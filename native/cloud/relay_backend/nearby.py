"""Authenticated enrollment and ingestion of signed, store-carried requests.

Carriers never receive a Cognito token. Only an authorized shelter coordinator can
upload the decrypted signed body, and the registered sender remains its owner.
"""
import base64
import json
from uuid import UUID
from typing import Literal

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, x25519
from pydantic import Field, ValidationError, model_validator

from .auth import Principal
from .common import APIError, key
from .models import StrictModel, RequestSubmission
from .store import Conflict, Put


def public_keys(signing, encryption):
    try:
        a = base64.b64decode(signing, validate=True)
        b = base64.b64decode(encryption, validate=True)
        if len(a) != 65 or len(b) != 32:
            raise ValueError()
        ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), a)
        x25519.X25519PublicKey.from_public_bytes(b)
    except (ValueError, TypeError):
        raise ValueError("Invalid device public keys") from None


class DeviceRegistration(StrictModel):
    device_id: UUID
    signing_key: str = Field(max_length=128)
    encryption_key: str = Field(max_length=64)

    @model_validator(mode="after")
    def valid_keys(self):
        public_keys(self.signing_key, self.encryption_key)
        return self


class ReceiverAssignment(StrictModel):
    device_id: UUID
    expected_revision: int = Field(ge=0)


class SignedRequest(StrictModel):
    body: str = Field(min_length=1, max_length=32000)
    signature: str = Field(min_length=1, max_length=112)
    signing_key: str = Field(min_length=1, max_length=128)


class NearbyBody(StrictModel):
    schema_version: Literal[1]
    submission: RequestSubmission
    sender_subject: str = Field(min_length=1, max_length=128)
    receiver_subject: str = Field(min_length=1, max_length=128)
    receiving_device_id: UUID
    sender_encryption_key: str = Field(max_length=64)
    receiver_signing_key: str = Field(max_length=128)


class NearbyMixin:
    def register_device(self, principal, body):
        self.writable()
        k = key("device", principal.subject + ":" + str(body.device_id))
        row = self.store.get(*k)
        value = {**body.model_dump(mode="json"), "owner_subject": principal.subject}
        if row:
            if row[0] != value:
                raise APIError(409, "device_identity_conflict", "This device ID already has a different enrolled identity")
            return body.model_dump(mode="json")
        owner_key = key("device_count", principal.subject)
        owner = self.store.get(*owner_key)
        count = owner[0]["count"] if owner else 0
        if count >= 8:
            raise APIError(429, "device_limit", "This demo account already has eight enrolled devices")
        try:
            self.store.transact(puts=[Put(*k, value), Put(*owner_key, {"count": count + 1}, owner[1] if owner else None)])
        except Conflict:
            raise APIError(409, "concurrent_device_enrollment", "Retry the identical device enrollment", True) from None
        return body.model_dump(mode="json")

    def assign_receiver(self, principal, shelter_id, body):
        self.writable()
        if principal.membership.role != "dispatcher":
            raise APIError(403, "dispatcher_required", "Only shelter staff can select a receiving device")
        incident = principal.membership.incident_id
        self.authorize_shelter(principal, incident, shelter_id)
        device = self.store.get(*key("device", principal.subject + ":" + str(body.device_id)))
        if not device or device[0]["owner_subject"] != principal.subject:
            raise APIError(403, "device_not_owned", "Enroll this coordinator's own receiving device first")
        k = key("receiver", incident + ":" + shelter_id)
        row = self.store.get(*k)
        if row and row[0]["device_id"] == str(body.device_id) and row[0]["account_subject"] == principal.subject:
            return row[0]
        revision = row[0]["revision"] if row else 0
        if body.expected_revision != revision:
            raise APIError(409, "receiver_revision_conflict", "Refresh the shelter before changing its receiver")
        receiver = {x: device[0][x] for x in ("device_id", "signing_key", "encryption_key")}
        receiver["revision"] = revision + 1
        receiver["account_subject"] = principal.subject
        try:
            self.store.transact(puts=[Put(*k, receiver, row[1] if row else None)])
        except Conflict:
            raise APIError(409, "receiver_revision_conflict", "Refresh the shelter before changing its receiver") from None
        return receiver

    def ingest_nearby(self, coordinator, signed):
        self.writable()
        if coordinator.membership.role != "dispatcher":
            raise APIError(403, "dispatcher_required", "Only the receiving shelter can ingest a carried request")
        try:
            raw = base64.b64decode(signed.body, validate=True)
            if len(raw) > 24000:
                raise ValueError()
            value = NearbyBody.model_validate_json(raw)
            public_keys(signed.signing_key, value.sender_encryption_key)
            signature = base64.b64decode(signed.signature, validate=True)
            if len(signature) > 80:
                raise ValueError()
            ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), base64.b64decode(signed.signing_key)).verify(signature, raw, ec.ECDSA(hashes.SHA256()))
        except (ValueError, ValidationError, InvalidSignature):
            raise APIError(422, "invalid_sender_signature", "The carried request could not be verified") from None
        submission = value.submission
        self.authorize_shelter(coordinator, submission.incident_id, submission.destination_shelter_id)
        receiver = self.store.get(*key("receiver", submission.incident_id + ":" + submission.destination_shelter_id))
        target = self.store.get(*key("device", coordinator.subject + ":" + str(value.receiving_device_id)))
        if (not receiver or receiver[0]["device_id"] != str(value.receiving_device_id) or
                receiver[0]["signing_key"] != value.receiver_signing_key or
                value.receiver_subject != coordinator.subject or receiver[0]["account_subject"] != coordinator.subject or not target or
                target[0]["owner_subject"] != coordinator.subject):
            raise APIError(403, "wrong_receiving_device", "This request was addressed to another shelter receiver")
        origin = self.store.get(*key("device", value.sender_subject + ":" + str(submission.origin_device_id)))
        if (not origin or origin[0]["signing_key"] != signed.signing_key or
                origin[0]["encryption_key"] != value.sender_encryption_key):
            raise APIError(403, "sender_not_enrolled", "The sender device has not been enrolled with this identity")
        membership = self.settings.memberships.get(origin[0]["owner_subject"])
        if not membership or membership.role != "requester":
            raise APIError(403, "sender_not_authorized", "The sender no longer has requester access")
        if submission.operation_id != submission.request_id:
            raise APIError(422, "request_id_mismatch", "Carried requests must retain one immutable submission ID")
        return self.submit(Principal(origin[0]["owner_subject"], membership), submission)
