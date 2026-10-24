from datetime import datetime, timedelta, timezone
from uuid import uuid4
import concurrent.futures

from conftest import auth
from relay_backend.api import build_service
from relay_backend.auth import Authenticator


def announcement(**changes):
    value = dict(announcement_id=str(uuid4()), shelter_id="shelter-a", title="SYNTHETIC test notice",
                 text="Demo supplies available at the fictional east entrance.", severity="info",
                 expires_at=(datetime.now(timezone.utc) + timedelta(hours=1)).isoformat())
    return {**value, **changes}


def test_incident_broadcast_has_no_request_dependency_and_is_authenticated(env):
    c = env["client"]
    assert c.get("/v1/announcements").status_code == 401
    assert c.post("/v1/announcements", json=announcement(), headers=auth(env)).status_code == 403
    body = announcement()
    r = c.post("/v1/announcements", json=body, headers=auth(env, "test-dispatcher-a"))
    assert r.status_code == 201, r.text
    for person in ("test-requester-a", "test-requester-b", "test-dispatcher-b"):
        assert c.get("/v1/announcements", headers=auth(env, person)).json()["items"] == [r.json()]
    env["settings"].memberships["test-requester-b"].incident_id = "separate-incident"
    assert c.get("/v1/announcements", headers=auth(env, "test-requester-b")).json()["items"] == []


def test_lost_response_retry_and_restart_do_not_duplicate(env):
    c = env["client"]; headers = auth(env, "test-dispatcher-a"); body = announcement()
    first = c.post("/v1/announcements", json=body, headers=headers)
    assert c.post("/v1/announcements", json=body, headers=headers).json() == first.json()
    assert c.post("/v1/announcements", json={**body, "text": "Changed"}, headers=headers).status_code == 409
    restarted = build_service(env["settings"])
    principal = Authenticator(env["settings"]).verify(headers["Authorization"])
    assert restarted.announcement_feed(principal)["items"] == [first.json()]
    restarted.store.close()


def test_concurrent_same_publication_is_idempotent(env):
    body = announcement(); headers = auth(env, "test-dispatcher-a")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: env["client"].post("/v1/announcements", json=body, headers=headers), range(2)))
    assert [r.status_code for r in results] == [201, 201]
    assert results[0].json() == results[1].json()


def test_withdrawal_is_versioned_and_scoped(env):
    c = env["client"]; headers = auth(env, "test-dispatcher-a"); body = announcement()
    c.post("/v1/announcements", json=body, headers=headers)
    path = "/v1/announcements/" + body["announcement_id"] + "/withdraw"
    for person in ("test-requester-a", "test-dispatcher-b"):
        assert c.post(path, json={"expected_revision": 1}, headers=auth(env, person)).status_code == 403
    assert c.post(path, json={"expected_revision": 0}, headers=headers).status_code == 409
    result = c.post(path, json={"expected_revision": 1}, headers=headers).json()
    assert result["withdrawn"] and result["revision"] == 2
    assert c.post(path, json={"expected_revision": 1}, headers=headers).json() == result
    assert c.post("/v1/announcements", json=body, headers=headers).json() == result
    assert c.get("/v1/announcements", headers=auth(env)).json()["items"] == [result]


def test_expiry_and_input_validation(env):
    c = env["client"]; headers = auth(env, "test-dispatcher-a")
    for changes in ({"title": " "}, {"text": "a" * 1501}, {"severity": "fake"},
                    {"expires_at": datetime.now(timezone.utc).isoformat()},
                    {"expires_at": (datetime.now(timezone.utc) + timedelta(days=8)).isoformat()},
                    {"expires_at": "2026-10-24T08:00:00"}):
        assert c.post("/v1/announcements", json=announcement(**changes), headers=headers).status_code == 422
    assert c.post("/v1/announcements", json=announcement(shelter_id="shelter-b"), headers=headers).status_code == 403


def test_expired_items_are_pruned_when_publishing_but_retry_stays_idempotent(env):
    c = env["client"]; headers = auth(env, "test-dispatcher-a"); body = announcement()
    original = c.post("/v1/announcements", json=body, headers=headers).json()
    original_clock = env["service"].clock
    env["service"].clock = lambda: original_clock() + 7200
    new = announcement(expires_at=(datetime.now(timezone.utc) + timedelta(hours=3)).isoformat())
    result = c.post("/v1/announcements", json=new, headers=headers); assert result.status_code == 201
    assert len(c.get("/v1/announcements", headers=auth(env)).json()["items"]) == 1
    assert c.post("/v1/announcements", json=body, headers=headers).json() == original


def details(**changes):
    return dict(expected_revision=0, address="SYNTHETIC demo building", instructions="Use the fictional east entrance.",
                latitude=0.0, longitude=0.01, **changes)


def test_shelter_details_permissions_validation_and_revision(env):
    c = env["client"]; path = "/v1/shelters/shelter-a/details"; body = details(); h = auth(env, "test-dispatcher-a")
    for person in ("test-requester-a", "test-dispatcher-b"):
        assert c.put(path, json=body, headers=auth(env, person)).status_code == 403
    for changes in ({"latitude": 91}, {"longitude": None}, {"latitude": "nan"}, {"instructions": "a" * 1501}):
        assert c.put(path, json={**body, **changes}, headers=h).status_code == 422
    first = c.put(path, json=body, headers=h); assert first.status_code == 200
    assert c.put(path, json=body, headers=h).json() == first.json()
    assert c.put(path, json={**body, "address": "Changed"}, headers=h).status_code == 409
    entry = c.get("/v1/shelters", headers=auth(env)).json()["items"][0]
    assert entry["details"] == first.json()
    assert c.get("/v1/shelters", headers=auth(env, "test-requester-b")).json()["items"][0]["details"] is None
    cleared = c.put(path, json={**body, "latitude": None, "longitude": None, "expected_revision": 1}, headers=h)
    assert cleared.status_code == 200 and cleared.json()["revision"] == 2
    assert cleared.json()["latitude"] is None
