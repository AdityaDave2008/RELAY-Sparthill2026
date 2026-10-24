import json
from conftest import auth
from test_backend import submission
from test_nearby import prepare, signed
from relay_backend.analysis import prompt
from relay_backend.common import key


def details():
    return {"display_name": "Synthetic Resident", "preferred_language": "English", "age": 24,
            "height_cm": 172.5, "weight_kg": 68.25, "blood_group": "O−", "allergies": "SYNTHETIC ALLERGY",
            "health_conditions": "SYNTHETIC CONDITION", "medications": "SYNTHETIC MEDICATION", "accessibility_needs": "SYNTHETIC SUPPORT"}


def test_profile_snapshot_is_authorized_and_immutable(env):
    c=env['client']; body=submission(requester_details=details())
    r=c.post('/v1/requests',json=body,headers=auth(env)); assert r.status_code==201, r.text
    assert c.post('/v1/requests',json=body,headers=auth(env)).status_code==200
    path='/v1/requests/'+body['request_id']+'/snapshot'
    for actor in ['test-requester-a','test-dispatcher-a']:
        assert c.get(path,headers=auth(env,actor)).json()['submission']['requester_details']==details()
    for actor in ['test-requester-b','test-dispatcher-b']:
        assert c.get(path,headers=auth(env,actor)).status_code==404
    body['requester_details']['display_name']='Changed'
    assert c.post('/v1/requests',json=body,headers=auth(env)).status_code==409


def test_profile_fields_are_not_in_bedrock_prompt():
    body=submission(requester_details=details())
    text=json.dumps(prompt(body,[]))
    assert body['original_text'] in text
    for marker in ['Synthetic Resident','SYNTHETIC ALLERGY','SYNTHETIC CONDITION','SYNTHETIC MEDICATION','SYNTHETIC SUPPORT']:
        assert marker not in text


def test_invalid_or_oversized_profile_rejected(env):
    c=env['client']
    for changes in [{'display_name':' '},{'preferred_language':'invalid'},{'age':-1},{'age':2.5},{'height_cm':0},
                    {'height_cm':301},{'weight_kg':1001},{'blood_group':'guess'},{'allergies':'a'*401},
                    {'photoJPEG':'private photo must never be accepted'}]:
        response=c.post('/v1/requests',json=submission(requester_details={**details(),**changes}),headers=auth(env))
        assert response.status_code==422


def test_legacy_replays_do_not_add_profile_to_immutable_digest(env):
    c=env['client']; body=submission()
    assert c.post('/v1/requests',json=body,headers=auth(env)).status_code==201
    row=env['service'].store.get(*key('request',body['request_id']))[0]
    assert 'requester_details' not in row['submission']
    assert c.post('/v1/requests',json={**body,'requester_details':None},headers=auth(env)).status_code==200


def test_signed_gateway_profile_and_direct_path_are_one_request(env):
    origin,signer,_,payload=prepare(env);c=env['client']
    payload['submission']['requester_details']=details()
    result=c.post('/v1/relay/requests',json=signed(origin,signer,payload),headers=auth(env,'test-dispatcher-a'))
    assert result.status_code==201, result.text
    assert result.json()['submission']['requester_details']==details()
    assert c.post('/v1/requests',json=payload['submission'],headers=auth(env)).status_code==200
