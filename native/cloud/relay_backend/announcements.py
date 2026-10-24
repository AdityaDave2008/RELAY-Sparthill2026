"""Incident announcements and staff-maintained shelter information. No AI or push delivery."""
from datetime import datetime, timezone
import json
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from .common import APIError, digest, key
from .models import StrictModel
from .store import Conflict, Put


class AnnouncementCommand(StrictModel):
    announcement_id: UUID
    shelter_id: str = Field(min_length=1, max_length=80)
    title: str = Field(min_length=1, max_length=100)
    text: str = Field(min_length=1, max_length=1500)
    severity: Literal["info", "important", "urgent"]
    expires_at: datetime

    @model_validator(mode="after")
    def valid(self):
        if not self.title.strip() or not self.text.strip() or self.expires_at.tzinfo is None:
            raise ValueError("Provide a title, announcement and timezone-aware expiry")
        return self


class RevisionCommand(StrictModel):
    expected_revision: int = Field(ge=0)


class ShelterDetailsCommand(RevisionCommand):
    address: str = Field(max_length=240)
    instructions: str = Field(max_length=1500)
    latitude: float | None = Field(default=None, ge=-90, le=90, allow_inf_nan=False)
    longitude: float | None = Field(default=None, ge=-180, le=180, allow_inf_nan=False)

    @model_validator(mode="after")
    def paired_coordinates(self):
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Provide both coordinates or neither")
        return self


def timestamp(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat().replace("+00:00", "Z")


class AnnouncementsMixin:
    def announcement_feed(self, principal):
        row = self.store.get(*key("announcements", principal.membership.incident_id))
        return {"items": row[0]["items"] if row else [], "fetched_at": timestamp(self.clock())}

    def announcement_staff(self, principal, shelter):
        if principal.membership.role != "dispatcher":
            raise APIError(403, "dispatcher_required", "Only dispatchers can publish announcements or edit shelter information")
        self.authorize_shelter(principal, principal.membership.incident_id, shelter)

    def publish_announcement(self, principal, command):
        self.writable()
        self.announcement_staff(principal, command.shelter_id)
        body = command.model_dump(mode="json")
        fingerprint = digest({"subject": principal.subject, "body": body})
        opkey = key("announcement-operation", str(command.announcement_id))
        old = self.store.get(*opkey)
        if old:
            if old[0]["hash"] != fingerprint:
                raise APIError(409, "idempotency_conflict", "This announcement ID already has different content")
            # Return its current state if it has since been withdrawn.
            current = self.announcement_feed(principal)["items"]
            return next((a for a in current if a["announcement_id"] == str(command.announcement_id)), old[0]["result"])
        now = self.clock()
        if not 60 <= command.expires_at.timestamp() - now <= 7 * 86400:
            raise APIError(422, "invalid_expiry", "Expiry must be between one minute and seven days from now")
        feedkey = key("announcements", principal.membership.incident_id)
        row = self.store.get(*feedkey)
        items = [a for a in row[0]["items"] if datetime.fromisoformat(a["expires_at"].replace("Z", "+00:00")).timestamp() > now] if row else []
        if len(items) >= 100:
            raise APIError(409, "announcement_limit", "This incident has reached its announcement limit; wait for older notices to expire")
        shelter = next(s for s in self.settings.shelters if s.shelter_id == command.shelter_id and s.incident_id == principal.membership.incident_id)
        result = {**body, "incident_id": principal.membership.incident_id, "publisher": shelter.display_name + " · dispatcher",
                  "created_at": timestamp(now), "updated_at": timestamp(now), "revision": 1, "withdrawn": False}
        if len(json.dumps({"items": [result, *items]}).encode()) > 300_000:
            raise APIError(409, "announcement_limit", "The incident announcement feed is full; wait for older notices to expire")
        try:
            self.store.transact([Put(*feedkey, {"items": [result, *items]}, row[1] if row else None),
                                 Put(*opkey, {"hash": fingerprint, "result": result})])
        except Conflict:
            # Concurrent same-operation retries resolve to the committed result.
            saved = self.store.get(*opkey)
            if saved and saved[0]["hash"] == fingerprint:
                return saved[0]["result"]
            raise APIError(409, "announcement_changed", "Announcements changed; retry with the same draft", True) from None
        return result

    def withdraw_announcement(self, principal, identifier, expected_revision):
        self.writable()
        feedkey = key("announcements", principal.membership.incident_id)
        row = self.store.get(*feedkey)
        items = row[0]["items"] if row else []
        current = next((a for a in items if a["announcement_id"] == str(identifier)), None)
        if current is None:
            raise APIError(404, "announcement_not_found", "Announcement not found")
        self.announcement_staff(principal, current["shelter_id"])
        if current["withdrawn"] and current["revision"] == expected_revision + 1:
            return current
        if current["revision"] != expected_revision:
            raise APIError(409, "announcement_changed", "Refresh this announcement before withdrawing it")
        updated = {**current, "withdrawn": True, "revision": current["revision"] + 1, "updated_at": timestamp(self.clock())}
        try:
            self.store.transact([Put(*feedkey, {"items": [updated if a["announcement_id"] == str(identifier) else a for a in items]}, row[1])])
        except Conflict:
            raise APIError(409, "announcement_changed", "Announcements changed; refresh and retry", True) from None
        return updated

    def update_shelter_details(self, principal, shelter_id, command):
        self.writable()
        self.announcement_staff(principal, shelter_id)
        recordkey = key("shelter-details", principal.membership.incident_id + ":" + shelter_id)
        row = self.store.get(*recordkey)
        content = command.model_dump(exclude={"expected_revision"})
        # Lost-response retry is safe without incrementing the revision twice.
        if row and row[0]["revision"] == command.expected_revision + 1 and all(row[0][k] == v for k, v in content.items()):
            return row[0]
        if (row[0]["revision"] if row else 0) != command.expected_revision:
            raise APIError(409, "shelter_changed", "Shelter information changed; refresh before saving")
        result = {**content, "revision": command.expected_revision + 1, "updated_at": timestamp(self.clock())}
        try:
            self.store.transact([Put(*recordkey, result, row[1] if row else None)])
        except Conflict:
            raise APIError(409, "shelter_changed", "Shelter information changed; refresh before saving") from None
        return result
