import base64
import json
import time
from datetime import datetime, timezone
from uuid import uuid4

from .analysis import validate_model_result
from .providers import ProviderError
from .store import Conflict, Delete, Put

from .common import APIError, PREFIX, WORK, canonical, digest, key, work_key
from .interpretations import InterpretationMixin
from .inventory import InventoryMixin
from .nearby import NearbyMixin
from .announcements import AnnouncementsMixin

_UNLOADED = object()


class Service(InterpretationMixin, InventoryMixin, NearbyMixin, AnnouncementsMixin):
    def __init__(self, settings, store, providers, clock=time.time):
        self.settings, self.store, self.providers, self.clock = settings, store, providers, clock

    def writable(self):
        if self.settings.mode == "aws" and not self.settings.allow_aws_writes_and_ai:
            raise APIError(503, "aws_activity_not_approved", "AWS writes and AI tests have not been enabled", False)

    def directory(self, principal):
        m = principal.membership
        shelters = [s.model_dump() for s in self.settings.shelters
                    if s.incident_id == m.incident_id and s.shelter_id in m.shelter_ids]
        receivers = self.store.get_many([key(kind, s["incident_id"] + ":" + s["shelter_id"]) for s in shelters for kind in ("receiver", "shelter-details")])
        for shelter in shelters:
            row = receivers.get(key("receiver", shelter["incident_id"] + ":" + shelter["shelter_id"]))
            shelter["receiver"] = row[0] if row else None
            details = receivers.get(key("shelter-details", shelter["incident_id"] + ":" + shelter["shelter_id"]))
            shelter["details"] = details[0] if details else None
        return shelters

    def budget_put(self, kind):
        row = self.store.get(PREFIX + "BUDGET", kind)
        count, version = (row[0]["count"], row[1]) if row else (0, None)
        limit = self.settings.max_requests if kind == "requests" else self.settings.max_transcriptions
        if count >= limit:
            raise APIError(429, "demo_limit_reached", "The configured demo resource limit has been reached; operator review required")
        return Put(PREFIX + "BUDGET", kind, {"count": count + 1}, version)

    def authorize_shelter(self, principal, incident, shelter):
        exists = any(s.shelter_id == shelter and s.incident_id == incident for s in self.settings.shelters)
        if not exists:
            raise APIError(400, "invalid_shelter", "Unknown destination shelter")
        if principal.membership.incident_id != incident or shelter not in principal.membership.shelter_ids:
            raise APIError(403, "shelter_forbidden", "This shelter is not authorized for the caller")

    def can_read(self, principal, record):
        return record["owner_subject"] == principal.subject or (
            principal.membership.role == "dispatcher" and
            principal.membership.incident_id == record["submission"]["incident_id"] and
            record["submission"]["destination_shelter_id"] in principal.membership.shelter_ids)

    def public_request(self, record, reservation=_UNLOADED):
        result = {k: v for k, v in record.items() if k not in {"payload_hash", "owner_subject"}}
        if reservation is _UNLOADED:
            reservation = self.store.get(*key("reservation", record["request_id"]))
        status = reservation[0]["status"] if reservation else "unassigned"
        result.update(assignment_state=status, fulfillment_state="fulfilled" if status == "fulfilled" else "not_fulfilled")
        return result

    @staticmethod
    def public_transcription(record, now):
        output = {k: v for k, v in record.items() if k not in {"payload_hash", "owner_subject", "operation_id", "start_operation_id"}}
        if output["status"] == "awaiting_upload" and output["upload_expires_at"] < now:
            output["status"] = "upload_expired"
            output["error"] = {"code": "upload_expired", "retryable": True,
                               "message": "Repeat the same allocation request to renew upload authorization"}
        return output

    def get_request(self, principal, identifier):
        row = self.store.get(*key("request", identifier))
        if not row or not self.can_read(principal, row[0]):
            raise APIError(404, "request_not_found", "Request not found")
        return self.public_request(row[0])

    def request_snapshot(self, principal, identifier):
        keys = {kind: key(kind, identifier) for kind in ("request", "reservation", "history")}
        batch = self.store.get_many(keys.values())
        row = batch.get(keys["request"])
        if not row or not self.can_read(principal, row[0]):
            raise APIError(404, "request_not_found", "Request not found")
        reservation, history = batch.get(keys["reservation"]), batch.get(keys["history"])
        result = self.public_request(row[0], reservation=reservation)
        result["reservation"] = reservation[0] if reservation else None
        result["history"] = history[0] if history else {"request_id": str(identifier), "revision": 0,
            "status": "new", "events": [], "resource_allocation_verified": False}
        return result

    def request_history(self, principal, identifier):
        self.get_request(principal, identifier)  # Enforce ownership/membership before disclosing events.
        row = self.store.get(*key("history", identifier))
        return row[0] if row else {"request_id": str(identifier), "revision": 0,
                                  "status": "new", "events": [], "resource_allocation_verified": False}

    def _duplicate_request(self, principal, payload, hash_value):
        row = self.store.get(*key("request", payload["request_id"]))
        if row and row[0]["owner_subject"] == principal.subject and row[0]["payload_hash"] == hash_value:
            return self.public_request(row[0]), False
        raise APIError(409, "idempotency_conflict", "An identifier was already used with different immutable content")

    def submit(self, principal, submission):
        self.writable()
        payload = submission.model_dump(mode="json")
        # Preserve immutable digests/replay of submissions from before these optional fields.
        for field in ("location", "structured_fields", "interpretation_id", "requester_details"):
            if payload.get(field) is None:
                payload.pop(field, None)
        if payload.get("location"):
            payload["location"]["captured_at"] = submission.location.captured_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
        for field in ("created_at", "expires_at"):
            payload[field] = getattr(submission, field).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
        hash_value = digest(payload)
        if self.store.get(*key("request", payload["request_id"])):
            return self._duplicate_request(principal, payload, hash_value)
        self.authorize_shelter(principal, payload["incident_id"], payload["destination_shelter_id"])
        now = self.clock()
        created, expires = submission.created_at.timestamp(), submission.expires_at.timestamp()
        if created > now + 300 or expires <= created or expires - created > 7 * 86400:
            raise APIError(400, "invalid_lifetime", "Use creation time within five minutes of now and a lifetime of at most seven days")
        if expires <= now:
            raise APIError(410, "request_expired", "Expired requests cannot begin processing")
        if payload["input_mode"] == "reviewed_transcript":
            audio = self.store.get(*key("transcription", payload["transcription_id"]))
            if not audio or audio[0]["owner_subject"] != principal.subject or audio[0]["incident_id"] != payload["incident_id"]:
                raise APIError(404, "transcription_not_found", "Transcription not found")
            if audio[0]["status"] != "completed":
                raise APIError(409, "transcription_not_complete", "Review the completed transcript before submitting")
        preview = self.preview_for_submission(principal, payload) if payload.get("interpretation_id") else None
        record = {"request_id": payload["request_id"], "schema_version": 1, "revision": 1,
                  "owner_subject": principal.subject, "payload_hash": hash_value, "submission": payload,
                  "accepted_at": datetime.fromtimestamp(now, timezone.utc).isoformat(),
                  "cloud_state": "accepted", "analysis_state": "pending", "result": None,
                  "analysis_attempts": 0, "error": None, "provider_evidence": None,
                  "assignment_state": "not_implemented", "fulfillment_state": "not_implemented"}
        if preview:
            record.update(analysis_state=preview[0]["status"], result=preview[0]["result"],
                          provider_evidence=preview[0]["provider_evidence"], analysis_attempts=preview[0]["analysis_attempts"])
        reference = {"request_id": payload["request_id"]}
        index_sk = f"{now:020.6f}#{payload['request_id']}"
        task = {"kind": "request", "id": payload["request_id"], "attempts": 0,
                "next_attempt_at": now, "lease_until": 0, "created_at": now}
        changes = [Put(*key("request", payload["request_id"]), record),
                   Put(PREFIX + "USER#" + principal.subject, index_sk, reference),
                   Put(PREFIX + "SHELTER#" + payload["incident_id"] + "#" + payload["destination_shelter_id"], index_sk, reference),
                   Put(PREFIX + "OP#" + principal.subject, payload["operation_id"], reference)]
        changes.extend([preview[1]] if preview else [Put(*work_key("request", payload["request_id"]), task), self.budget_put("requests")])
        try:
            self.store.transact(puts=changes)
        except Conflict:
            if self.store.get(*key("request", payload["request_id"])) or self.store.get(PREFIX + "OP#" + principal.subject, payload["operation_id"]):
                return self._duplicate_request(principal, payload, hash_value)
            if preview:
                current = self.owned_interpretation(principal, payload["interpretation_id"])[0]
                if current.get("submitted_request_id"):
                    raise APIError(409, "interpretation_already_used", "A preview can be sent as only one request") from None
            raise APIError(503, "concurrent_acceptance", "Retry the identical request after a short delay", True) from None
        if not preview:
            self._wake("request", payload["request_id"])
        return self.public_request(record), True

    def _wake(self, kind, identifier):
        wake = getattr(self.providers, "wake_worker", None)
        if wake:
            try:
                wake(kind, identifier)
            except ProviderError:
                pass  # Durable queue remains pending; scheduled/local worker recovers it.

    def retry_analysis(self, principal, identifier, operation_id):
        self.writable()
        row = self.store.get(*key("request", identifier))
        if not row or not self.can_read(principal, row[0]):
            raise APIError(404, "request_not_found", "Request not found")
        record, version = row
        op_key = (PREFIX + "OP#" + principal.subject, str(operation_id))
        previous = self.store.get(*op_key)
        if previous:
            if previous[0] == {"retry_request_id": str(identifier)}:
                return self.public_request(record)
            raise APIError(409, "idempotency_conflict", "Operation ID has already been used")
        if record["analysis_state"] != "failed":
            raise APIError(409, "analysis_not_failed", "Only a failed analysis can be explicitly retried")
        if record.get("manual_retry_count", 0) >= 2:
            raise APIError(409, "retry_limit", "Manual retry limit reached; operator review required")
        if datetime.fromisoformat(record["submission"]["expires_at"].replace("Z", "+00:00")).timestamp() <= self.clock():
            raise APIError(410, "request_expired", "Expired requests cannot be retried")
        record.update(analysis_state="pending", error=None, manual_retry_count=record.get("manual_retry_count", 0) + 1)
        task = {"kind": "request", "id": str(identifier), "attempts": 0, "next_attempt_at": self.clock(),
                "lease_until": 0, "created_at": self.clock()}
        try:
            self.store.transact(puts=[Put(*key("request", identifier), record, version),
                                      Put(*work_key("request", identifier), task),
                                      Put(*op_key, {"retry_request_id": str(identifier)})])
        except Conflict:
            raise APIError(409, "concurrent_update", "Retry the same operation", True) from None
        self._wake("request", identifier)
        return self.public_request(record)

    def list_requests(self, principal, view, shelter_id, cursor, limit):
        if view == "shelter":
            if principal.membership.role != "dispatcher":
                raise APIError(403, "dispatcher_required", "Shelter inbox requires dispatcher membership")
            if not shelter_id:
                raise APIError(400, "shelter_required", "Select an authorized shelter inbox")
            self.authorize_shelter(principal, principal.membership.incident_id, shelter_id)
            pk = PREFIX + "SHELTER#" + principal.membership.incident_id + "#" + shelter_id
        else:
            pk = PREFIX + "USER#" + principal.subject
        scope = digest({"pk": pk, "subject": principal.subject})
        after = None
        if cursor:
            try:
                data = json.loads(base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)))
                if data["scope"] != scope or not isinstance(data["after"], str) or len(data["after"]) > 128:
                    raise ValueError()
                after = data["after"]
            except (ValueError, KeyError, TypeError):
                raise APIError(400, "invalid_cursor", "Cursor does not match this authorized inbox") from None
        rows, next_after = self.store.query(pk, after=after, limit=limit)
        keys = [key(kind, reference["request_id"]) for _, reference, _ in rows
                for kind in ("request", "reservation", "history")]
        batch = self.store.get_many(keys)
        records = []
        for _, reference, _ in rows:
            row = batch.get(key("request", reference["request_id"]))
            if row and self.can_read(principal, row[0]):
                identifier = reference["request_id"]
                reservation = batch.get(key("reservation", identifier))
                history = batch.get(key("history", identifier))
                result = self.public_request(row[0], reservation)
                result["reservation"] = reservation[0] if reservation else None
                result["history"] = history[0] if history else {"request_id": identifier, "revision": 0,
                    "status": "new", "events": [], "resource_allocation_verified": False}
                records.append(result)
        next_cursor = base64.urlsafe_b64encode(canonical({"scope": scope, "after": next_after}).encode()).decode().rstrip("=") if next_after else None
        return {"items": records, "next_cursor": next_cursor}

    def allocate_audio(self, principal, allocation):
        self.writable()
        payload = allocation.model_dump(mode="json")
        if payload["incident_id"] != principal.membership.incident_id:
            raise APIError(403, "incident_forbidden", "Incident is not authorized")
        now = self.clock()
        row_key = key("transcription", payload["transcription_id"])
        row = self.store.get(*row_key)
        hash_value = digest(payload)
        if row:
            record, version = row
            if record["owner_subject"] != principal.subject or record["payload_hash"] != hash_value:
                raise APIError(409, "idempotency_conflict", "Transcription ID was used with different content")
            if record["status"] == "awaiting_upload":
                record = {**record, "upload_expires_at": now + self.settings.upload_ttl_seconds}
                try:
                    self.store.transact(puts=[Put(*row_key, record, version)])
                except Conflict:
                    raise APIError(409, "concurrent_update", "Retry the identical operation", True) from None
        else:
            record = {**payload, "owner_subject": principal.subject, "payload_hash": hash_value,
                      "status": "awaiting_upload", "created_at": now, "upload_expires_at": now + self.settings.upload_ttl_seconds,
                      "transcript": None, "error": None, "provider_evidence": None, "start_operation_id": None,
                      "start_count": 0}
            try:
                self.store.transact(puts=[Put(*row_key, record),
                                          Put(PREFIX + "OP#" + principal.subject, payload["operation_id"], {"transcription_id": payload["transcription_id"]}),
                                          self.budget_put("transcriptions")])
            except Conflict:
                # Covers lost replies, concurrent identical allocation, and operation-ID reuse.
                existing = self.store.get(*row_key)
                if not existing or existing[0]["owner_subject"] != principal.subject or existing[0]["payload_hash"] != hash_value:
                    if not existing and not self.store.get(PREFIX + "OP#" + principal.subject, payload["operation_id"]):
                        raise APIError(503, "concurrent_acceptance", "Retry the identical allocation after a short delay", True) from None
                    raise APIError(409, "idempotency_conflict", "An identifier was already used") from None
                record = existing[0]
        response = self.public_transcription(record, now)
        response["upload"] = self.providers.upload_authorization(record) if record["status"] == "awaiting_upload" else None
        return response

    def owned_audio(self, principal, identifier):
        row = self.store.get(*key("transcription", identifier))
        if not row or row[0]["owner_subject"] != principal.subject:
            raise APIError(404, "transcription_not_found", "Transcription not found")
        return row

    def get_audio(self, principal, identifier):
        record, version = self.owned_audio(principal, identifier)
        now = self.clock()
        if (record["status"] == "processing" and
                (record.get("provider_evidence") or {}).get("transport") == "streaming" and
                now > record["started_at"] + self.settings.max_audio_seconds + 45):
            # An API process may disappear without its finally block. A bounded
            # stale session must not trap the retained recording in processing.
            record = {**record, "status": "failed", "transcript": None,
                      "error": {"code": "stream_expired", "message": "The live session ended. Retry the saved recording.", "retryable": False}}
            try:
                self.store.transact(puts=[Put(*key("transcription", identifier), record, version)])
            except Conflict:
                record = self.owned_audio(principal, identifier)[0]
        return self.public_transcription(record, now)

    def start_audio(self, principal, identifier, operation_id):
        self.writable()
        record, version = self.owned_audio(principal, identifier)
        if record["start_operation_id"] and record["start_operation_id"] != str(operation_id):
            raise APIError(409, "idempotency_conflict", "Reuse the original transcription start operation ID")
        if record["status"] in {"queued", "processing", "completed"}:
            return self.public_transcription(record, self.clock())
        if (record.get("provider_evidence") or {}).get("transport") == "streaming":
            raise APIError(409, "stream_not_resumable", "Start a new live session or import the retained recording as a new audio job.")
        if record["status"] == "failed" and (not record["error"]["retryable"] or record["start_count"] >= 3):
            raise APIError(409, "transcription_terminal", "This transcription cannot be restarted; allocate a new recording")
        try:
            metadata = self.providers.seal_upload(record)
        except ProviderError as exc:
            record = {**record, "error": {"code": exc.code, "message": "Upload validation failed; upload a valid recording", "retryable": exc.retryable}}
            try:
                self.store.transact(puts=[Put(*key("transcription", identifier), record, version)])
            except Conflict:
                pass
            raise APIError(422 if exc.code != "upload_missing" else 409, exc.code, record["error"]["message"], exc.retryable) from None
        now = self.clock()
        record = {**record, **metadata, "status": "queued", "error": None,
                  "start_operation_id": str(operation_id), "started_at": now, "start_count": record["start_count"] + 1}
        task = {"kind": "transcription", "id": str(identifier), "attempts": 0,
                "next_attempt_at": now, "lease_until": 0, "created_at": now}
        try:
            self.store.transact(puts=[Put(*key("transcription", identifier), record, version),
                                      Put(*work_key("transcription", identifier), task)])
        except Conflict:
            latest = self.owned_audio(principal, identifier)[0]
            if latest["start_operation_id"] == str(operation_id) and latest["status"] in {"queued", "processing", "completed"}:
                return self.public_transcription(latest, self.clock())
            raise APIError(409, "concurrent_update", "Retry the same start operation", True) from None
        self._wake("transcription", identifier)
        return self.public_transcription(record, now)


class Worker:
    def __init__(self, service):
        self.service = service
        self.cursor = None

    def run_once(self, task_key=None):
        s = self.service
        s.writable()
        if task_key:
            row = s.store.get(WORK, task_key)
            candidates = [(task_key, *row)] if row else []
        else:
            candidates, self.cursor = s.store.query(WORK, after=self.cursor, limit=25)
        for sk, task, version in candidates:
            now = s.clock()
            if task["next_attempt_at"] > now or task["lease_until"] > now:
                continue
            claimed = {**task, "lease_until": now + s.settings.lease_seconds, "lease_id": str(uuid4())}
            if task["kind"] in {"request", "interpretation"}:
                # Persist BEFORE invocation: crashes after a paid call cannot cause
                # unlimited re-invocation when the lease is reclaimed.
                claimed["dispatches"] = task.get("dispatches", 0) + 1
            try:
                s.store.transact(puts=[Put(WORK, sk, claimed, version)])
            except Conflict:
                continue
            self._process(sk, claimed, version + 1)
            return True
        return False

    def _process(self, sk, task, task_version):
        s = self.service
        record_key = key(task["kind"], task["id"])
        row = s.store.get(*record_key)
        if not row:
            s.store.transact(deletes=[Delete(WORK, sk, task_version)])
            return
        record, record_version = row
        now = s.clock()
        retry_task = None
        try:
            if task["kind"] in {"request", "interpretation"}:
                if task.get("dispatches", 1) > s.settings.max_attempts:
                    raise ProviderError("analysis_attempt_limit")
                expires = (record["expires_at"] if task["kind"] == "interpretation" else
                           datetime.fromisoformat(record["submission"]["expires_at"].replace("Z", "+00:00")).timestamp())
                if expires <= now:
                    raise ProviderError("request_expired")
                shelters = [x.model_dump() for x in s.settings.shelters if x.incident_id == record["submission"]["incident_id"]]
                raw, evidence = s.providers.analyze(record["submission"], shelters)
                evidence["queue_wait_ms"] = round(max(0, now - task["created_at"]) * 1000)
                result = validate_model_result(raw, record["submission"], shelters)
                state_field = "status" if task["kind"] == "interpretation" else "analysis_state"
                record.update({state_field: result["status"], "result": result, "provider_evidence": evidence,
                               "analysis_attempts": task.get("dispatches", task["attempts"] + 1), "error": None})
            else:
                if now - record["started_at"] > s.settings.transcription_timeout_seconds:
                    raise ProviderError("transcription_poll_timeout", True)
                if record["status"] == "queued":
                    evidence = s.providers.start_transcription(record)
                    record.update(status="processing", provider_evidence=evidence)
                output = s.providers.poll_transcription(record)
                if output["status"] == "completed":
                    record.update(status="completed", transcript=output["transcript"], error=None,
                                  provider_evidence={**(record.get("provider_evidence") or {}), "poll_request_id": output["request_id"],
                                                     "provider": output["provider"], "job_name": output["job_name"]})
                else:
                    retry_task = {**task, "next_attempt_at": now + 3, "lease_until": 0}
        except ProviderError as exc:
            attempts = task["attempts"] + 1
            retrying = exc.retryable and attempts < s.settings.max_attempts and exc.code != "transcription_poll_timeout"
            record["error"] = {"code": exc.code, "message": "Provider operation failed; accepted data remains durable", "retryable": exc.retryable}
            if task["kind"] in {"request", "interpretation"}:
                state_field = "status" if task["kind"] == "interpretation" else "analysis_state"
                state = ("pending" if task["kind"] == "interpretation" else "retrying") if retrying else "failed"
                record.update({state_field: state, "analysis_attempts": min(task.get("dispatches", attempts), s.settings.max_attempts)})
            else:
                record["status"] = "queued" if retrying and record["status"] == "queued" else "processing" if retrying else "failed"
            if retrying:
                retry_task = {**task, "attempts": attempts, "next_attempt_at": now + min(30, 2 ** attempts), "lease_until": 0}
        # Unexpected process/provider faults leave the lease in place. A new worker
        # can reclaim after expiry; do not silently acknowledge or delete its work.
        puts = [Put(*record_key, record, record_version)]
        deletes = []
        if retry_task:
            puts.append(Put(WORK, sk, retry_task, task_version))
        else:
            deletes.append(Delete(WORK, sk, task_version))
        try:
            s.store.transact(puts=puts, deletes=deletes)
        except Conflict:
            pass  # A superseding lease/version owns the final write.
