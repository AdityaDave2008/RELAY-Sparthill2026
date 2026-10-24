"""Independent HTTP restart test using real Cognito, DynamoDB and Bedrock.
Stop other workers for this isolated namespace before running. No AWS resources
are provisioned here; exactly one new request and one worker cycle are used.
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import httpx


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--tokens', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--port', type=int, default=18788)
    p.add_argument('--allow-chargeable-aws', action='store_true')
    args = p.parse_args()
    if not args.allow_chargeable_aws:
        raise SystemExit('Obtain approval and provide --allow-chargeable-aws.')
    cfg = json.loads(args.config.read_text())
    if cfg.get('mode') != 'aws' or cfg.get('storage') != 'dynamodb':
        raise SystemExit('This test requires the real AWS configuration.')
    with socket.socket() as check:
        check.bind(('127.0.0.1', args.port))
    cloud = Path(__file__).resolve().parents[1]
    tokens = json.loads(args.tokens.read_text())
    process_env = {**os.environ, 'PYTHONPATH': str(cloud)}
    command = [sys.executable, '-m', 'relay_backend', 'serve', '--config', str(args.config), '--port', str(args.port)]
    client = httpx.Client(base_url=f'http://127.0.0.1:{args.port}', timeout=20,
                          headers={'Authorization': 'Bearer ' + tokens['test-requester-a']})
    processes = []
    evidence = {'mode': 'aws', 'storage': 'dynamodb', 'started_at': datetime.now(timezone.utc).isoformat()}
    def start():
        process = subprocess.Popen(command, env=process_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        processes.append(process)
        for _ in range(150):
            if process.poll() is not None:
                raise RuntimeError('API process failed to start')
            try:
                r = client.get('/v1/health')
                if r.status_code == 200 and r.json()['mode'] == 'aws':
                    return process
            except httpx.TransportError:
                pass
            time.sleep(.1)
        raise RuntimeError('API startup timed out')
    try:
        first = start()
        now = datetime.now(timezone.utc)
        body = {'schema_version': 1, 'operation_id': str(uuid4()), 'request_id': str(uuid4()),
                'incident_id': 'synthetic-demo-01', 'destination_shelter_id': 'shelter-a',
                'origin_device_id': str(uuid4()), 'original_text': 'Shelter A needs 7 blankets.',
                'input_mode': 'text', 'created_at': now.isoformat(), 'expires_at': (now + timedelta(hours=1)).isoformat(), 'revision': 1}
        response = client.post('/v1/requests', json=body)
        assert response.status_code == 201 and response.json()['analysis_state'] == 'pending', 'Stop other workers before this test'
        evidence['request_id'] = body['request_id']
        del response  # Simulate the caller not retaining the acceptance receipt.
        first.kill()
        first.wait(timeout=10)
        start()
        replay = client.post('/v1/requests', json=body)
        assert replay.status_code == 200 and replay.json()['analysis_state'] == 'pending'
        subprocess.run([sys.executable, '-m', 'relay_backend', 'worker', '--config', str(args.config), '--once'],
                       env=process_env, timeout=90, check=True)
        result = client.get('/v1/requests/' + body['request_id']).json()
        assert result['analysis_state'] == 'ready_for_review'
        assert result['result']['proposal']['quantity'] == 7 and result['result']['proposal']['item_id'] == 'blankets'
        assert result['provider_evidence']['provider'] == 'aws' and result['provider_evidence']['request_id']
        assert result['analysis_attempts'] == 1
        assert client.post('/v1/requests', json=body).status_code == 200
        listed = client.get('/v1/requests?limit=50').json()['items']
        assert sum(x['request_id'] == body['request_id'] for x in listed) == 1
        evidence.update(status='PASS', api_process_crash_replay='PASS', separate_worker_recovery='PASS',
                        logical_request_count=1, result=result)
    except Exception as exc:
        evidence.update(status='FAIL', failure=type(exc).__name__ + ': ' + str(exc))
        raise
    finally:
        evidence['finished_at'] = datetime.now(timezone.utc).isoformat()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(evidence, indent=2) + '\n')
        client.close()
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
    print(json.dumps({'status': evidence['status'], 'request_id': evidence['request_id'],
                      'api_process_crash_replay': evidence['api_process_crash_replay'],
                      'separate_worker_recovery': evidence['separate_worker_recovery']}, indent=2))


if __name__ == '__main__':
    main()
