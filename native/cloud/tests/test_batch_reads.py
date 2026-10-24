"""Inbox batching must retain permissions, pagination and complete strong reads."""
from uuid import uuid4

import pytest
from botocore.exceptions import ClientError
from botocore.stub import Stubber

from conftest import auth
from test_backend import submission
from test_dynamo_adapter import adapter
from relay_backend.service import PREFIX, key
from relay_backend.store import Put


def wire(pair, value):
    return {"pk":{"S":pair[0]},"sk":{"S":pair[1]},"v":{"N":"2"},"payload":{"S":'{"value":'+str(value)+'}'}}


def params(store, keys):
    return {"RequestItems":{store.table:{"Keys":[store.key(*pair) for pair in keys],"ConsistentRead":True}}}


def test_unordered_partial_missing_and_duplicate_keys(monkeypatch):
    client,store=adapter();keys=[key("request",str(i)) for i in range(3)]
    monkeypatch.setattr("relay_backend.store.time.sleep",lambda _:None)
    with Stubber(client) as stub:
        stub.add_response("batch_get_item",{"Responses":{store.table:[wire(keys[1],20)]},
                           "UnprocessedKeys":{store.table:{"Keys":[store.key(*keys[0])]}}},params(store,keys))
        stub.add_response("batch_get_item",{"Responses":{store.table:[wire(keys[0],10)]}},params(store,[keys[0]]))
        result=store.get_many([*keys,keys[0]])
        assert result=={keys[0]:({"value":10},2),keys[1]:({"value":20},2),keys[2]:None}
        stub.assert_no_pending_responses()


def test_maximum_batch_size_and_empty_input():
    client,store=adapter();keys=[key("request",str(i)) for i in range(101)]
    with Stubber(client) as stub:
        assert store.get_many([])=={}
        stub.add_response("batch_get_item",{"Responses":{}},params(store,keys[:100]))
        stub.add_response("batch_get_item",{"Responses":{}},params(store,keys[100:]))
        assert store.get_many(keys)==dict.fromkeys(keys)
        stub.assert_no_pending_responses()


def test_denied_batch_uses_existing_get_permission_and_remembers_denial():
    client,store=adapter();a,b=key("request","a"),key("request","b")
    with Stubber(client) as stub:
        stub.add_client_error("batch_get_item",service_error_code="AccessDeniedException",expected_params=params(store,[a]))
        stub.add_response("get_item",{"Item":wire(a,1)},dict(TableName=store.table,Key=store.key(*a),ConsistentRead=True))
        assert store.get_many([a])[a]==({"value":1},2)
        # A second poll must not add another denied BatchGetItem round trip.
        stub.add_response("get_item",{"Item":wire(b,2)},dict(TableName=store.table,Key=store.key(*b),ConsistentRead=True))
        assert store.get_many([b])[b]==({"value":2},2)
        stub.assert_no_pending_responses()


def test_exhausted_unprocessed_keys_are_read_not_silently_omitted(monkeypatch):
    client,store=adapter();a=key("request","a")
    monkeypatch.setattr("relay_backend.store.time.sleep",lambda _:None)
    with Stubber(client) as stub:
        for _ in range(3):
            stub.add_response("batch_get_item",{"Responses":{},"UnprocessedKeys":{store.table:{"Keys":[store.key(*a)]}}},params(store,[a]))
        stub.add_response("get_item",{"Item":wire(a,9)},dict(TableName=store.table,Key=store.key(*a),ConsistentRead=True))
        assert store.get_many([a])[a]==({"value":9},2)
        stub.assert_no_pending_responses()


def test_other_service_failures_are_not_treated_as_missing_rows():
    client,store=adapter();a=key("request","a")
    with Stubber(client) as stub:
        stub.add_client_error("batch_get_item",service_error_code="InternalServerError",expected_params=params(store,[a]))
        with pytest.raises(ClientError):store.get_many([a])
        stub.assert_no_pending_responses()


def test_all_namespaces_are_checked_before_any_batch_or_fallback_call():
    client,store=adapter()
    with Stubber(client):
        with pytest.raises(ValueError):store.get_many([key("request","a"),("OTHER_PROJECT","META")])
        store._batch_get_denied=True
        with pytest.raises(ValueError):store.get_many([key("request","a"),("OTHER_PROJECT","META")])


def test_paginated_batch_keeps_authorization_order_and_reservation_projection(env,monkeypatch):
    c,s=env["client"],env["service"]
    bodies=[submission() for _ in range(3)]
    for body in bodies:assert c.post("/v1/requests",json=body,headers=auth(env)).status_code==201
    foreign=submission(destination_shelter_id="shelter-b")
    assert c.post("/v1/requests",json=foreign,headers=auth(env,"test-requester-b")).status_code==201
    # A dangling or foreign index reference must neither disclose a row nor break its page cursor.
    s.store.transact(puts=[Put(PREFIX+"USER#test-requester-a","!0-missing",{"request_id":str(uuid4())}),
                           Put(PREFIX+"USER#test-requester-a","!1-foreign",{"request_id":foreign["request_id"]}),
                           Put(*key("reservation",bodies[0]["request_id"]),{"item_id":"water_packs","quantity":2,"unit":"pack","status":"reserved"})])
    batches=[];original=s.store.get_many
    def batched(keys):
        batches.append(list(keys));return original(keys)
    monkeypatch.setattr(s.store,"get_many",batched)
    def no_point_reads(*args):raise AssertionError("Inbox must not add one GetItem per record/reservation")
    monkeypatch.setattr(s.store,"get",no_point_reads)
    first=c.get("/v1/requests?view=mine&limit=2",headers=auth(env)).json()
    assert first["items"]==[] and first["next_cursor"]
    second=c.get("/v1/requests",params={"limit":2,"cursor":first["next_cursor"]},headers=auth(env)).json()
    assert [x["request_id"] for x in second["items"]]==[b["request_id"] for b in bodies[:2]]
    assert [x["assignment_state"] for x in second["items"]]==["reserved","unassigned"]
    assert second["items"][0]["reservation"]["quantity"]==2
    assert second["items"][1]["reservation"] is None
    assert [x["history"]["request_id"] for x in second["items"]]==[b["request_id"] for b in bodies[:2]]
    assert all(x["history"]["status"]=="new" for x in second["items"])
    last=c.get("/v1/requests",params={"limit":2,"cursor":second["next_cursor"]},headers=auth(env)).json()
    assert [x["request_id"] for x in last["items"]]==[bodies[2]["request_id"]] and last["next_cursor"] is None
    assert [len(x) for x in batches]==[6,6,3]
    assert c.get("/v1/requests",params={"cursor":first["next_cursor"]},headers=auth(env,"test-requester-b")).status_code==400
    assert c.get("/v1/requests?view=shelter&shelter_id=shelter-a",headers=auth(env)).status_code==403
