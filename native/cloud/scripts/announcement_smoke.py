"""Explicit live synthetic announcement check using existing owned demo sessions.

Creates one short-lived TEST announcement, verifies both resident accounts can see
it, then withdraws it. No AI calls. Tokens stay in memory and are never reported.
"""
import argparse
import json
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from relay_backend.config import Settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--sessions", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(); settings = Settings.load(args.config)
    assert settings.public_base_url == "https://relay.stepcheck.app"
    base = settings.public_base_url
    report = {"scope": "Live synthetic HTTPS/API check; no physical wireless or microphone test", "started_at": datetime.now(timezone.utc).isoformat()}

    def request(url, method="GET", body=None, token=None):
        headers = {"Content-Type": "application/json"}
        if token: headers["Authorization"] = "Bearer " + token
        r = urllib.request.Request(url, method=method, headers=headers, data=None if body is None else json.dumps(body).encode())
        with urllib.request.urlopen(r, timeout=20) as response: return json.load(response)

    def token(name):
        saved = json.loads((args.sessions / name).read_text())
        r = urllib.request.Request("https://cognito-idp.us-east-1.amazonaws.com/", data=json.dumps({"ClientId": settings.client_id, "AuthFlow": "REFRESH_TOKEN_AUTH", "AuthParameters": {"REFRESH_TOKEN": saved["refresh"]}}).encode(), headers={"Content-Type": "application/x-amz-json-1.1", "X-Amz-Target": "AWSCognitoIdentityProviderService.InitiateAuth"})
        with urllib.request.urlopen(r, timeout=15) as response: return json.load(response)["AuthenticationResult"]["AccessToken"]

    try:
        staff = token("enrollment-dispatcher.private.json")
        residents = [token("enrollment-requester.private.json"), token("enrollment-requester-b.private.json")]
        directory = request(base + "/v1/shelters", token=staff)
        shelter = directory["items"][0]["shelter_id"]
        command = {"announcement_id": str(uuid4()), "shelter_id": shelter, "title": "SYNTHETIC API TEST · expires soon", "text": "Test publication and withdrawal. No real emergency or travel instruction.", "severity": "info", "expires_at": datetime.fromtimestamp(time.time() + 600, timezone.utc).isoformat()}
        started = time.monotonic()
        first = request(base + "/v1/announcements", "POST", command, staff)
        assert request(base + "/v1/announcements", "POST", command, staff) == first
        report["announcement_id"] = first["announcement_id"]
        report["publish_and_idempotent_retry_seconds"] = round(time.monotonic() - started, 3)
        for resident in residents:
            feed = request(base + "/v1/announcements", token=resident)
            assert sum(a["announcement_id"] == first["announcement_id"] for a in feed["items"]) == 1
        report["both_distinct_resident_accounts_received_same_id"] = True
        try:
            request(base + "/v1/announcements", "POST", {**command, "announcement_id": str(uuid4())}, residents[0])
            raise AssertionError("Resident publication unexpectedly allowed")
        except urllib.error.HTTPError as error:
            assert error.code == 403; report["resident_publish_status"] = error.code
        withdrawn = request(base + "/v1/announcements/" + first["announcement_id"] + "/withdraw", "POST", {"expected_revision": 1}, staff)
        assert withdrawn["withdrawn"] and withdrawn["revision"] == 2
        for resident in residents:
            item = next(a for a in request(base + "/v1/announcements", token=resident)["items"] if a["announcement_id"] == first["announcement_id"])
            assert item["withdrawn"] and item["revision"] == 2
        report["withdrawal_visible_to_both_residents"] = True
        report["active_ui_demo_announcements"] = [{"id": a["announcement_id"], "title": a["title"]} for a in request(base + "/v1/announcements", token=staff)["items"] if not a["withdrawn"] and a["title"].startswith("DEMO ONLY")]
        report["status"] = "PASS"
    except Exception as error:
        report.update(status="FAIL", error_type=type(error).__name__)
        if isinstance(error, urllib.error.HTTPError): report["http_status"] = error.code
    args.output.write_text(json.dumps(report, indent=2)); print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__": raise SystemExit(main())
