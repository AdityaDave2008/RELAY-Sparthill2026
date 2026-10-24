"""Durable pre-send previews: no help request, inbox entry or stock effect."""
from .common import APIError, PREFIX, digest, key, work_key
from .store import Conflict, Put


class InterpretationMixin:
    @staticmethod
    def public_interpretation(record):
        return {k: record[k] for k in ("interpretation_id", "status", "result", "error")}

    def owned_interpretation(self, principal, identifier):
        row = self.store.get(*key("interpretation", identifier))
        if not row or row[0]["owner_subject"] != principal.subject:
            raise APIError(404, "interpretation_not_found", "Preview not found")
        self.authorize_shelter(principal, row[0]["submission"]["incident_id"],
                               row[0]["submission"]["destination_shelter_id"])
        return row

    def get_interpretation(self, principal, identifier):
        return self.public_interpretation(self.owned_interpretation(principal, identifier)[0])

    def interpret(self, principal, command):
        self.writable()
        payload = command.model_dump(mode="json")
        self.authorize_shelter(principal, payload["incident_id"], payload["destination_shelter_id"])
        row_key = key("interpretation", payload["interpretation_id"])
        op_key = (PREFIX + "OP#" + principal.subject, payload["operation_id"])
        fingerprint = digest(payload)

        def duplicate():
            existing = self.store.get(*row_key)
            if existing and existing[0]["owner_subject"] == principal.subject and existing[0]["payload_hash"] == fingerprint:
                return self.public_interpretation(existing[0]), False
            raise APIError(409, "idempotency_conflict", "An identifier was used with different immutable content")

        if self.store.get(*row_key) or self.store.get(*op_key):
            return duplicate()
        if payload.get("transcription_id"):
            audio, _ = self.owned_audio(principal, payload["transcription_id"])
            if audio["incident_id"] != payload["incident_id"]:
                raise APIError(404, "transcription_not_found", "Transcription not found")
            if audio["status"] != "completed":
                raise APIError(409, "transcription_not_complete", "Review the completed transcript before previewing")
        now = self.clock()
        record = {"interpretation_id": payload["interpretation_id"], "owner_subject": principal.subject,
                  "payload_hash": fingerprint, "submission": payload, "status": "pending",
                  "result": None, "error": None, "provider_evidence": None, "analysis_attempts": 0,
                  "created_at": now, "expires_at": now + 86400, "submitted_request_id": None}
        task = {"kind": "interpretation", "id": payload["interpretation_id"], "attempts": 0,
                "next_attempt_at": now, "lease_until": 0, "created_at": now}
        try:
            self.store.transact(puts=[Put(*row_key, record), Put(*work_key("interpretation", payload["interpretation_id"]), task),
                                      Put(*op_key, {"interpretation_id": payload["interpretation_id"], "hash": fingerprint}),
                                      self.budget_put("requests")])
        except Conflict:
            if self.store.get(*row_key) or self.store.get(*op_key):
                return duplicate()
            raise APIError(503, "concurrent_acceptance", "Retry the identical preview after a short delay", True) from None
        self._wake("interpretation", payload["interpretation_id"])
        return self.public_interpretation(record), True

    def preview_for_submission(self, principal, payload):
        """Return a conditional binding; the caller commits it with the request."""
        record, version = self.owned_interpretation(principal, payload["interpretation_id"])
        if record.get("submitted_request_id") not in (None, payload["request_id"]):
            raise APIError(409, "interpretation_already_used", "A preview can be sent as only one request")
        # A direct sender and its authorized nearby gateway may arrive together.
        # For the SAME request ID, let submit's transaction/replay check resolve
        # the race; a different ID must still be rejected.
        if record["expires_at"] <= self.clock():
            raise APIError(410, "interpretation_expired", "Create a new preview before sending")
        if record["status"] not in {"ready_for_review", "needs_review"} or record["result"] is None:
            raise APIError(409, "interpretation_not_ready", "Wait for and review the preview before sending")
        for field in ("incident_id", "destination_shelter_id", "original_text", "transcription_id"):
            if record["submission"].get(field) != payload.get(field):
                raise APIError(409, "interpretation_mismatch", "Changed text, shelter or recording requires a new preview")
        return record, Put(*key("interpretation", payload["interpretation_id"]),
                           {**record, "submitted_request_id": payload["request_id"]}, version)
