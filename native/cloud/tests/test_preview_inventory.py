"""Fixture-only acceptance, failure, restart and competing stock transaction tests."""
import concurrent.futures
import json
import threading
import time
from datetime import datetime, timezone
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from conftest import auth
from test_backend import submission, allocation, wav_bytes
from relay_backend.api import build_service, create_app
from relay_backend.auth import Authenticator
from relay_backend.models import InventoryCommand, RequestLocation, RequestSubmission, RequestEventCommand
from relay_backend.providers import ProviderError
from relay_backend.service import APIError, PREFIX, WORK, Worker, digest, key
from relay_backend.store import Put


def preview(**changes):
    body = dict(operation_id=str(uuid4()), interpretation_id=str(uuid4()), incident_id="synthetic-demo-01",
                destination_shelter_id="shelter-a", original_text="Shelter A needs 2 water packs.")
    return {**body, **changes}


def stock(env, delta=10, revision=0, **changes):
    body = dict(operation_id=str(uuid4()), item_id="water_packs", quantity_delta=delta,
                expected_revision=revision, note="Synthetic fixture stock")
    body.update(changes)
    return env["client"].post("/v1/inventory/shelter-a/adjust", json=body, headers=auth(env,"test-dispatcher-a")), body


def request(env, **changes):
    body = submission("Shelter A needs 2 water packs.", **changes)
    assert env["client"].post("/v1/requests", json=body, headers=auth(env)).status_code == 201
    return "/v1/requests/" + body["request_id"]


def action(env, path, kind="reserve", **changes):
    body = dict(operation_id=str(uuid4()), action=kind)
    if kind == "reserve":
        body.update(item_id="water_packs", quantity=2)
    body.update(changes)
    return env["client"].post(path+"/inventory", json=body, headers=auth(env,"test-dispatcher-a")), body


def current_stock(env):
    r = env["client"].get("/v1/inventory?shelter_id=shelter-a", headers=auth(env,"test-dispatcher-a"))
    assert r.status_code == 200
    return next(x for x in r.json()["items"] if x["item_id"] == "water_packs")


def test_preview_before_send_durable_replay_budget_and_inbox(env):
    c,s=env["client"],env["service"]; body=preview(); path="/v1/interpretations/"+body["interpretation_id"]
    env["settings"].max_requests=1
    first=c.post("/v1/interpretations",json=body,headers=auth(env))
    assert first.status_code==201 and first.json()["status"]=="pending" and s.providers.calls==0
    assert c.post("/v1/interpretations",json=body,headers=auth(env)).status_code==200
    assert c.post("/v1/interpretations",json={**body,"original_text":"changed"},headers=auth(env)).status_code==409
    assert c.get("/v1/requests",headers=auth(env)).json()["items"]==[]
    assert c.get("/v1/requests?view=shelter&shelter_id=shelter-a",headers=auth(env,"test-dispatcher-a")).json()["items"]==[]
    assert c.get(path,headers=auth(env,"test-requester-b")).status_code==404
    assert c.get(path,headers=auth(env,"test-dispatcher-a")).status_code==404
    old=build_service(env["settings"])
    assert Worker(old).run_once() and old.providers.calls==1
    result=c.get(path,headers=auth(env)).json()
    assert result["status"]=="ready_for_review" and result["result"]["allocation_authorized"] is False
    send=submission(body["original_text"],interpretation_id=body["interpretation_id"])
    assert c.post("/v1/requests",json=send,headers=auth(env)).status_code==201
    assert c.post("/v1/requests",json=send,headers=auth(env)).status_code==200
    assert not Worker(old).run_once() and old.providers.calls==1
    assert s.store.get(PREFIX+"BUDGET","requests")[0]["count"]==1
    assert len(c.get("/v1/requests",headers=auth(env)).json()["items"])==1
    assert c.post("/v1/requests",json=submission(body["original_text"],interpretation_id=body["interpretation_id"]),headers=auth(env)).status_code==409
    assert c.post("/v1/interpretations",json=preview(),headers=auth(env)).status_code==429
    assert c.get("/v1/requests/"+send["request_id"]+"/inventory",headers=auth(env)).json()["reservation"] is None
    old.store.close()


def test_preview_mismatch_pending_and_membership(env):
    c=env["client"];body=preview();assert c.post("/v1/interpretations",json=body,headers=auth(env)).status_code==201
    send=submission(body["original_text"],interpretation_id=body["interpretation_id"])
    assert c.post("/v1/requests",json=send,headers=auth(env)).json()["error"]["code"]=="interpretation_not_ready"
    Worker(env["service"]).run_once()
    assert c.post("/v1/requests",json={**send,"original_text":"Shelter A needs 9 water packs."},headers=auth(env)).json()["error"]["code"]=="interpretation_mismatch"
    assert c.post("/v1/interpretations",json=preview(destination_shelter_id="shelter-b"),headers=auth(env)).status_code==403
    assert c.post("/v1/interpretations",json=preview(),headers=auth(env,"test-requester-b")).status_code==403
    assert c.post("/v1/interpretations",json=preview(),headers={}).status_code==401


def test_preview_transcription_must_be_owned_completed_same_incident(env):
    c=env["client"];data=wav_bytes();body=allocation(data);identifier=body["transcription_id"]
    assert c.post("/v1/transcriptions",json=body,headers=auth(env)).status_code==201
    assert c.post("/v1/interpretations",json=preview(transcription_id=identifier),headers=auth(env)).status_code==409
    assert c.post("/v1/interpretations",json=preview(destination_shelter_id="shelter-b",transcription_id=identifier),headers=auth(env,"test-requester-b")).status_code==404
    c.put("/v1/local-uploads/"+identifier,content=data,headers=auth(env))
    c.post("/v1/transcriptions/"+identifier+"/start",json={"operation_id":str(uuid4())},headers=auth(env))
    Worker(env["service"]).run_once()
    assert c.post("/v1/interpretations",json=preview(transcription_id=identifier),headers=auth(env)).status_code==201


def test_preview_transient_retry_and_crash_attempt_cap(env):
    s,c=env["service"],env["client"];now=[time.time()];s.clock=lambda:now[0]
    s.providers.error=ProviderError("throttled",True)
    body=preview();c.post("/v1/interpretations",json=body,headers=auth(env))
    assert Worker(s).run_once()
    assert c.get("/v1/interpretations/"+body["interpretation_id"],headers=auth(env)).json()["status"]=="pending"
    s.providers.error=None;now[0]+=4;assert Worker(s).run_once()
    assert c.get("/v1/interpretations/"+body["interpretation_id"],headers=auth(env)).json()["status"]=="ready_for_review"
    calls=[]
    def crash(*args):
        calls.append(True);raise RuntimeError("Fixture crash")
    s.providers.analyze=crash;body=preview();c.post("/v1/interpretations",json=body,headers=auth(env))
    for _ in range(3):
        with pytest.raises(RuntimeError): Worker(s).run_once()
        now[0]+=121
    assert Worker(s).run_once()
    result=c.get("/v1/interpretations/"+body["interpretation_id"],headers=auth(env)).json()
    assert result["status"]=="failed" and result["error"]["code"]=="analysis_attempt_limit" and len(calls)==3


def test_legacy_submission_digest_and_new_optional_fields(env):
    c,s=env["client"],env["service"];body=submission();assert c.post("/v1/requests",json=body,headers=auth(env)).status_code==201
    assert c.post("/v1/requests",json={**body,"location":None,"structured_fields":None,"interpretation_id":None},headers=auth(env)).status_code==200
    stored=s.store.get(*key("request",body["request_id"]))[0]
    assert not set(["location","structured_fields","interpretation_id"]) & stored["submission"].keys()
    assert digest(stored["submission"])==stored["payload_hash"]
    location=dict(latitude=37.3352,longitude=-121.8811,horizontal_accuracy=25,captured_at=datetime.now(timezone.utc).isoformat(),precision="precise",source="device")
    new=submission(location=location,structured_fields=dict(item_id="water_packs",quantity=2,unit="pack",people=3,landmark="Synthetic gate"))
    r=c.post("/v1/requests",json=new,headers=auth(env));assert r.status_code==201
    assert r.json()["submission"]["location"]["latitude"]==37.3352
    from relay_backend.analysis import prompt
    raw=json.dumps(prompt(r.json()["submission"],[]))
    assert "37.3352" not in raw and "121.8811" not in raw and "Synthetic gate" not in raw
    unknown=submission(structured_fields=dict(item_id="water_packs",quantity=None,unit=None,people=1000000))
    assert c.post("/v1/requests",json=unknown,headers=auth(env)).status_code==201
    unknown["structured_fields"]["people"]=1000001
    assert c.post("/v1/requests",json=unknown,headers=auth(env)).status_code==422


@pytest.mark.parametrize("field,value",[("latitude",91),("longitude",-181),("latitude",float("nan")),("longitude",float("inf")),("horizontal_accuracy",-1),("horizontal_accuracy",True),("captured_at","2026-10-24T00:00:00")])
def test_invalid_location_rejected(field,value):
    body=dict(latitude=0.0,longitude=0.0,horizontal_accuracy=10,captured_at="2026-10-24T00:00:00Z",precision="approximate",source="manual")
    with pytest.raises(ValidationError): RequestLocation.model_validate({**body,field:value})


def test_stock_adjustment_auth_revision_replay_and_underflow(env):
    c=env["client"]
    assert current_stock(env)==dict(item_id="water_packs",unit="pack",on_hand=0,reserved=0,available=0,revision=0)
    r,body=stock(env);assert r.status_code==200
    assert c.post("/v1/inventory/shelter-a/adjust",json=body,headers=auth(env,"test-dispatcher-a")).json()==r.json()
    assert c.post("/v1/inventory/shelter-a/adjust",json={**body,"quantity_delta":11},headers=auth(env,"test-dispatcher-a")).status_code==409
    assert c.get("/v1/inventory?shelter_id=shelter-a",headers=auth(env)).status_code==403
    assert c.get("/v1/inventory?shelter_id=shelter-a",headers=auth(env,"test-dispatcher-b")).status_code==403
    assert c.post("/v1/inventory/shelter-a/adjust",json=body,headers=auth(env)).status_code==403
    assert stock(env,delta=-11,revision=1)[0].status_code==409
    assert stock(env,delta=1,revision=0)[0].status_code==409
    assert stock(env,item_id="unsupported",revision=1)[0].status_code==422
    assert stock(env,delta=True,revision=1)[0].status_code==422
    assert current_stock(env)["on_hand"]==10


def test_reserve_fulfill_restart_replays_and_roles(env):
    c=env["client"];stock(env);path=request(env)
    r,body=action(env,path,expected_inventory_revision=1);assert r.status_code==200
    assert r.json()["reservation"]["status"]=="reserved" and r.json()["history"]["status"]=="accepted"
    assert r.json()["history"]["resource_allocation_verified"] is True
    assert r.json()["history"]["physical_delivery_verified"] is False
    assert current_stock(env)["available"]==8
    assert c.post(path+"/inventory",json=body,headers=auth(env,"test-dispatcher-a")).json()==r.json()
    assert c.post(path+"/inventory",json={**body,"quantity":3},headers=auth(env,"test-dispatcher-a")).status_code==409
    assert c.post(path+"/inventory",json=body,headers=auth(env)).status_code==403
    assert c.get(path+"/inventory",headers=auth(env,"test-requester-b")).status_code==404
    assert c.post(path+"/inventory",json=body,headers=auth(env,"test-dispatcher-b")).status_code==404
    assert stock(env,delta=-9,revision=2)[0].status_code==409
    assert action(env,path,"fulfill",quantity=1)[0].status_code==409
    r,body=action(env,path,"fulfill",expected_inventory_revision=2);assert r.status_code==200
    assert current_stock(env)==dict(item_id="water_packs",unit="pack",on_hand=8,reserved=0,available=8,revision=3)
    replacement=build_service(env["settings"]);cc=TestClient(create_app(env["settings"],replacement))
    assert cc.post(path+"/inventory",json=body,headers=auth(env,"test-dispatcher-a")).json()==r.json()
    assert action(env,path,"fulfill")[0].status_code==409
    assert cc.get(path,headers=auth(env)).json()["fulfillment_state"]=="fulfilled"
    assert cc.get(path+"/history",headers=auth(env)).json()["revision"]==2
    assert len(replacement.store.query(PREFIX+"STOCK_LEDGER#synthetic-demo-01#shelter-a#water_packs")[0])==3
    replacement.store.close()


@pytest.mark.parametrize("close",["release","cancelled","rejected"])
def test_release_cancel_and_old_reject_return_stock_atomically(env,close):
    stock(env);path=request(env);assert action(env,path)[0].status_code==200;c=env["client"]
    if close=="release":
        r,body=action(env,path,"release");route=path+"/inventory";actor="test-dispatcher-a"
    else:
        body=dict(operation_id=str(uuid4()),expected_revision=1,status=close)
        actor="test-requester-a" if close=="cancelled" else "test-dispatcher-a"
        route=path+"/events";r=c.post(route,json=body,headers=auth(env,actor))
    assert r.status_code==200
    assert c.post(route,json=body,headers=auth(env,actor)).json()==r.json()
    assert current_stock(env)["available"]==10 and current_stock(env)["reserved"]==0
    reservation=c.get(path+"/inventory",headers=auth(env)).json()
    assert reservation["reservation"]["status"]=="released" and reservation["history"]["revision"]==2
    assert reservation["history"]["resource_allocation_verified"] is False
    assert action(env,path,"fulfill")[0].status_code==409


def test_legacy_completed_cannot_bypass_inventory(env):
    stock(env);path=request(env);assert action(env,path)[0].status_code==200;c=env["client"]
    body=dict(operation_id=str(uuid4()),expected_revision=1,status="in_progress")
    assert c.post(path+"/events",json=body,headers=auth(env,"test-dispatcher-a")).status_code==200
    body=dict(operation_id=str(uuid4()),expected_revision=2,status="completed")
    r=c.post(path+"/events",json=body,headers=auth(env,"test-dispatcher-a"))
    assert r.status_code==409 and r.json()["error"]["code"]=="inventory_action_required"
    assert current_stock(env)["reserved"]==2
    assert action(env,path,"fulfill")[0].status_code==200


def test_two_independent_store_connections_cannot_overbook(env):
    stock(env,delta=3);paths=[request(env),request(env)]
    services=[build_service(env["settings"]),build_service(env["settings"])]
    barrier=threading.Barrier(2)
    for s in services:
        original=s.inventory_row
        def synchronized(*args,original=original):
            result=original(*args);barrier.wait(timeout=5);return result
        s.inventory_row=synchronized
    principal=Authenticator(env["settings"]).verify(auth(env,"test-dispatcher-a")["Authorization"])
    def attempt(index):
        try:
            services[index].change_request_inventory(principal,paths[index].split("/")[-1],InventoryCommand(operation_id=uuid4(),action="reserve",item_id="water_packs",quantity=2))
            return 200
        except APIError as e: return e.status
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(attempt,range(2)))==[200,409]
    assert current_stock(env)["reserved"]==2 and current_stock(env)["available"]==1
    states=[env["client"].get(p+"/inventory",headers=auth(env)).json() for p in paths]
    assert sum(x["reservation"] is not None for x in states)==1
    assert sorted(x["history"]["revision"] for x in states)==[0,1]
    for s in services:s.store.close()


def test_old_committed_event_operation_still_replays(env):
    path=request(env);identifier=path.split("/")[-1];c=env["client"];op=str(uuid4())
    body=dict(operation_id=op,expected_revision=0,text="Legacy reply",status=None)
    history=dict(request_id=identifier,revision=1,status="new",events=[dict(event_id=op,revision=1,author_role="requester",text="Legacy reply",status=None,created_at=datetime.now(timezone.utc).isoformat())],resource_allocation_verified=False)
    env["service"].store.transact(puts=[Put(*key("history",identifier),history),Put(PREFIX+"OP#test-requester-a",op,{"event_request_id":identifier,"hash":digest(body)})])
    r=c.post(path+"/events",json=body,headers=auth(env));assert r.status_code==200
    assert r.json()["revision"]==1 and len(r.json()["events"])==1


def test_parallel_preview_replay_spends_one_slot(env):
    body=preview();c=env["client"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        codes=list(pool.map(lambda _:c.post("/v1/interpretations",json=body,headers=auth(env)).status_code,range(8)))
    assert codes.count(201)==1 and codes.count(200)==7
    assert env["service"].store.get(PREFIX+"BUDGET","requests")[0]["count"]==1
    assert len(env["service"].store.query(WORK)[0])==1


def test_one_preview_cannot_create_two_requests_concurrently(env):
    body=preview();env["client"].post("/v1/interpretations",json=body,headers=auth(env));Worker(env["service"]).run_once()
    services=[build_service(env["settings"]),build_service(env["settings"])];barrier=threading.Barrier(2)
    for s in services:
        original=s.preview_for_submission
        def synchronized(*args,original=original):
            result=original(*args);barrier.wait(timeout=5);return result
        s.preview_for_submission=synchronized
    principal=Authenticator(env["settings"]).verify(auth(env)["Authorization"])
    def attempt(i):
        try:
            services[i].submit(principal,RequestSubmission.model_validate(submission(body["original_text"],interpretation_id=body["interpretation_id"])))
            return 201
        except APIError as e:return e.status
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(attempt,range(2)))==[201,409]
    assert len(env["client"].get("/v1/requests",headers=auth(env)).json()["items"])==1
    assert env["service"].store.get(PREFIX+"BUDGET","requests")[0]["count"]==1
    for s in services:s.store.close()


def test_cancellation_racing_fulfillment_has_one_consistent_outcome(env):
    stock(env);path=request(env);action(env,path);identifier=path.split("/")[-1]
    services=[build_service(env["settings"]),build_service(env["settings"])];barrier=threading.Barrier(2)
    for s in services:
        original=s.inventory_row
        def synchronized(*args,original=original):
            result=original(*args);barrier.wait(timeout=5);return result
        s.inventory_row=synchronized
    requester=Authenticator(env["settings"]).verify(auth(env)["Authorization"])
    dispatcher=Authenticator(env["settings"]).verify(auth(env,"test-dispatcher-a")["Authorization"])
    def attempt(i):
        try:
            if i==0:services[i].append_request_event(requester,identifier,RequestEventCommand(operation_id=uuid4(),expected_revision=1,status="cancelled"))
            else:services[i].change_request_inventory(dispatcher,identifier,InventoryCommand(operation_id=uuid4(),action="fulfill"))
            return 200
        except APIError as e:return e.status
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(attempt,range(2)))==[200,409]
    inv=env["client"].get(path+"/inventory",headers=auth(env)).json();after=current_stock(env)
    assert after["reserved"]==0 and inv["history"]["revision"]==2
    assert (after["on_hand"],inv["reservation"]["status"],inv["history"]["status"]) in [(8,"fulfilled","completed"),(10,"released","cancelled")]
    for s in services:s.store.close()


def test_lost_reservation_response_restart_replays_without_deducting_twice(env):
    stock(env);path=request(env);s=env["service"];original=s.store.transact
    def commit_then_disconnect(*args,**kwargs):
        original(*args,**kwargs);raise RuntimeError("Fixture lost response after durable commit")
    s.store.transact=commit_then_disconnect
    body=dict(operation_id=str(uuid4()),action="reserve",item_id="water_packs",quantity=2)
    with pytest.raises(RuntimeError):env["client"].post(path+"/inventory",json=body,headers=auth(env,"test-dispatcher-a"))
    replacement=build_service(env["settings"]);c=TestClient(create_app(env["settings"],replacement))
    r=c.post(path+"/inventory",json=body,headers=auth(env,"test-dispatcher-a"));assert r.status_code==200
    assert r.json()["history"]["revision"]==1 and current_stock(env)["reserved"]==2
    replacement.store.close()


def test_full_history_does_not_trap_reserved_stock(env):
    stock(env);path=request(env);action(env,path);identifier=path.split("/")[-1]
    row=env["service"].store.get(*key("history",identifier));history=row[0]
    event=history["events"][0]
    history["events"]=[{**event,"event_id":str(uuid4()),"revision":i+1,"status":None} for i in range(100)]
    history["revision"]=100
    env["service"].store.transact(puts=[Put(*key("history",identifier),history,row[1])])
    body=dict(operation_id=str(uuid4()),expected_revision=100,status="cancelled")
    assert env["client"].post(path+"/events",json=body,headers=auth(env)).status_code==200
    assert current_stock(env)["available"]==10 and current_stock(env)["reserved"]==0
