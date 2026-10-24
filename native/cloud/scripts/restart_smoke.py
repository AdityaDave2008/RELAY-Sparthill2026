"""Real process restart + HTTP replay test. Fixture services only; no AWS calls."""
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import httpx


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runtime-dir', type=Path, required=True)
    p.add_argument('--port', type=int, default=18787)
    args = p.parse_args()
    root = args.runtime_dir.resolve()
    cloud = Path(__file__).resolve().parents[1]
    subprocess.run([sys.executable, str(cloud / 'scripts/bootstrap_local.py'), '--runtime-dir', str(root)], check=True, stdout=subprocess.DEVNULL)
    config = root / 'local-config.json'
    tokens = json.loads((root / 'local-test-tokens.json').read_text())
    process_env = {**os.environ, 'PYTHONPATH': str(cloud)}
    command = [sys.executable, '-m', 'relay_backend', 'serve', '--config', str(config), '--port', str(args.port)]
    base = f'http://127.0.0.1:{args.port}'
    client = httpx.Client(base_url=base, timeout=10, headers={'Authorization': 'Bearer ' + tokens['test-requester-a']})
    processes = []
    def start():
        process = subprocess.Popen(command, env=process_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        processes.append(process)
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError('Backend process exited during restart test')
            try:
                if client.get('/v1/health').status_code == 200:
                    return process
            except httpx.TransportError:
                pass
            time.sleep(.1)
        raise RuntimeError('Backend startup timed out')
    def stop(process):
        process.terminate()
        process.wait(timeout=10)
    try:
        first = start()
        now = datetime.now(timezone.utc)
        body = {'schema_version': 1, 'operation_id': str(uuid4()), 'request_id': str(uuid4()),
                'incident_id': 'synthetic-demo-01', 'destination_shelter_id': 'shelter-a',
                'origin_device_id': str(uuid4()), 'original_text': 'Shelter A needs 20 water packs.',
                'input_mode': 'text', 'created_at': now.isoformat(),
                'expires_at': (now + timedelta(hours=1)).isoformat(), 'revision': 1}
        response = client.post('/v1/requests', json=body)
        assert response.status_code == 201 and response.json()['analysis_state'] == 'pending'
        # Deliberately discard acceptance and stop the API before any worker exists.
        del response
        stop(first)
        second = start()
        replay = client.post('/v1/requests', json=body)
        assert replay.status_code == 200 and replay.json()['analysis_state'] == 'pending'
        subprocess.run([sys.executable, '-m', 'relay_backend', 'worker', '--config', str(config), '--once'], env=process_env, check=True)
        result = client.get('/v1/requests/' + body['request_id']).json()
        assert result['analysis_state'] == 'ready_for_review'
        assert result['analysis_attempts'] == 1
        assert len(client.get('/v1/requests').json()['items']) == 1
        evidence = {'status': 'PASS', 'mode': 'local-test', 'storage': 'sqlite',
                    'finished_at': datetime.now(timezone.utc).isoformat(), 'request_id': body['request_id'],
                    'api_restart_replay': 'PASS', 'separate_worker_process_recovery': 'PASS',
                    'logical_request_count': 1, 'analysis_attempts': 1, 'real_aws': 'NOT TESTED'}
        (root / 'restart-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print(json.dumps(evidence, indent=2))
        stop(second)
    finally:
        client.close()
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)


if __name__ == '__main__':
    main()
