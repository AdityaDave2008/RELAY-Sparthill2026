"""Synthetic extraction/reply regressions. Fixture calls are not AWS evidence."""
import json
import time
from uuid import uuid4
from fastapi.testclient import TestClient
from conftest import auth
from test_backend import submission
from test_preview_inventory import preview
from relay_backend.analysis import validate_model_result
from relay_backend.api import create_app
from relay_backend.models import StructuredFields
from relay_backend.service import Worker


def extract(text, **changes):
    proposal=dict(item_id='water_packs',quantity=2,unit='pack',shelter_id='shelter-a',negated=False,missing_fields=[],summary='Synthetic request')
    proposal.update(changes)
    return validate_model_result(json.dumps(proposal),{'original_text':text,'destination_shelter_id':'shelter-a'},[{'shelter_id':'shelter-a','display_name':'Shelter A'}])


def test_people_room_age_and_no_internet_do_not_invalidate_supply_count():
    r=extract('No internet here. My father is 62. We need two water packs for four people in room 12, urgently.',people=4,landmark='room 12',urgency='urgent',urgency_evidence='urgently')
    assert r['status']=='ready_for_review'
    assert r['proposal']['quantity']==2 and r['proposal']['people']==4
    assert r['proposal']['urgency']=='urgent' and r['allocation_authorized'] is False


def test_people_number_cannot_become_supply_quantity():
    r=extract('We are four people and need water packs.',quantity=4,people=4)
    assert r['proposal']['quantity'] is None and r['proposal']['people']==4
    assert 'quantity_not_grounded' in r['review_reasons']


def test_stated_bottle_count_is_preserved_without_pack_conversion():
    r=extract('Please send two bottles of water for four people.',unit='bottle',people=4)
    assert r['proposal']['quantity']==2 and r['proposal']['unit']=='bottle'
    assert 'unit_mismatch' in r['review_reasons']


def test_medicine_strength_does_not_become_package_count_or_triage():
    r=extract('We need insulin 100 mg for two people.',item_id='medicines',quantity=100,unit='item',people=2,medicine_details='insulin 100 mg',urgency='immediate',urgency_evidence='insulin 100 mg')
    assert r['proposal']['quantity'] is None and r['proposal']['urgency'] is None
    assert r['proposal']['medicine_details']=='insulin 100 mg'
    assert 'medicine_staff_review' in r['review_reasons']


def test_urgency_must_be_quoted_and_match_explicit_language():
    for quote in ['right now','no rush']:
        r=extract('We need 2 water packs, no rush.',urgency='immediate',urgency_evidence=quote)
        assert r['proposal']['urgency'] is None
    assert extract('We need 2 water packs, no rush.',urgency='routine',urgency_evidence='no rush')['proposal']['urgency']=='routine'


def test_hallucinated_location_and_people_are_removed():
    r=extract('We need 2 water packs.',people=5,landmark='north entrance')
    assert r['proposal']['people'] is None and r['proposal']['landmark'] is None


def test_added_optional_fields_do_not_change_legacy_submission_shape():
    old={'item_id':'water_packs','quantity':2,'unit':'pack','people':4,'landmark':'Room 12'}
    assert StructuredFields.model_validate(old).model_dump(mode='json')==old


def test_medicine_urgency_and_updates_snapshot_survive_submission(env):
    c=env['client'];body=submission('SYNTHETIC: We need two inhalers urgently.',structured_fields={'item_id':'medicines','quantity':2,'unit':'item','people':1,'landmark':'Test room','urgency':'urgent','medicine_details':'inhalers'})
    first=c.post('/v1/requests',json=body,headers=auth(env));assert first.status_code==201
    assert c.post('/v1/requests',json=body,headers=auth(env)).status_code==200
    path='/v1/requests/'+body['request_id']
    event={'operation_id':str(uuid4()),'expected_revision':0,'text':'Synthetic staff review in progress.'}
    assert c.post(path+'/events',json=event,headers=auth(env,'test-dispatcher-a')).status_code==200
    snapshot=c.get(path+'/snapshot',headers=auth(env));assert snapshot.status_code==200
    assert snapshot.json()['history']['revision']==1
    assert snapshot.json()['submission']['structured_fields']['urgency']=='urgent'
    assert snapshot.json()['submission']['structured_fields']['medicine_details']=='inhalers'
    assert c.get(path+'/snapshot',headers=auth(env,'test-requester-b')).status_code==404
    assert c.get(path+'/snapshot').status_code==401
    denied=c.post(path+'/inventory',json={'operation_id':str(uuid4()),'action':'reserve','item_id':'water_packs','quantity':2},headers=auth(env,'test-dispatcher-a'))
    assert denied.status_code==422 and denied.json()['error']['code']=='medicine_staff_review'


def test_preview_fast_lane_reuses_conditional_lease(env):
    env['settings'].accelerate_previews=True
    with TestClient(create_app(env['settings'],env['service'])) as c:
        body=preview();path='/v1/interpretations/'+body['interpretation_id']
        assert c.post('/v1/interpretations',json=body,headers=auth(env)).status_code==201
        Worker(env['service']).run_once() # May race fast lane; only one may invoke.
        for _ in range(100):
            r=c.get(path,headers=auth(env)).json()
            if r['status']!='pending':break
            time.sleep(.01)
        assert r['status']=='ready_for_review'
        assert c.post('/v1/interpretations',json=body,headers=auth(env)).status_code==200
        assert env['service'].providers.calls==1


def test_optional_missing_field_annotation_keeps_valid_extracted_data():
    r=extract('We need two water packs for four people urgently.',people=4,urgency='urgent',urgency_evidence='urgently',missing_fields=['urgency_evidence'])
    assert r['status']=='ready_for_review' and r['proposal']['quantity']==2


def test_structured_tool_only_reports_expected_schema_without_running_tools():
    from relay_backend.analysis import extraction_tool, structured_output
    assert extraction_tool()['toolChoice']=={'tool':{'name':'extract_request'}}
    data={'quantity':2}
    response={'output':{'message':{'content':[{'toolUse':{'name':'extract_request','input':data}}]}}}
    assert json.loads(structured_output(response))==data
    response['output']['message']['content'][0]['toolUse']['name']='allocate_stock'
    assert structured_output(response)=='{}'


def test_direct_gateway_preview_race_replays_same_request(env, monkeypatch):
    from relay_backend.common import key
    c=env['client'];body=preview()
    assert c.post('/v1/interpretations',json=body,headers=auth(env)).status_code==201
    Worker(env['service']).run_once()
    request=submission(body['original_text'],interpretation_id=body['interpretation_id'])
    assert c.post('/v1/requests',json=request,headers=auth(env)).status_code==201
    real_get=env['service'].store.get;miss=[True]
    def racing_get(pk,sk):
        if (pk,sk)==key('request',request['request_id']) and miss[0]:
            miss[0]=False;return None # Sender checked just before gateway commit.
        return real_get(pk,sk)
    monkeypatch.setattr(env['service'].store,'get',racing_get)
    assert c.post('/v1/requests',json=request,headers=auth(env)).status_code==200
    assert len(c.get('/v1/requests',headers=auth(env)).json()['items'])==1
    assert env['service'].providers.calls==1
