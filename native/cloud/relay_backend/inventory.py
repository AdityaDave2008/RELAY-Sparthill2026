"""Conditional stock ledger and request reservations, shared by SQLite/DynamoDB."""
from datetime import datetime, timezone

from .analysis import ITEM_UNITS
from .common import APIError, PREFIX, digest, key
from .store import Conflict, Put


class InventoryMixin:
    def require_dispatcher(self, principal, shelter, incident=None):
        if principal.membership.role != "dispatcher":
            raise APIError(403, "dispatcher_required", "Inventory changes require authorized coordinator membership")
        self.authorize_shelter(principal, incident or principal.membership.incident_id, shelter)

    @staticmethod
    def inventory_key(incident, shelter, item):
        return PREFIX + "INVENTORY#" + incident + "#" + shelter, item

    def inventory_row(self, incident, shelter, item):
        row = self.store.get(*self.inventory_key(incident, shelter, item))
        return row if row else ({"item_id": item, "unit": ITEM_UNITS[item], "on_hand": 0,
                                 "reserved": 0, "revision": 0}, None)

    @staticmethod
    def public_stock(stock):
        return {**stock, "available": stock["on_hand"] - stock["reserved"]}

    def inventory(self, principal, shelter):
        self.require_dispatcher(principal, shelter)
        return {"shelter_id": shelter, "items": [self.public_stock(self.inventory_row(
            principal.membership.incident_id, shelter, item)[0]) for item in sorted(ITEM_UNITS)]}

    @staticmethod
    def checked_stock(stock, on_hand, reserved):
        if not 0 <= reserved <= on_hand <= 1_000_000_000:
            raise APIError(409, "insufficient_inventory", "Stock cannot become negative or fall below existing reservations")
        return {**stock, "on_hand": on_hand, "reserved": reserved, "revision": stock["revision"] + 1}

    @staticmethod
    def expect_inventory(stock, expected):
        if expected is not None and stock["revision"] != expected:
            raise APIError(409, "inventory_revision_conflict", "Refresh stock before making this change")

    def ledger_put(self, principal, incident, shelter, before, after, operation_id, action, request_id=None, note=""):
        return Put(PREFIX + "STOCK_LEDGER#" + incident + "#" + shelter + "#" + before["item_id"],
                   principal.subject + "#" + str(operation_id),
                   {"operation_id": str(operation_id), "author_subject": principal.subject,
                    "action": action, "request_id": str(request_id) if request_id else None, "note": note,
                    "before": before, "after": after,
                    "created_at": datetime.fromtimestamp(self.clock(), timezone.utc).isoformat()})

    def operation(self, principal, command, kind, identifier):
        op_key = (PREFIX + "OP#" + principal.subject, str(command.operation_id))
        fingerprint = digest({"kind": kind, "id": str(identifier), "body": command.model_dump(mode="json")})
        existing = self.store.get(*op_key)
        if existing:
            # Lost replies from build 8/9 still replay after the ledger upgrade.
            if kind == "request_event" and existing[0] == {"event_request_id": str(identifier), "hash": digest(command.model_dump(mode="json"))}:
                return op_key, fingerprint, self.request_history(principal, identifier)
            if existing[0].get("hash") != fingerprint or "response" not in existing[0]:
                raise APIError(409, "idempotency_conflict", "Operation ID was used with different content")
            return op_key, fingerprint, existing[0]["response"]
        return op_key, fingerprint, None

    def commit_operation(self, op_key, fingerprint, response, changes):
        try:
            self.store.transact(puts=[*changes, Put(*op_key, {"hash": fingerprint, "response": response})])
        except Conflict:
            existing = self.store.get(*op_key)
            if existing:
                if existing[0].get("hash") == fingerprint and "response" in existing[0]:
                    return existing[0]["response"]
                raise APIError(409, "idempotency_conflict", "Operation ID was used with different content") from None
            raise APIError(409, "revision_conflict", "Another change won; refresh stock and history before retrying", True) from None
        return response

    def adjust_inventory(self, principal, shelter, command):
        self.writable()
        self.require_dispatcher(principal, shelter)
        op_key, fingerprint, replay = self.operation(principal, command, "adjust_inventory", shelter)
        if replay is not None:
            return replay
        incident = principal.membership.incident_id
        stock, version = self.inventory_row(incident, shelter, command.item_id)
        self.expect_inventory(stock, command.expected_revision)
        updated = self.checked_stock(stock, stock["on_hand"] + command.quantity_delta, stock["reserved"])
        response = self.inventory(principal, shelter)
        response["items"] = [self.public_stock(updated) if x["item_id"] == command.item_id else x for x in response["items"]]
        return self.commit_operation(op_key, fingerprint, response, [
            Put(*self.inventory_key(incident, shelter, command.item_id), updated, version),
            self.ledger_put(principal, incident, shelter, stock, updated, command.operation_id, "adjust", note=command.note)])

    def request_inventory(self, principal, identifier):
        self.get_request(principal, identifier)
        row = self.store.get(*key("reservation", identifier))
        return {"request_id": str(identifier), "reservation": row[0] if row else None,
                "history": self.request_history(principal, identifier)}

    def history_event(self, history, principal, operation_id, text, status, verified=None):
        event = {"event_id": str(operation_id), "revision": history["revision"] + 1,
                 "author_role": principal.membership.role, "text": text, "status": status,
                 "created_at": datetime.fromtimestamp(self.clock(), timezone.utc).isoformat()}
        return {**history, "revision": event["revision"], "status": status or history["status"],
                "events": [*history["events"], event], "physical_delivery_verified": False,
                "resource_allocation_verified": history.get("resource_allocation_verified", False) if verified is None else verified}

    def change_request_inventory(self, principal, identifier, command):
        self.writable()
        record = self.get_request(principal, identifier)
        submission = record["submission"]
        incident, shelter = submission["incident_id"], submission["destination_shelter_id"]
        self.require_dispatcher(principal, shelter, incident)
        op_key, fingerprint, replay = self.operation(principal, command, "request_inventory", identifier)
        if replay is not None:
            return replay
        reservation_row = self.store.get(*key("reservation", identifier))
        history_row = self.store.get(*key("history", identifier))
        history = history_row[0] if history_row else self.request_history(principal, identifier)
        if history["status"] in {"completed", "cancelled", "rejected"}:
            raise APIError(409, "request_terminal", "This request is already closed")
        if command.action == "reserve":
            fields = submission.get("structured_fields") or {}
            if fields.get("item_id") == "medicines" or ((record.get("result") or {}).get("proposal") or {}).get("item_id") == "medicines":
                raise APIError(422, "medicine_staff_review", "Named medicines require staff review; generic stock allocation is unavailable")
            if reservation_row:
                raise APIError(409, "reservation_exists", "This request already has a reservation; use its existing action")
            if len(history["events"]) >= 100:
                raise APIError(429, "history_limit", "Demo request history limit reached")
            fields = submission.get("structured_fields") or {}
            result = record.get("result") or {}
            proposal = (result.get("proposal") or {}) if result.get("status") == "ready_for_review" else {}
            item = command.item_id or fields.get("item_id") or proposal.get("item_id")
            quantity = command.quantity or fields.get("quantity") or proposal.get("quantity")
            if item not in ITEM_UNITS or type(quantity) is not int or not 1 <= quantity <= 10000:
                raise APIError(422, "reservation_details_required", "Confirm one supported item and positive quantity")
            reservation = {"item_id": item, "quantity": quantity, "unit": ITEM_UNITS[item], "status": "reserved"}
            status, text = "accepted", "Coordinator reserved inventory."
        else:
            if not reservation_row or reservation_row[0]["status"] != "reserved":
                raise APIError(409, "reservation_not_active", "An active reservation is required")
            reservation = reservation_row[0]
            item, quantity = reservation["item_id"], reservation["quantity"]
            if (command.item_id is not None and command.item_id != item) or (command.quantity is not None and command.quantity != quantity):
                raise APIError(409, "reservation_mismatch", "Fulfill or release the entire existing reservation")
            reservation = {**reservation, "status": "fulfilled" if command.action == "fulfill" else "released"}
            status = "completed" if command.action == "fulfill" else "rejected"
            text = "Coordinator recorded inventory fulfillment." if command.action == "fulfill" else "Coordinator released inventory."
        stock, version = self.inventory_row(incident, shelter, item)
        self.expect_inventory(stock, command.expected_inventory_revision)
        on_hand, reserved = stock["on_hand"], stock["reserved"]
        if command.action == "reserve":
            reserved += quantity
        else:
            reserved -= quantity
            if command.action == "fulfill":
                on_hand -= quantity
        updated = self.checked_stock(stock, on_hand, reserved)
        history = self.history_event(history, principal, command.operation_id, text, status, command.action != "release")
        response = {"request_id": str(identifier), "reservation": reservation, "history": history}
        return self.commit_operation(op_key, fingerprint, response, [
            Put(*self.inventory_key(incident, shelter, item), updated, version),
            Put(*key("reservation", identifier), reservation, reservation_row[1] if reservation_row else None),
            Put(*key("history", identifier), history, history_row[1] if history_row else None),
            self.ledger_put(principal, incident, shelter, stock, updated, command.operation_id, command.action, identifier)])

    def append_request_event(self, principal, identifier, command):
        self.writable()
        record = self.get_request(principal, identifier)
        op_key, fingerprint, replay = self.operation(principal, command, "request_event", identifier)
        if replay is not None:
            return replay
        row = self.store.get(*key("history", identifier))
        history = row[0] if row else self.request_history(principal, identifier)
        if command.expected_revision != history["revision"]:
            raise APIError(409, "revision_conflict", "Refresh request history before submitting this update")
        status = command.status
        # Closing a reservation must remain possible after the ordinary reply cap.
        if len(history["events"]) >= 100 and status not in {"cancelled", "rejected"}:
            raise APIError(429, "history_limit", "Demo request history limit reached")
        reservation_row = self.store.get(*key("reservation", identifier))
        active = reservation_row and reservation_row[0]["status"] == "reserved"
        changes = []
        if status:
            is_dispatcher = principal.membership.role == "dispatcher"
            submission = record["submission"]
            incident, shelter = submission["incident_id"], submission["destination_shelter_id"]
            if is_dispatcher:
                self.require_dispatcher(principal, shelter, incident)
            if (is_dispatcher and status == "cancelled") or (not is_dispatcher and status != "cancelled"):
                raise APIError(403, "status_forbidden", "This role cannot make that status update")
            if status == "completed" or (status in {"accepted", "in_progress"} and not active):
                raise APIError(409, "inventory_action_required", "Reserve or fulfill inventory through the inventory endpoint")
            transitions = {"new": {"accepted", "rejected", "cancelled"}, "accepted": {"in_progress", "rejected", "cancelled"},
                           "in_progress": {"cancelled", "rejected"}, "completed": set(), "rejected": set(), "cancelled": set()}
            if status not in transitions.get(history["status"], set()):
                raise APIError(409, "invalid_transition", "That status transition is not allowed")
            if active and status in {"cancelled", "rejected"}:
                reservation = reservation_row[0]
                stock, stock_version = self.inventory_row(incident, shelter, reservation["item_id"])
                updated = self.checked_stock(stock, stock["on_hand"], stock["reserved"] - reservation["quantity"])
                changes.extend([
                    Put(*self.inventory_key(incident, shelter, reservation["item_id"]), updated, stock_version),
                    Put(*key("reservation", identifier), {**reservation, "status": "released"}, reservation_row[1]),
                    self.ledger_put(principal, incident, shelter, stock, updated, command.operation_id, status, identifier, command.text)])
        history = self.history_event(history, principal, command.operation_id, command.text, status,
                                     False if status in {"cancelled", "rejected"} else None)
        changes.append(Put(*key("history", identifier), history, row[1] if row else None))
        return self.commit_operation(op_key, fingerprint, history, changes)
