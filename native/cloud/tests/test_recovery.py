import concurrent.futures
import time
from uuid import uuid4

from conftest import auth
from test_backend import allocation, submission, wav_bytes
from relay_backend.providers import ProviderError
from relay_backend.service import PREFIX, Worker, key


def test_parallel_replays_preserve_one_logical_record(env):
    body = submission()
    def send(_):
        return env['client'].post('/v1/requests', json=body, headers=auth(env)).status_code
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        codes = list(pool.map(send, range(16)))
    assert codes.count(201) == 1 and set(codes) == {200, 201}
    assert len(env['service'].store.query(PREFIX + 'USER#test-requester-a')[0]) == 1
    assert env['service'].store.get(PREFIX + 'BUDGET', 'requests')[0]['count'] == 1


def test_failure_remains_durable_and_explicit_retry_is_bounded(env):
    s, c = env['service'], env['client']
    s.providers.error = ProviderError('AccessDeniedException', False)
    body = submission()
    path = '/v1/requests/' + body['request_id']
    c.post('/v1/requests', json=body, headers=auth(env))
    assert Worker(s).run_once()
    failed = c.get(path, headers=auth(env)).json()
    assert failed['cloud_state'] == 'accepted' and failed['analysis_state'] == 'failed'
    op = {'operation_id': str(uuid4())}
    assert c.post(path + '/retry-analysis', json=op, headers=auth(env, 'test-requester-b')).status_code == 404
    assert c.post(path + '/retry-analysis', json=op, headers=auth(env)).status_code == 202
    assert c.post(path + '/retry-analysis', json=op, headers=auth(env)).status_code == 202
    Worker(s).run_once()
    assert c.post(path + '/retry-analysis', json={'operation_id': str(uuid4())}, headers=auth(env)).status_code == 202
    Worker(s).run_once()
    assert c.post(path + '/retry-analysis', json={'operation_id': str(uuid4())}, headers=auth(env)).status_code == 409
    assert s.providers.calls == 3


def test_crash_reclaims_cannot_repeat_paid_calls_forever(env):
    s, c = env['service'], env['client']
    clock = [time.time()]
    s.clock = lambda: clock[0]
    invocations = []
    def crash(*args):
        invocations.append(True)
        raise RuntimeError('Simulated process fault after invocation')
    s.providers.analyze = crash
    body = submission()
    c.post('/v1/requests', json=body, headers=auth(env))
    import pytest
    for _ in range(3):
        with pytest.raises(RuntimeError):
            Worker(s).run_once()
        clock[0] += 121
    assert Worker(s).run_once()
    r = c.get('/v1/requests/' + body['request_id'], headers=auth(env)).json()
    assert len(invocations) == 3 and r['analysis_state'] == 'failed'
    assert r['error']['code'] == 'analysis_attempt_limit'


def test_upload_expiry_renewal_checksum_and_terminal_job_failure(env):
    s, c = env['service'], env['client']
    clock = [time.time()]
    s.clock = lambda: clock[0]
    data = wav_bytes()
    body = allocation(data)
    identifier = body['transcription_id']
    path = '/v1/transcriptions/' + identifier
    assert c.post('/v1/transcriptions', json=body, headers=auth(env)).status_code == 201
    clock[0] += 301
    assert c.get(path, headers=auth(env)).json()['status'] == 'upload_expired'
    assert c.put('/v1/local-uploads/' + identifier, content=data, headers=auth(env)).status_code == 409
    assert c.post('/v1/transcriptions', json=body, headers=auth(env)).status_code == 201
    corrupted = data[:-1] + bytes([data[-1] ^ 1])
    c.put('/v1/local-uploads/' + identifier, content=corrupted, headers=auth(env))
    op = {'operation_id': str(uuid4())}
    assert c.post(path + '/start', json=op, headers=auth(env)).json()['error']['code'] == 'audio_checksum_mismatch'
    c.put('/v1/local-uploads/' + identifier, content=data, headers=auth(env))
    assert c.post(path + '/start', json=op, headers=auth(env)).status_code == 202
    def failed(record):
        raise ProviderError('transcription_service_failed')
    s.providers.poll_transcription = failed
    Worker(s).run_once()
    result = c.get(path, headers=auth(env)).json()
    assert result['status'] == 'failed' and not result['error']['retryable']
    assert c.post(path + '/start', json=op, headers=auth(env)).status_code == 409


def test_bounded_resource_counter_does_not_break_replay(env):
    env['settings'].max_requests = 1
    c = env['client']
    body = submission()
    assert c.post('/v1/requests', json=body, headers=auth(env)).status_code == 201
    assert c.post('/v1/requests', json=submission(), headers=auth(env)).status_code == 429
    assert c.post('/v1/requests', json=body, headers=auth(env)).status_code == 200
