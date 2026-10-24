import concurrent.futures
from uuid import uuid4
from conftest import auth
from test_backend import submission


def setup_request(env):
    body = submission()
    assert env['client'].post('/v1/requests', json=body, headers=auth(env)).status_code == 201
    return '/v1/requests/' + body['request_id']


def command(revision=0, **kwargs):
    return dict(operation_id=str(uuid4()), expected_revision=revision, text='SYNTHETIC reply', **kwargs)


def test_profile_comes_from_verified_membership(env):
    response = env['client'].get('/v1/me', headers=auth(env)).json()
    assert response['role'] == 'requester' and response['shelter_ids'] == ['shelter-a']
    assert env['client'].get('/v1/me').status_code == 401


def test_replies_idempotent_and_scoped(env):
    c=env['client']; path=setup_request(env)
    body=command()
    a=c.post(path+'/events', json=body, headers=auth(env)); assert a.status_code==200
    assert c.post(path+'/events',json=body,headers=auth(env)).json()==a.json()
    assert c.post(path+'/events',json={**body,'text':'Changed'},headers=auth(env)).status_code==409
    assert c.get(path+'/history',headers=auth(env,'test-requester-b')).status_code==404
    assert c.post(path+'/events',json=command(1),headers=auth(env,'test-dispatcher-b')).status_code==404
    r=c.post(path+'/events',json=command(1),headers=auth(env,'test-dispatcher-a'))
    assert r.json()['events'][-1]['author_role']=='dispatcher'


def test_status_permissions_and_transitions(env):
    c=env['client']; path=setup_request(env)
    assert c.post(path+'/events',json=command(status='accepted'),headers=auth(env)).status_code==403
    assert c.post(path+'/events',json=command(status='completed'),headers=auth(env,'test-dispatcher-a')).status_code==409
    # Build 10 prevents legacy progress commands from bypassing the stock ledger.
    for status in ['accepted','in_progress','completed']:
        r=c.post(path+'/events',json=command(status=status),headers=auth(env,'test-dispatcher-a'))
        assert r.status_code==409 and r.json()['error']['code']=='inventory_action_required'
    assert c.get(path+'/history',headers=auth(env)).json()['revision']==0


def test_owner_cancel_and_restart(env):
    c=env['client']; path=setup_request(env)
    assert c.post(path+'/events',json=command(status='cancelled'),headers=auth(env)).status_code==200
    from relay_backend.api import build_service
    from relay_backend.auth import Authenticator
    other=build_service(env['settings'])
    p=Authenticator(env['settings']).verify(auth(env)['Authorization'])
    assert other.request_history(p,path.split('/')[-1])['status']=='cancelled'
    other.store.close()


def test_concurrent_event_only_one_wins(env):
    c=env['client']; path=setup_request(env)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda _:c.post(path+'/events',json=command(),headers=auth(env)).status_code,range(2)))
    assert sorted(results)==[200,409]
    assert len(c.get(path+'/history',headers=auth(env)).json()['events'])==1
