import os
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from uuid import UUID
from typing import Literal

from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import Depends, FastAPI, Header, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .auth import Authenticator, AuthError
from .config import Settings
from .models import (ErrorResponse, RequestSubmission, StartTranscription, TranscriptionAllocation,
                     Health, RequestResult, RequestPage, TranscriptionResult, ShelterDirectory,
                     Profile, RequestEventCommand, RequestHistory, InterpretationSubmission,
                     InterpretationResult, Inventory, InventoryAdjustment, InventoryCommand, RequestInventory, InboxRequestResult)
from .providers import AWSProviders, FixtureProviders, ProviderError
from .service import APIError, Service, Worker
from .store import DynamoStore, SQLiteStore
from .speech import install_speech_routes
from .nearby import DeviceRegistration, ReceiverAssignment, SignedRequest
from .announcements import AnnouncementCommand, RevisionCommand, ShelterDetailsCommand
from .models import ShelterDetails


def build_service(settings):
    settings.runtime_dir.mkdir(parents=True, exist_ok=True)
    if settings.mode == "aws":
        session = settings.aws_session()
        config = Config(connect_timeout=5, read_timeout=10, retries={"total_max_attempts": 1})
        identity = session.client("sts", config=config).get_caller_identity()
        if identity["Account"] != settings.expected_account:
            raise RuntimeError("Wrong AWS account; backend refused to start")
        store = DynamoStore(session.client("dynamodb", config=config), settings.table_name) if settings.storage == "dynamodb" else SQLiteStore(settings.runtime_dir / "backend.sqlite")
        providers = AWSProviders(settings, session)
    else:
        store = SQLiteStore(settings.runtime_dir / "backend.sqlite")
        providers = FixtureProviders(settings)
    return Service(settings, store, providers)


def create_app(settings: Settings, service=None):
    service = service or build_service(settings)
    auth = Authenticator(settings)
    previews = ThreadPoolExecutor(max_workers=1, thread_name_prefix="relay-preview") if settings.accelerate_previews else None
    preview_slot = threading.BoundedSemaphore(1)

    @asynccontextmanager
    async def lifespan(app):
        yield
        if previews: previews.shutdown(wait=False, cancel_futures=True)

    def run_preview(identifier):
        try:
            Worker(service).run_once("interpretation#" + str(identifier))
        except Exception as error:
            print("Preview worker interrupted:", type(error).__name__, flush=True)
        finally:
            preview_slot.release()

    app = FastAPI(lifespan=lifespan, title="RELAY Cloud API", version="1.0.0",
                  description="Durable authenticated requests, pre-send previews, reviewed speech and coordinator inventory ledger. Inventory fulfillment is a staff-recorded stock transaction, not proof of physical delivery. Nearby gateway ingestion verifies enrolled sender signatures.",
                  servers=[{"url": settings.public_base_url}],
                  responses={n: {"model": ErrorResponse} for n in (400, 401, 403, 404, 409, 410, 413, 422, 429, 503)})
    app.state.service = service
    install_speech_routes(app, service, auth)
    bearer = HTTPBearer(auto_error=False)

    def principal(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        try:
            return auth.verify("Bearer " + credentials.credentials if credentials and credentials.scheme.lower() == "bearer" else None)
        except AuthError as exc:
            raise APIError(401, "unauthorized", str(exc)) from None

    @app.exception_handler(APIError)
    async def api_error(request, exc):
        headers = {"WWW-Authenticate": "Bearer"} if exc.status == 401 else {}
        return JSONResponse(status_code=exc.status, content={"error": {"code": exc.code, "message": exc.message, "retryable": exc.retryable}}, headers=headers)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        # Do not echo bearer tokens, uploaded data, or user text in errors/logs.
        return JSONResponse(status_code=422, content={"error": {"code": "invalid_request", "message": "Request does not match the versioned schema", "retryable": False}})

    @app.exception_handler(ProviderError)
    async def provider_error(request, exc):
        return JSONResponse(status_code=503, content={"error": {"code": exc.code, "message": "Provider is unavailable; retry only if indicated", "retryable": exc.retryable}})

    async def storage_error(request, exc):
        return JSONResponse(status_code=503, content={"error": {"code": "storage_unavailable", "message": "Acceptance is unknown; retry the identical operation ID and content", "retryable": True}})
    app.add_exception_handler(ClientError, storage_error)
    app.add_exception_handler(BotoCoreError, storage_error)

    @app.middleware("http")
    async def limits_and_headers(request: Request, call_next):
        limit = settings.max_audio_bytes if request.url.path.startswith("/v1/local-uploads/") else 32768
        try:
            declared = int(request.headers.get("content-length", "0"))
        except ValueError:
            declared = limit + 1
        if declared > limit or declared < 0:
            return JSONResponse(status_code=413, content={"error": {"code": "body_too_large", "message": "Request body exceeds its limit", "retryable": False}})
        # Cap chunked bodies too. Headers alone are not an enforcement mechanism.
        if request.method in {"POST", "PUT", "PATCH"}:
            data = bytearray()
            async for chunk in request.stream():
                data.extend(chunk)
                if len(data) > limit:
                    return JSONResponse(status_code=413, content={"error": {"code": "body_too_large", "message": "Request body exceeds its limit", "retryable": False}})
            request._body = bytes(data)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.get("/", include_in_schema=False)
    def index():
        return RedirectResponse(url="/docs", status_code=307)

    @app.get("/v1/health", operation_id="getHealth", tags=["Health"], response_model=Health)
    def health():
        return {"status": "ok", "api_version": "1.0.0", "schema_version": 1,
                "mode": settings.mode, "storage": settings.storage,
                "performs_ai_check": False,
                "note": "Liveness only; this route never invokes AI and does not certify AWS runtime."}

    @app.get("/v1/me", response_model=Profile, tags=["Account"])
    def me(user=Depends(principal)):
        return {"subject": user.subject, **user.membership.model_dump()}

    @app.post("/v1/interpretations", status_code=201, response_model=InterpretationResult, tags=["Pre-send preview"],
              responses={200: {"description": "Identical preview already accepted", "model": InterpretationResult}})
    def interpret(body: InterpretationSubmission, response: Response, user=Depends(principal)):
        result, created = service.interpret(user, body)
        # Durable queue/conditional lease remain authoritative; this bounded lane
        # removes interactive preview wait behind unrelated jobs, with no extra calls.
        if previews and result["status"] == "pending" and preview_slot.acquire(blocking=False):
            try: previews.submit(run_preview, body.interpretation_id)
            except RuntimeError: preview_slot.release()
        response.status_code = 201 if created else 200
        return result

    @app.get("/v1/interpretations/{interpretation_id}", response_model=InterpretationResult, tags=["Pre-send preview"])
    def interpretation(interpretation_id: UUID, user=Depends(principal)):
        return service.get_interpretation(user, interpretation_id)

    @app.get("/v1/inventory", response_model=Inventory, tags=["Inventory"])
    def inventory(shelter_id: str, user=Depends(principal)):
        return service.inventory(user, shelter_id)

    @app.post("/v1/inventory/{shelter_id}/adjust", response_model=Inventory, tags=["Inventory"])
    def adjust_inventory(shelter_id: str, body: InventoryAdjustment, user=Depends(principal)):
        return service.adjust_inventory(user, shelter_id, body)

    @app.get("/v1/requests/{request_id}/snapshot", response_model=InboxRequestResult, tags=["Requests"])
    def request_snapshot(request_id: UUID, user=Depends(principal)):
        return service.request_snapshot(user, request_id)

    @app.get("/v1/requests/{request_id}/inventory", response_model=RequestInventory, tags=["Inventory"])
    def request_inventory(request_id: UUID, user=Depends(principal)):
        return service.request_inventory(user, request_id)

    @app.post("/v1/requests/{request_id}/inventory", response_model=RequestInventory, tags=["Inventory"])
    def change_inventory(request_id: UUID, body: InventoryCommand, user=Depends(principal)):
        return service.change_request_inventory(user, request_id, body)

    @app.get("/v1/requests/{request_id}/history", response_model=RequestHistory, tags=["Requests"])
    def history(request_id: UUID, user=Depends(principal)):
        return service.request_history(user, request_id)

    @app.post("/v1/requests/{request_id}/events", response_model=RequestHistory, tags=["Requests"])
    def request_event(request_id: UUID, body: RequestEventCommand, user=Depends(principal)):
        return service.append_request_event(user, request_id, body)

    @app.get("/v1/shelters", operation_id="listShelters", tags=["Directory"], response_model=ShelterDirectory)
    def shelters(user=Depends(principal)):
        return {"schema_version": 1, "items": service.directory(user)}

    @app.put("/v1/shelters/{shelter_id}/details", tags=["Directory"], response_model=ShelterDetails)
    def shelter_details(shelter_id: str, body: ShelterDetailsCommand, user=Depends(principal)):
        return service.update_shelter_details(user, shelter_id, body)

    @app.get("/v1/announcements", tags=["Announcements"])
    def announcements(user=Depends(principal)):
        return service.announcement_feed(user)

    @app.post("/v1/announcements", status_code=201, tags=["Announcements"])
    def publish_announcement(body: AnnouncementCommand, user=Depends(principal)):
        return service.publish_announcement(user, body)

    @app.post("/v1/announcements/{announcement_id}/withdraw", tags=["Announcements"])
    def withdraw_announcement(announcement_id: UUID, body: RevisionCommand, user=Depends(principal)):
        return service.withdraw_announcement(user, announcement_id, body.expected_revision)

    @app.post("/v1/devices", tags=["Nearby delivery"])
    def register_device(body: DeviceRegistration, user=Depends(principal)):
        return service.register_device(user, body)

    @app.put("/v1/shelters/{shelter_id}/receiver", tags=["Nearby delivery"])
    def assign_receiver(shelter_id: str, body: ReceiverAssignment, user=Depends(principal)):
        return service.assign_receiver(user, shelter_id, body)

    @app.post("/v1/relay/requests", response_model=RequestResult, tags=["Nearby delivery"])
    def ingest_nearby(body: SignedRequest, response: Response, user=Depends(principal)):
        result, created = service.ingest_nearby(user, body)
        response.status_code = 201 if created else 200
        return result

    @app.post("/v1/requests", status_code=201, operation_id="submitRequest", tags=["Requests"], response_model=RequestResult,
              responses={200: {"description": "An identical request was already accepted"}})
    def submit(body: RequestSubmission, response: Response, user=Depends(principal)):
        result, created = service.submit(user, body)
        response.status_code = 201 if created else 200
        return result

    @app.get("/v1/requests/{request_id}", operation_id="getRequest", tags=["Requests"], response_model=RequestResult)
    def get_request(request_id: UUID, user=Depends(principal)):
        return service.get_request(user, request_id)

    @app.get("/v1/requests", operation_id="listRequests", tags=["Requests"], response_model=RequestPage)
    def list_requests(view: Literal["mine", "shelter"] = "mine", shelter_id: str | None = None,
                      cursor: str | None = Query(default=None, max_length=1024),
                      limit: int = Query(default=20, ge=1, le=50), user=Depends(principal)):
        return service.list_requests(user, view, shelter_id, cursor, limit)

    @app.post("/v1/transcriptions", status_code=201, operation_id="allocateTranscription", tags=["Recorded speech"], response_model=TranscriptionResult)
    def allocate_transcription(body: TranscriptionAllocation, user=Depends(principal)):
        return service.allocate_audio(user, body)

    @app.post("/v1/transcriptions/{transcription_id}/start", status_code=202, operation_id="startTranscription", tags=["Recorded speech"], response_model=TranscriptionResult)
    def start_transcription(transcription_id: UUID, body: StartTranscription, user=Depends(principal)):
        return service.start_audio(user, transcription_id, body.operation_id)

    @app.get("/v1/transcriptions/{transcription_id}", operation_id="getTranscription", tags=["Recorded speech"], response_model=TranscriptionResult)
    def get_transcription(transcription_id: UUID, user=Depends(principal)):
        return service.get_audio(user, transcription_id)

    @app.post("/v1/requests/{request_id}/retry-analysis", status_code=202, operation_id="retryAnalysis", tags=["Requests"], response_model=RequestResult)
    def retry_analysis(request_id: UUID, body: StartTranscription, user=Depends(principal)):
        return service.retry_analysis(user, request_id, body.operation_id)

    if settings.mode == "local-test":
        @app.put("/v1/local-uploads/{transcription_id}", include_in_schema=False)
        async def local_upload(transcription_id: UUID, request: Request, user=Depends(principal)):
            record, _ = service.owned_audio(user, transcription_id)
            if record["status"] != "awaiting_upload" or record["upload_expires_at"] < service.clock():
                raise APIError(409, "upload_not_open", "Renew an awaiting upload or allocate a new recording")
            service.providers.write_upload(record, await request.body())
            return Response(status_code=204)
    return app


def from_env():
    return create_app(Settings.load(os.environ["RELAY_CONFIG"]))
