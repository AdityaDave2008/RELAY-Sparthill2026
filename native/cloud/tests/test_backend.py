import concurrent.futures
import hashlib
import io
import json
import time
import wave
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import pytest

from conftest import auth
from relay_backend.api import build_service, create_app
from relay_backend.providers import ProviderError
from relay_backend.service import PREFIX, WORK, Worker, key, work_key
from fastapi.testclient import TestClient


def submission(text="Shelter A needs 20 water packs.", **changes):
    now = datetime.now(timezone.utc)
    body = {"schema_version": 1, "operation_id": str(uuid4()), "request_id": str(uuid4()),
            "incident_id": "synthetic-demo-01", "destination_shelter_id": "shelter-a",
            "origin_device_id": str(uuid4()), "original_text": text, "input_mode": "text",
            "created_at": now.isoformat(), "expires_at": (now + timedelta(hours=24)).isoformat(), "revision": 1}
    body.update(changes)
    return body


def wav_bytes(seconds=0.1, sample_rate=16000, channels=1):
    stream = io.BytesIO()
    with wave.open(stream, "wb") as audio:
        audio.setnchannels(channels)
        audio.setsampwidth(2)
        audio.setframerate(sample_rate)
        audio.writeframes(b"\0\0" * int(seconds * sample_rate) * channels)
    return stream.getvalue()


def allocation(data):
    return {"schema_version": 1, "operation_id": str(uuid4()), "transcription_id": str(uuid4()),
            "incident_id": "synthetic-demo-01", "content_type": "audio/wav", "byte_length": len(data),
            "sha256": hashlib.sha256(data).hexdigest(), "language_code": "en-US"}


def test_health_and_authentication_boundaries(env):
    c = env["client"]
    assert c.get("/v1/health").status_code == 200
    assert env["service"].providers.calls == 0
    assert c.get("/v1/shelters").status_code == 401
    assert c.get("/v1/shelters", headers={"Authorization": "Bearer junk"}).status_code == 401
    assert [s["shelter_id"] for s in c.get("/v1/shelters", headers=auth(env)).json()["items"]] == ["shelter-a"]
    key_data = (env["settings"].runtime_dir / "test-signing-key.pem").read_bytes()
    base = {"iss": env["settings"].issuer, "sub": "test-requester-a", "client_id": "relay-local-test",
            "token_use": "access", "iat": int(time.time()) - 100, "exp": int(time.time()) + 100}
    for change in ({"exp": int(time.time()) - 20}, {"token_use": "id"}, {"client_id": "wrong"}, {"iss": "https://evil.invalid"}, {"sub": "unenrolled"}):
        token = jwt.encode({**base, **change}, key_data, algorithm="RS256")
        assert c.get("/v1/shelters", headers={"Authorization": "Bearer " + token}).status_code == 401


def test_text_acceptance_result_and_idempotent_recovery(env):
    c, service = env["client"], env["service"]
    body = submission()
    accepted = c.post("/v1/requests", json=body, headers=auth(env))
    assert accepted.status_code == 201
    assert accepted.json()["cloud_state"] == "accepted"
    assert accepted.json()["analysis_state"] == "pending"
    assert service.providers.calls == 0
    assert c.post("/v1/requests", json=body, headers=auth(env)).status_code == 200
    assert c.post("/v1/requests", json={**body, "original_text": "changed"}, headers=auth(env)).status_code == 409
    # New process/store instance observes the committed queue, even without a reply to the client.
    replacement = build_service(env["settings"])
    assert Worker(replacement).run_once()
    assert replacement.providers.calls == 1
    second_client = TestClient(create_app(env["settings"], replacement))
    response = second_client.get("/v1/requests/" + body["request_id"], headers=auth(env)).json()
    assert response["analysis_state"] == "ready_for_review"
    assert response["result"]["proposal"]["quantity"] == 20
    assert response["result"]["allocation_authorized"] is False
    assert response["provider_evidence"]["provider"] == "fixture-not-aws"
    assert second_client.post("/v1/requests", json=body, headers=auth(env)).status_code == 200
    assert not Worker(replacement).run_once()
    assert len(service.store.query(PREFIX + "USER#test-requester-a")[0]) == 1


def test_record_and_shelter_inbox_authorization(env):
    c = env["client"]
    body = submission()
    assert c.post("/v1/requests", json=body, headers=auth(env)).status_code == 201
    path = "/v1/requests/" + body["request_id"]
    assert c.get(path, headers=auth(env, "test-requester-b")).status_code == 404
    assert c.get(path, headers=auth(env, "test-dispatcher-b")).status_code == 404
    assert c.get(path, headers=auth(env, "test-dispatcher-a")).status_code == 200
    inbox = "/v1/requests?view=shelter&shelter_id=shelter-a"
    assert c.get(inbox, headers=auth(env)).status_code == 403
    assert c.get(inbox, headers=auth(env, "test-dispatcher-b")).status_code == 403
    assert len(c.get(inbox, headers=auth(env, "test-dispatcher-a")).json()["items"]) == 1
    assert c.post("/v1/requests", json=submission(destination_shelter_id="shelter-b"), headers=auth(env)).status_code == 403
    assert c.post("/v1/requests", json={**submission(), "owner_subject": "test-requester-b"}, headers=auth(env)).status_code == 422


def test_inbox_pagination_is_owner_bound(env):
    c = env["client"]
    for _ in range(3):
        assert c.post("/v1/requests", json=submission(), headers=auth(env)).status_code == 201
    first = c.get("/v1/requests?limit=2", headers=auth(env)).json()
    second = c.get("/v1/requests", params={"limit": 2, "cursor": first["next_cursor"]}, headers=auth(env)).json()
    assert len(first["items"]) == 2 and len(second["items"]) == 1 and second["next_cursor"] is None
    assert c.get("/v1/requests", params={"cursor": first["next_cursor"]}, headers=auth(env, "test-requester-b")).status_code == 400


@pytest.mark.parametrize("text,reason", [
    ("Shelter A needs water packs.", "missing_quantity"),
    ("Do not send 20 water packs to Shelter A.", "negation_requires_review"),
    ("Shelter B needs 20 water packs.", "text_destination_conflict"),
    ("Shelter A needs -2 water packs.", "unsupported_quantity_format"),
    ("Shelter A needs 2 water packs, not 20.", "multiple_quantities_require_review"),
    ("Shelter A needs two hundred water packs.", "complex_quantity_requires_review"),
    ("Shelter A needs 2 water packs and 2 blankets.", "multiple_items_require_review"),
    ("Shelter A doesn't need 20 water packs.", "negation_requires_review"),
])
def test_semantic_review_not_automatic_decisions(env, text, reason):
    body = submission(text)
    assert env["client"].post("/v1/requests", json=body, headers=auth(env)).status_code == 201
    Worker(env["service"]).run_once()
    r = env["client"].get("/v1/requests/" + body["request_id"], headers=auth(env)).json()
    assert r["analysis_state"] == "needs_review"
    assert reason in r["result"]["review_reasons"]


def test_invalid_model_output_is_explicit(env):
    env["service"].providers.raw_override = "Here is a result: {not valid json}"
    body = submission()
    env["client"].post("/v1/requests", json=body, headers=auth(env))
    Worker(env["service"]).run_once()
    r = env["client"].get("/v1/requests/" + body["request_id"], headers=auth(env)).json()
    assert r["analysis_state"] == "needs_review" and r["result"]["proposal"] is None


def test_invented_quantity_is_removed_and_missing_input_is_explicit(env):
    env["service"].providers.raw_override = json.dumps({
        "item_id": "water_packs", "quantity": 1, "unit": "pack", "shelter_id": "shelter-a",
        "negated": False, "missing_fields": [], "summary": "Shelter A requests one water pack."})
    body = submission("Shelter A needs water packs.")
    env["client"].post("/v1/requests", json=body, headers=auth(env))
    Worker(env["service"]).run_once()
    result = env["client"].get("/v1/requests/" + body["request_id"], headers=auth(env)).json()["result"]
    assert result["status"] == "needs_review" and result["proposal"]["quantity"] is None
    assert {"quantity_not_grounded", "missing_quantity"} <= set(result["review_reasons"])


@pytest.mark.parametrize("text,reason", [
    ("Shelter A needs water packs.", "missing_quantity"),
    ("Do not send 20 water packs to Shelter A.", "negation_requires_review"),
])
def test_source_review_signals_survive_malformed_model_output(env, text, reason):
    env["service"].providers.raw_override = '{"quantity":null}]'
    body = submission(text)
    env["client"].post("/v1/requests", json=body, headers=auth(env))
    Worker(env["service"]).run_once()
    result = env["client"].get("/v1/requests/" + body["request_id"], headers=auth(env)).json()["result"]
    assert result["status"] == "needs_review" and result["proposal"] is None
    assert {reason, "invalid_model_output"} <= set(result["review_reasons"])


def test_failure_retries_and_expired_lease_survive_restart(env):
    service = env["service"]
    clock = [time.time()]
    service.clock = lambda: clock[0]
    service.providers.error = ProviderError("ThrottlingException", True)
    body = submission()
    env["client"].post("/v1/requests", json=body, headers=auth(env))
    worker = Worker(service)
    assert worker.run_once()
    assert env["client"].get("/v1/requests/" + body["request_id"], headers=auth(env)).json()["analysis_state"] == "retrying"
    clock[0] += 5
    service.providers.error = None
    assert worker.run_once()
    assert env["client"].get("/v1/requests/" + body["request_id"], headers=auth(env)).json()["analysis_state"] == "ready_for_review"
    # Simulate a process dying after it claimed durable work.
    another = submission()
    env["client"].post("/v1/requests", json=another, headers=auth(env))
    row, version = service.store.get(*work_key("request", another["request_id"]))
    from relay_backend.store import Put
    service.store.transact(puts=[Put(*work_key("request", another["request_id"]), {**row, "lease_until": clock[0] + 120}, version)])
    assert not Worker(service).run_once()
    clock[0] += 121
    assert Worker(service).run_once()


def test_expiry_invalid_shelter_and_operation_reuse(env):
    c = env["client"]
    assert c.post("/v1/requests", json=submission(destination_shelter_id="unknown"), headers=auth(env)).status_code == 400
    expired = submission(created_at=(datetime.now(timezone.utc) - timedelta(days=2)).isoformat(),
                         expires_at=(datetime.now(timezone.utc) - timedelta(days=1)).isoformat())
    assert c.post("/v1/requests", json=expired, headers=auth(env)).status_code == 410
    body = submission()
    c.post("/v1/requests", json=body, headers=auth(env))
    other = submission(operation_id=body["operation_id"])
    assert c.post("/v1/requests", json=other, headers=auth(env)).status_code == 409
    assert env["service"].store.get(*key("request", other["request_id"])) is None


def test_audio_upload_transcript_review_same_request_pipeline(env):
    c, service = env["client"], env["service"]
    data = wav_bytes()
    body = allocation(data)
    allocated = c.post("/v1/transcriptions", json=body, headers=auth(env))
    assert allocated.status_code == 201
    identifier = body["transcription_id"]
    upload_path = "/v1/local-uploads/" + identifier
    assert c.put(upload_path, content=data, headers=auth(env, "test-requester-b")).status_code == 404
    start = {"operation_id": str(uuid4())}
    assert c.post(f"/v1/transcriptions/{identifier}/start", json=start, headers=auth(env)).status_code == 409
    assert c.put(upload_path, content=data, headers=auth(env)).status_code == 204
    assert c.post(f"/v1/transcriptions/{identifier}/start", json=start, headers=auth(env)).status_code == 202
    assert c.post(f"/v1/transcriptions/{identifier}/start", json=start, headers=auth(env)).status_code == 202
    assert c.post(f"/v1/transcriptions/{identifier}/start", json={"operation_id": str(uuid4())}, headers=auth(env)).status_code == 409
    assert c.get(f"/v1/transcriptions/{identifier}", headers=auth(env, "test-dispatcher-a")).status_code == 404
    assert Worker(service).run_once()
    result = c.get(f"/v1/transcriptions/{identifier}", headers=auth(env)).json()
    assert result["status"] == "completed" and result["transcript"]
    assert c.get("/v1/requests", headers=auth(env)).json()["items"] == []
    req = submission(result["transcript"], input_mode="reviewed_transcript", transcription_id=identifier)
    assert c.post("/v1/requests", json=req, headers=auth(env)).status_code == 201
    assert Worker(service).run_once()
    assert c.get("/v1/requests/" + req["request_id"], headers=auth(env)).json()["analysis_state"] == "ready_for_review"


@pytest.mark.parametrize("data", [b"not a wav" * 8, wav_bytes(channels=2), wav_bytes(sample_rate=44100)])
def test_invalid_audio_has_clear_state_without_job(env, data):
    c = env["client"]
    body = allocation(data)
    c.post("/v1/transcriptions", json=body, headers=auth(env))
    identifier = body["transcription_id"]
    c.put("/v1/local-uploads/" + identifier, content=data, headers=auth(env))
    assert c.post(f"/v1/transcriptions/{identifier}/start", json={"operation_id": str(uuid4())}, headers=auth(env)).status_code == 422
    record = c.get(f"/v1/transcriptions/{identifier}", headers=auth(env)).json()
    assert record["error"]["retryable"] and record["status"] == "awaiting_upload"
    assert not Worker(env["service"]).run_once()


def test_body_limit_and_gateway_identity_rejected(env):
    c = env["client"]
    assert c.post("/v1/requests", content=b"x" * 33000, headers=auth(env)).status_code == 413
    assert c.post("/v1/requests", json={**submission(), "original_sender_subject": "someone-else"}, headers=auth(env)).status_code == 422
    assert c.post("/v1/sync/push", json={}, headers=auth(env)).status_code == 404
