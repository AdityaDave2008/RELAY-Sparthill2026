import base64
import json
from uuid import uuid4

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, x25519

from conftest import auth
from test_backend import submission
from relay_backend.common import PREFIX


def device():
    signing = ec.generate_private_key(ec.SECP256R1())
    encryption = x25519.X25519PrivateKey.generate()
    public = {'device_id': str(uuid4()),
              'signing_key': base64.b64encode(signing.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)).decode(),
              'encryption_key': base64.b64encode(encryption.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()}
    return public, signing


def enroll(env, owner):
    public, signing = device()
    r = env['client'].post('/v1/devices', headers=auth(env, owner), json=public)
    assert r.status_code == 200, r.text
    return public, signing


def prepare(env):
    origin, signer = enroll(env, 'test-requester-a')
    target, _ = enroll(env, 'test-dispatcher-a')
    c = env['client']
    r = c.put('/v1/shelters/shelter-a/receiver', headers=auth(env, 'test-dispatcher-a'), json={'device_id': target['device_id'], 'expected_revision': 0})
    assert r.status_code == 200, r.text
    body = submission(origin_device_id=origin['device_id'])
    body['operation_id'] = body['request_id']
    payload = {'schema_version': 1, 'submission': body, 'sender_subject': 'test-requester-a', 'receiver_subject': 'test-dispatcher-a', 'receiving_device_id': target['device_id'], 'sender_encryption_key': origin['encryption_key'], 'receiver_signing_key': target['signing_key']}
    return origin, signer, target, payload


def signed(origin, signer, payload):
    raw = json.dumps(payload, separators=(',', ':'), sort_keys=True).encode()
    return {'body': base64.b64encode(raw).decode(), 'signature': base64.b64encode(signer.sign(raw, ec.ECDSA(hashes.SHA256()))).decode(), 'signing_key': origin['signing_key']}


def test_gateway_preserves_origin_owner_and_deduplicates_direct_upload(env):
    origin, signer, target, payload = prepare(env); c = env['client']; identifier = payload['submission']['request_id']
    envelope = signed(origin, signer, payload)
    r = c.post('/v1/relay/requests', headers=auth(env, 'test-dispatcher-a'), json=envelope)
    assert r.status_code == 201, r.text
    assert c.post('/v1/relay/requests', headers=auth(env, 'test-dispatcher-a'), json=envelope).status_code == 200
    assert c.post('/v1/requests', headers=auth(env), json=payload['submission']).status_code == 200
    assert c.get('/v1/requests/'+identifier, headers=auth(env)).status_code == 200
    assert c.get('/v1/requests/'+identifier, headers=auth(env, 'test-requester-b')).status_code == 404
    assert env['service'].store.get(PREFIX+'BUDGET', 'requests')[0]['count'] == 1
    directory = c.get('/v1/shelters', headers=auth(env)).json()['items']
    assert directory[0]['receiver'] == {**target, 'revision': 1, 'account_subject': 'test-dispatcher-a'}
    other = c.get('/v1/shelters', headers=auth(env, 'test-requester-b')).json()['items']
    assert all(x['receiver'] is None for x in other)


def test_direct_upload_before_gateway_is_also_one_request(env):
    origin, signer, _, payload = prepare(env); c = env['client']
    assert c.post('/v1/requests', headers=auth(env), json=payload['submission']).status_code == 201
    r = c.post('/v1/relay/requests', headers=auth(env, 'test-dispatcher-a'), json=signed(origin, signer, payload))
    assert r.status_code == 200, r.text
    assert env['service'].store.get(PREFIX+'BUDGET', 'requests')[0]['count'] == 1


def test_sender_signature_detects_tampering_and_does_not_enqueue(env):
    origin, signer, _, payload = prepare(env); c = env['client']; envelope = signed(origin, signer, payload)
    payload['submission']['original_text'] = 'Tampered amount'
    envelope['body'] = base64.b64encode(json.dumps(payload).encode()).decode()
    r = c.post('/v1/relay/requests', headers=auth(env, 'test-dispatcher-a'), json=envelope)
    assert r.status_code == 422 and r.json()['error']['code'] == 'invalid_sender_signature'
    assert env['service'].store.get(PREFIX+'BUDGET', 'requests') is None


def test_self_asserted_signature_cannot_impersonate_enrolled_sender(env):
    origin, _, _, payload = prepare(env); attacker, signer = device()
    r = env['client'].post('/v1/relay/requests', headers=auth(env, 'test-dispatcher-a'), json=signed(attacker, signer, payload))
    assert r.status_code == 403 and r.json()['error']['code'] == 'sender_not_enrolled'
    assert env['service'].store.get(PREFIX+'BUDGET', 'requests') is None


def test_unprivileged_and_wrong_shelter_gateways_are_rejected(env):
    origin, signer, _, payload = prepare(env); c = env['client']; envelope = signed(origin, signer, payload)
    assert c.post('/v1/relay/requests', json=envelope).status_code == 401
    assert c.post('/v1/relay/requests', headers=auth(env), json=envelope).status_code == 403
    assert c.post('/v1/relay/requests', headers=auth(env, 'test-dispatcher-b'), json=envelope).status_code == 403


def test_enrollment_cannot_take_over_device_or_replace_keys(env):
    public, _ = enroll(env, 'test-requester-a'); c = env['client']
    assert c.post('/v1/devices', headers=auth(env), json=public).status_code == 200
    # Switching accounts on the same physical device enrolls a separate binding.
    assert c.post('/v1/devices', headers=auth(env, 'test-requester-b'), json=public).status_code == 200
    different, _ = device(); different['device_id'] = public['device_id']
    assert c.post('/v1/devices', headers=auth(env), json=different).status_code == 409
    assert c.put('/v1/shelters/shelter-a/receiver', headers=auth(env), json={'device_id': public['device_id'], 'expected_revision': 0}).status_code == 403
    assert c.put('/v1/shelters/shelter-a/receiver', headers=auth(env, 'test-dispatcher-a'), json={'device_id': public['device_id'], 'expected_revision': 0}).status_code == 403


def test_receiver_replacement_requires_current_revision_and_old_route_is_not_ingested(env):
    origin, signer, _, payload = prepare(env); c = env['client']; new, _ = enroll(env, 'test-dispatcher-a')
    command = {'device_id': new['device_id'], 'expected_revision': 0}
    assert c.put('/v1/shelters/shelter-a/receiver', headers=auth(env, 'test-dispatcher-a'), json=command).status_code == 409
    command['expected_revision'] = 1
    assert c.put('/v1/shelters/shelter-a/receiver', headers=auth(env, 'test-dispatcher-a'), json=command).json()['revision'] == 2
    r = c.post('/v1/relay/requests', headers=auth(env, 'test-dispatcher-a'), json=signed(origin, signer, payload))
    assert r.status_code == 403 and r.json()['error']['code'] == 'wrong_receiving_device'


def test_current_sender_membership_is_required_at_ingestion(env):
    origin, signer, _, payload = prepare(env)
    env['settings'].memberships['test-requester-a'].shelter_ids = []
    r = env['client'].post('/v1/relay/requests', headers=auth(env, 'test-dispatcher-a'), json=signed(origin, signer, payload))
    assert r.status_code == 403 and r.json()['error']['code'] == 'shelter_forbidden'


def test_registration_limit_is_durable_and_replays_do_not_consume_slots(env):
    c = env['client']; public = None
    for _ in range(8):public, _ = enroll(env, 'test-requester-a')
    assert c.post('/v1/devices', headers=auth(env), json=public).status_code == 200
    new, _ = device();r = c.post('/v1/devices', headers=auth(env), json=new)
    assert r.status_code == 429 and r.json()['error']['code'] == 'device_limit'
