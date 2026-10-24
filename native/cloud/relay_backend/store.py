"""Versioned key/value store. Both adapters provide atomic conditional transactions."""
import copy
import json
import sqlite3
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

from botocore.exceptions import ClientError


class Conflict(Exception):
    pass


@dataclass
class Put:
    pk: str
    sk: str
    data: dict
    expected: int | None = None  # None means the item must not exist.


@dataclass
class Delete:
    pk: str
    sk: str
    expected: int


class SQLiteStore:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, check_same_thread=False, isolation_level=None, timeout=10)
        self.db.execute("PRAGMA busy_timeout=10000")
        for attempt in range(8):
            try:
                if self.db.execute("PRAGMA journal_mode").fetchone()[0] != "wal":
                    self.db.execute("PRAGMA journal_mode=WAL")
                break
            except sqlite3.OperationalError as exc:
                if "locked" not in str(exc).lower() or attempt == 7:
                    raise
                time.sleep(min(0.5, 0.05 * (attempt + 1)))
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("CREATE TABLE IF NOT EXISTS records (pk TEXT, sk TEXT, v INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(pk,sk))")
        self.lock = threading.RLock()

    def get(self, pk, sk):
        with self.lock:
            row = self.db.execute("SELECT payload,v FROM records WHERE pk=? AND sk=?", (pk, sk)).fetchone()
            return (json.loads(row[0]), row[1]) if row else None

    def get_many(self, keys):
        keys = list(dict.fromkeys(keys))
        results = dict.fromkeys(keys)
        with self.lock:
            for offset in range(0, len(keys), 100):
                batch = keys[offset:offset + 100]
                placeholders = ",".join("(?,?)" for _ in batch)
                rows = self.db.execute(
                    "SELECT pk,sk,payload,v FROM records WHERE (pk,sk) IN (VALUES " + placeholders + ")",
                    [part for pair in batch for part in pair]).fetchall()
                results.update({(pk, sk): (json.loads(payload), version) for pk, sk, payload, version in rows})
        return results

    def query(self, pk, after=None, limit=25):
        with self.lock:
            rows = self.db.execute("SELECT sk,payload,v FROM records WHERE pk=? AND sk>? ORDER BY sk LIMIT ?",
                                   (pk, after or "", limit + 1)).fetchall()
        page = [(sk, json.loads(payload), version) for sk, payload, version in rows[:limit]]
        return page, page[-1][0] if len(rows) > limit else None

    def transact(self, puts=(), deletes=()):
        with self.lock:
            self.db.execute("BEGIN IMMEDIATE")
            try:
                for change in [*puts, *deletes]:
                    row = self.db.execute("SELECT v FROM records WHERE pk=? AND sk=?", (change.pk, change.sk)).fetchone()
                    if (row[0] if row else None) != change.expected:
                        raise Conflict()
                for change in puts:
                    self.db.execute("INSERT OR REPLACE INTO records VALUES (?,?,?,?)",
                                    (change.pk, change.sk, (change.expected or 0) + 1,
                                     json.dumps(change.data, allow_nan=False, separators=(",", ":"))))
                for change in deletes:
                    self.db.execute("DELETE FROM records WHERE pk=? AND sk=?", (change.pk, change.sk))
                self.db.execute("COMMIT")
            except Exception:
                self.db.execute("ROLLBACK")
                raise

    def close(self):
        self.db.close()


class DynamoStore:
    def __init__(self, client, table_name):
        self.client, self.table = client, table_name
        self._batch_get_denied = False

    @staticmethod
    def key(pk, sk):
        if not pk.startswith("RELAY_MVP_V1#"):
            raise ValueError("DynamoDB access is restricted to the RELAY_MVP_V1 namespace")
        return {"pk": {"S": pk}, "sk": {"S": sk}}

    def get(self, pk, sk):
        item = self.client.get_item(TableName=self.table, Key=self.key(pk, sk), ConsistentRead=True).get("Item")
        return (json.loads(item["payload"]["S"]), int(item["v"]["N"])) if item else None

    def _point_reads(self, keys):
        """Use existing GetItem permissions with bounded concurrency, never a scan."""
        results = {}
        with ThreadPoolExecutor(max_workers=6) as pool:
            pending = {pool.submit(self.get, *pair): pair for pair in keys}
            try:
                for future in as_completed(pending):
                    results[pending[future]] = future.result()
            except Exception:
                for future in pending:
                    future.cancel()
                raise
        return results

    def get_many(self, keys):
        keys = list(dict.fromkeys(keys))
        # Validate every key before issuing any call, including the IAM fallback.
        encoded = {pair: self.key(*pair) for pair in keys}
        results = dict.fromkeys(keys)
        for offset in range(0, len(keys), 100):
            pending = keys[offset:offset + 100]
            if self._batch_get_denied:
                results.update(self._point_reads(pending))
                continue
            for attempt in range(3):
                try:
                    response = self.client.batch_get_item(RequestItems={self.table: {
                        "Keys": [encoded[pair] for pair in pending], "ConsistentRead": True}})
                except ClientError as exc:
                    if exc.response["Error"]["Code"] not in {"AccessDeniedException", "AccessDenied", "UnauthorizedOperation"}:
                        raise
                    # Do not require a new IAM grant or repeat a denied call each poll.
                    self._batch_get_denied = True
                    break
                for item in response.get("Responses", {}).get(self.table, []):
                    pair = (item["pk"]["S"], item["sk"]["S"])
                    if pair in encoded:
                        results[pair] = (json.loads(item["payload"]["S"]), int(item["v"]["N"]))
                unprocessed = response.get("UnprocessedKeys", {}).get(self.table, {}).get("Keys", [])
                remaining = {(item["pk"]["S"], item["sk"]["S"]) for item in unprocessed}
                pending = [pair for pair in pending if pair in remaining]
                if not pending:
                    break
                if attempt < 2:
                    time.sleep(0.05 * (2 ** attempt))
            # Never silently treat unprocessed keys as missing records.
            if pending:
                results.update(self._point_reads(pending))
        return results

    def query(self, pk, after=None, limit=25):
        self.key(pk, after or "")
        args = dict(TableName=self.table, KeyConditionExpression="pk = :pk",
                    ExpressionAttributeValues={":pk": {"S": pk}}, Limit=limit, ConsistentRead=True)
        if after:
            args["ExclusiveStartKey"] = self.key(pk, after)
        response = self.client.query(**args)
        page = [(x["sk"]["S"], json.loads(x["payload"]["S"]), int(x["v"]["N"])) for x in response.get("Items", [])]
        last = response.get("LastEvaluatedKey")
        return page, last["sk"]["S"] if last else None

    def transact(self, puts=(), deletes=()):
        transactions = []
        for change in puts:
            item = {**self.key(change.pk, change.sk), "v": {"N": str((change.expected or 0) + 1)},
                    "payload": {"S": json.dumps(change.data, allow_nan=False, separators=(",", ":"))}}
            action = {"TableName": self.table, "Item": item}
            if change.expected is None:
                action["ConditionExpression"] = "attribute_not_exists(pk)"
            else:
                action.update(ConditionExpression="v = :v", ExpressionAttributeValues={":v": {"N": str(change.expected)}})
            transactions.append({"Put": action})
        for change in deletes:
            transactions.append({"Delete": {"TableName": self.table, "Key": self.key(change.pk, change.sk),
                                             "ConditionExpression": "v = :v",
                                             "ExpressionAttributeValues": {":v": {"N": str(change.expected)}}}})
        try:
            self.client.transact_write_items(TransactItems=transactions)
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "TransactionCanceledException":
                reasons = exc.response.get("CancellationReasons", [])
                if any(r.get("Code") == "ConditionalCheckFailed" for r in reasons):
                    raise Conflict() from None
            raise
