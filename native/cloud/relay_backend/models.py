from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator, model_serializer


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RequestLocation(StrictModel):
    latitude: float = Field(strict=True, ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(strict=True, ge=-180, le=180, allow_inf_nan=False)
    horizontal_accuracy: float = Field(strict=True, ge=0, le=20_000_000, allow_inf_nan=False)
    captured_at: datetime
    precision: Literal["precise", "approximate"]
    source: Literal["device", "manual"]

    @field_validator("captured_at")
    @classmethod
    def aware(cls, value):
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("An explicit UTC offset is required")
        return value


class StructuredFields(StrictModel):
    item_id: Literal["water_packs", "blankets", "food_packs", "medicines", "other"] | None = None
    quantity: int | None = Field(default=None, strict=True, ge=1, le=10000)
    unit: Literal["pack", "piece", "bottle", "item", "tablet", "vial", "box"] | None = None
    people: int | None = Field(default=None, strict=True, ge=1, le=1000000)
    landmark: str | None = Field(default=None, max_length=500)

    urgency: Literal["routine", "soon", "urgent", "immediate"] | None = None
    medicine_details: str | None = Field(default=None, max_length=240)

    @model_serializer(mode="wrap")
    def preserve_legacy_shape(self, handler):
        value = handler(self)
        # Existing request hashes must not change when old clients retry after upgrade.
        for field in ("urgency", "medicine_details"):
            if value.get(field) is None:
                value.pop(field, None)
        return value


class SharedResidentDetails(StrictModel):
    display_name: str = Field(min_length=1, max_length=80)
    preferred_language: Literal["English", "Spanish", "Mandarin", "Vietnamese", "Hindi", "Telugu", "Other"]
    age: int | None = Field(default=None, strict=True, ge=0, le=130)
    height_cm: float | None = Field(default=None, ge=0, le=300, allow_inf_nan=False)
    weight_kg: float | None = Field(default=None, ge=0, le=1000, allow_inf_nan=False)
    blood_group: Literal["A+", "A−", "B+", "B−", "AB+", "AB−", "O+", "O−"] | None = None
    allergies: str | None = Field(default=None, max_length=400)
    health_conditions: str | None = Field(default=None, max_length=500)
    medications: str | None = Field(default=None, max_length=400)
    accessibility_needs: str | None = Field(default=None, max_length=400)

    @model_validator(mode="after")
    def valid_details(self):
        if not self.display_name.strip():
            raise ValueError("A shared profile needs a display name")
        if self.height_cm == 0 or self.weight_kg == 0:
            raise ValueError("Measurements must be positive or omitted")
        import json
        if len(json.dumps(self.model_dump(exclude_none=True), ensure_ascii=False, separators=(",", ":")).encode()) > 4096:
            raise ValueError("Shared personal details exceed 4096 bytes")
        for value in self.model_dump().values():
            if isinstance(value, str) and any(ord(c) < 32 and c not in "\n\r\t" for c in value):
                raise ValueError("Personal details contain invalid control characters")
        return self


class RequestSubmission(StrictModel):
    schema_version: Literal[1] = 1
    operation_id: UUID
    request_id: UUID
    incident_id: str = Field(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
    destination_shelter_id: str = Field(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
    origin_device_id: UUID
    original_text: str = Field(min_length=1, max_length=4096)
    input_mode: Literal["text", "reviewed_transcript"]
    transcription_id: UUID | None = None
    created_at: datetime
    expires_at: datetime
    revision: Literal[1] = 1
    location: RequestLocation | None = None
    structured_fields: StructuredFields | None = None
    interpretation_id: UUID | None = None
    requester_details: SharedResidentDetails | None = None

    @field_validator("created_at", "expires_at")
    @classmethod
    def aware(cls, value):
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("An explicit UTC offset is required")
        return value

    @field_validator("original_text")
    @classmethod
    def nonblank(cls, value):
        if not value.strip() or any(ord(c) < 32 and c not in "\n\r\t" for c in value):
            raise ValueError("Text must be nonblank and contain no control characters")
        return value

    @model_validator(mode="after")
    def mode_matches(self):
        if (self.input_mode == "reviewed_transcript") != (self.transcription_id is not None):
            raise ValueError("Only reviewed_transcript input must include transcription_id")
        return self


class TranscriptionAllocation(StrictModel):
    schema_version: Literal[1] = 1
    operation_id: UUID
    transcription_id: UUID
    incident_id: str = Field(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
    content_type: Literal["audio/wav"] = "audio/wav"
    byte_length: int = Field(strict=True, ge=45, le=2_097_152)
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    language_code: Literal["en-US"] = "en-US"


class StartTranscription(StrictModel):
    operation_id: UUID


class ModelProposal(StrictModel):
    item_id: Literal["water_packs", "blankets", "food_packs", "medicines", "other"] | None
    quantity: int | None = Field(default=None, strict=True, ge=1, le=10000)
    unit: Literal["pack", "piece", "bottle", "item", "tablet", "vial", "box"] | None
    shelter_id: str | None = Field(max_length=80)
    negated: bool = Field(strict=True)
    missing_fields: list[Literal["item", "quantity", "unit", "shelter"]] = Field(max_length=4)
    summary: str = Field(min_length=1, max_length=400)

    people: int | None = Field(default=None, strict=True, ge=1, le=1000000)
    landmark: str | None = Field(default=None, max_length=240)
    medicine_details: str | None = Field(default=None, max_length=240)
    urgency: Literal["routine", "soon", "urgent", "immediate"] | None = None
    urgency_evidence: str | None = Field(default=None, max_length=240)


class ErrorDetail(StrictModel):
    code: str
    message: str
    retryable: bool = False


class ErrorResponse(StrictModel):
    error: ErrorDetail


class ValidatedResult(StrictModel):
    status: Literal["ready_for_review", "needs_review"]
    proposal: ModelProposal | None
    review_reasons: list[str]
    allocation_authorized: Literal[False] = False


class RequestResult(StrictModel):
    request_id: UUID
    schema_version: Literal[1]
    revision: Literal[1]
    submission: RequestSubmission
    accepted_at: datetime
    cloud_state: Literal["accepted"]
    analysis_state: Literal["pending", "retrying", "ready_for_review", "needs_review", "failed"]
    result: ValidatedResult | None
    analysis_attempts: int
    manual_retry_count: int = 0
    error: ErrorDetail | None
    provider_evidence: dict | None
    assignment_state: Literal["not_implemented", "unassigned", "reserved", "released", "fulfilled"]
    fulfillment_state: Literal["not_implemented", "not_fulfilled", "fulfilled"]


class UploadAuthorization(StrictModel):
    method: Literal["POST", "PUT"]
    url: str
    fields: dict[str, str]
    headers: dict[str, str]
    requires_bearer_token: bool
    expires_in_seconds: int


class TranscriptionResult(StrictModel):
    schema_version: Literal[1]
    transcription_id: UUID
    incident_id: str
    content_type: Literal["audio/wav"]
    byte_length: int
    sha256: str
    language_code: Literal["en-US"]
    status: Literal["awaiting_upload", "upload_expired", "queued", "processing", "completed", "failed"]
    created_at: float
    upload_expires_at: float
    transcript: str | None
    error: ErrorDetail | None
    provider_evidence: dict | None
    start_count: int
    started_at: float | None = None
    duration_seconds: float | None = None
    sample_rate: int | None = None
    upload: UploadAuthorization | None = None


class ShelterReceiver(StrictModel):
    account_subject: str
    device_id: UUID
    signing_key: str
    encryption_key: str
    revision: int


class ShelterDetails(StrictModel):
    address: str
    instructions: str
    latitude: float | None
    longitude: float | None
    revision: int
    updated_at: datetime


class DirectoryEntry(StrictModel):
    shelter_id: str
    incident_id: str
    display_name: str
    receiver: ShelterReceiver | None = None
    details: ShelterDetails | None = None


class ShelterDirectory(StrictModel):
    schema_version: Literal[1]
    items: list[DirectoryEntry]


class Health(StrictModel):
    status: Literal["ok"]
    api_version: str
    schema_version: Literal[1]
    mode: Literal["local-test", "aws"]
    storage: Literal["sqlite", "dynamodb"]
    performs_ai_check: Literal[False] = False
    note: str


class Profile(StrictModel):
    subject: str
    role: Literal['requester', 'dispatcher']
    incident_id: str
    shelter_ids: list[str]


class RequestEventCommand(StrictModel):
    operation_id: UUID
    expected_revision: int = Field(ge=0)
    text: str = Field(default='', max_length=2000)
    status: Literal['accepted', 'in_progress', 'completed', 'rejected', 'cancelled'] | None = None

    @model_validator(mode='after')
    def has_content(self):
        self.text = self.text.strip()
        if (not self.text and self.status is None) or any(ord(c) < 32 and c not in '\n\r\t' for c in self.text):
            raise ValueError('Add a reply or status')
        return self


class RequestEvent(StrictModel):
    event_id: UUID
    revision: int
    author_role: Literal['requester', 'dispatcher']
    text: str
    status: str | None
    created_at: datetime


class RequestHistory(StrictModel):
    request_id: UUID
    revision: int
    status: str
    events: list[RequestEvent]
    # True means the inventory transaction was verified, never physical delivery.
    resource_allocation_verified: bool = False
    physical_delivery_verified: Literal[False] = False


class InterpretationSubmission(StrictModel):
    operation_id: UUID
    interpretation_id: UUID
    incident_id: str = Field(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
    destination_shelter_id: str = Field(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
    original_text: str = Field(min_length=1, max_length=4096)
    transcription_id: UUID | None = None

    @field_validator("original_text")
    @classmethod
    def nonblank(cls, value):
        return RequestSubmission.nonblank(value)


class InterpretationResult(StrictModel):
    interpretation_id: UUID
    status: Literal["pending", "ready_for_review", "needs_review", "failed"]
    result: ValidatedResult | None = None
    error: ErrorDetail | None = None


class InventoryItem(StrictModel):
    item_id: Literal["water_packs", "food_packs", "blankets"]
    unit: Literal["pack", "piece"]
    on_hand: int = Field(ge=0)
    reserved: int = Field(ge=0)
    available: int = Field(ge=0)
    revision: int = Field(ge=0)


class Inventory(StrictModel):
    shelter_id: str
    items: list[InventoryItem]


class InventoryAdjustment(StrictModel):
    operation_id: UUID
    item_id: Literal["water_packs", "food_packs", "blankets"]
    quantity_delta: int = Field(strict=True, ge=-1000000, le=1000000)
    expected_revision: int = Field(strict=True, ge=0)
    note: str = Field(min_length=1, max_length=500)

    @model_validator(mode="after")
    def meaningful(self):
        self.note = self.note.strip()
        if not self.note or self.quantity_delta == 0:
            raise ValueError("A nonzero change and audit note are required")
        return self


class InventoryCommand(StrictModel):
    operation_id: UUID
    action: Literal["reserve", "fulfill", "release"]
    item_id: Literal["water_packs", "food_packs", "blankets"] | None = None
    quantity: int | None = Field(default=None, strict=True, ge=1, le=10000)
    expected_inventory_revision: int | None = Field(default=None, strict=True, ge=0)


class Reservation(StrictModel):
    item_id: Literal["water_packs", "food_packs", "blankets"]
    quantity: int = Field(ge=1)
    unit: Literal["pack", "piece"]
    status: Literal["reserved", "fulfilled", "released"]


class RequestInventory(StrictModel):
    request_id: UUID
    reservation: Reservation | None
    history: RequestHistory


class InboxRequestResult(RequestResult):
    history: RequestHistory
    reservation: Reservation | None


class RequestPage(StrictModel):
    items: list[InboxRequestResult]
    next_cursor: str | None
