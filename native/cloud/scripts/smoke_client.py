"""Independent HTTP client; records evidence but never tokens or upload signatures."""
import argparse
import hashlib
import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import httpx


def run(base_url, tokens, audio_path, allow_aws=False, output=None):
    evidence = {"started_at": datetime.now(timezone.utc).isoformat(), "base_url": base_url,
                "checks": {}, "requests": [], "transcriptions": [], "native_app_integration": "NOT TESTED"}
    client = httpx.Client(base_url=base_url, timeout=20)

    def call(method, path, actor="test-requester-a", expected=(200,), **kwargs):
        headers = {"Authorization": "Bearer " + tokens[actor]} if actor else {}
        response = client.request(method, path, headers=headers, **kwargs)
        if response.status_code not in expected:
            code = response.json().get("error", {}).get("code", "unexpected_response")
            raise AssertionError(f"{method} {path}: expected {expected}, got {response.status_code} ({code})")
        return response.json() if response.content else None

    def submit(text, **changes):
        now = datetime.now(timezone.utc)
        body = {"schema_version": 1, "operation_id": str(uuid4()), "request_id": str(uuid4()),
                "incident_id": "synthetic-demo-01", "destination_shelter_id": "shelter-a",
                "origin_device_id": str(uuid4()), "original_text": text, "input_mode": "text",
                "created_at": now.isoformat(), "expires_at": (now + timedelta(hours=1)).isoformat(), "revision": 1}
        body.update(changes)
        result = call("POST", "/v1/requests", expected=(201,), json=body)
        assert result["cloud_state"] == "accepted"
        return body, result

    def poll(path, field, terminal, seconds=240):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            result = call("GET", path)
            if result[field] in terminal:
                return result
            time.sleep(2)
        raise AssertionError("Bounded poll timed out: " + path)

    try:
        health = call("GET", "/v1/health", actor=None)
        evidence["mode"] = health["mode"]
        evidence["storage"] = health["storage"]
        if health["mode"] == "aws" and not allow_aws:
            raise SystemExit("AWS mode requires --allow-chargeable-aws after explicit approval.")
        call("GET", "/v1/shelters", actor=None, expected=(401,))
        directory = call("GET", "/v1/shelters")
        assert [x["shelter_id"] for x in directory["items"]] == ["shelter-a"]
        evidence["checks"]["authentication_and_directory"] = "PASS"
        body, accepted = submit("SYNTHETIC: Shelter A needs 20 water packs.")
        request_path = "/v1/requests/" + body["request_id"]
        call("POST", "/v1/requests", json=body)
        call("POST", "/v1/requests", json={**body, "original_text": "changed content"}, expected=(409,))
        call("GET", request_path, actor="test-requester-b", expected=(404,))
        call("GET", request_path, actor="test-dispatcher-b", expected=(404,))
        call("GET", request_path, actor="test-dispatcher-a")
        call("GET", "/v1/requests?view=shelter&shelter_id=shelter-a", expected=(403,))
        call("GET", "/v1/requests?view=shelter&shelter_id=shelter-a", actor="test-dispatcher-b", expected=(403,))
        call("GET", "/v1/requests?view=shelter&shelter_id=shelter-a", actor="test-dispatcher-a")
        evidence["checks"]["idempotency_and_authorization"] = "PASS"
        final = poll(request_path, "analysis_state", {"ready_for_review", "needs_review", "failed"})
        evidence["requests"].append(final)
        assert final["analysis_state"] == "ready_for_review"
        assert final["result"]["proposal"]["quantity"] == 20
        assert final["result"]["allocation_authorized"] is False
        evidence["checks"]["text_pipeline"] = "PASS"
        for text, expected_reason in [("Shelter A needs water packs.", "missing_quantity"),
                                      ("Do not send 20 water packs to Shelter A.", "negation_requires_review")]:
            other, _ = submit(text)
            result = poll("/v1/requests/" + other["request_id"], "analysis_state", {"ready_for_review", "needs_review", "failed"})
            evidence["requests"].append(result)
            assert result["analysis_state"] == "needs_review" and expected_reason in result["result"]["review_reasons"]
        call("POST", "/v1/requests", json={**body, "request_id": str(uuid4()), "operation_id": str(uuid4()),
                                            "destination_shelter_id": "not-a-shelter"}, expected=(400,))
        evidence["checks"]["missing_quantity_negation_invalid_shelter"] = "PASS"
        if audio_path:
            audio = Path(audio_path).read_bytes()
            audio_id = str(uuid4())
            allocation = {"schema_version": 1, "operation_id": str(uuid4()), "transcription_id": audio_id,
                          "incident_id": "synthetic-demo-01", "content_type": "audio/wav", "byte_length": len(audio),
                          "sha256": hashlib.sha256(audio).hexdigest(), "language_code": "en-US"}
            result = call("POST", "/v1/transcriptions", json=allocation, expected=(201,))
            upload = result["upload"]
            if upload["method"] == "POST":
                uploaded = httpx.post(upload["url"], data=upload["fields"], files={"file": ("synthetic.wav", audio, "audio/wav")}, timeout=30)
            else:
                uploaded = client.put(upload["url"], content=audio, headers={"Authorization": "Bearer " + tokens["test-requester-a"], **upload["headers"]})
            assert uploaded.status_code in {200, 201, 204}
            start = {"operation_id": str(uuid4())}
            call("POST", f"/v1/transcriptions/{audio_id}/start", json=start, expected=(202,))
            call("POST", f"/v1/transcriptions/{audio_id}/start", json=start, expected=(202,))
            call("GET", f"/v1/transcriptions/{audio_id}", actor="test-requester-b", expected=(404,))
            transcription = poll(f"/v1/transcriptions/{audio_id}", "status", {"completed", "failed"})
            evidence["transcriptions"].append(transcription)
            assert transcription["status"] == "completed" and transcription["transcript"].strip()
            # Scripted confirmation demonstrates the contract, not a human review UI.
            reviewed, _ = submit(transcription["transcript"], input_mode="reviewed_transcript", transcription_id=audio_id)
            result = poll("/v1/requests/" + reviewed["request_id"], "analysis_state", {"ready_for_review", "needs_review", "failed"})
            evidence["requests"].append(result)
            assert result["analysis_state"] in {"ready_for_review", "needs_review"}
            evidence["checks"]["audio_to_reviewed_request"] = "PASS"
            evidence["audio_source"] = "Caller-provided fixture; label synthetic/TTS when applicable. Not a noisy-speech benchmark."
        else:
            evidence["checks"]["audio_to_reviewed_request"] = "NOT TESTED"
        evidence["checks"]["real_bedrock"] = "PASS" if health["mode"] == "aws" else "NOT TESTED"
        evidence["checks"]["real_transcribe"] = "PASS" if health["mode"] == "aws" and audio_path else "NOT TESTED"
        evidence["status"] = "PASS"
        return evidence
    except Exception as exc:
        evidence["status"] = "FAIL"
        evidence["failure"] = str(exc)
        raise
    finally:
        evidence["finished_at"] = datetime.now(timezone.utc).isoformat()
        if output:
            Path(output).write_text(json.dumps(evidence, indent=2) + "\n")
        client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--tokens", type=Path, required=True)
    parser.add_argument("--audio", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--allow-chargeable-aws", action="store_true")
    args = parser.parse_args()
    result = run(args.base_url, json.loads(args.tokens.read_text()), args.audio, args.allow_chargeable_aws, args.output)
    print(json.dumps({"status": result["status"], "mode": result["mode"], "checks": result["checks"]}, indent=2))
