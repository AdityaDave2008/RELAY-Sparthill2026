#!/usr/bin/env python3
"""Swift CryptoKit → Python gateway compatibility; fixture auth/transport only."""
import argparse
import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path

from fastapi.testclient import TestClient
from relay_backend.api import build_service, create_app
from relay_backend.config import Settings


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    spec=importlib.util.spec_from_file_location('bootstrap',root/'cloud/scripts/bootstrap_local.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='relay-native-gateway-') as tmp:
        folder=Path(tmp);fixture=folder/'public-fixture.json'
        subprocess.run([str(root/'.build/debug/RelayNearbyCheck'),'--fixture',str(fixture)],check=True,capture_output=True)
        value=json.loads(fixture.read_text());config,tokens=module.bootstrap(folder/'runtime')
        client=TestClient(create_app(Settings.load(config)));tokens=json.loads(tokens.read_text())
        def auth(name):return {'Authorization':'Bearer '+tokens[name]}
        for field,role in [('sender','test-requester-a'),('receiver','test-dispatcher-a')]:
            response=client.post('/v1/devices',headers=auth(role),json=value[field]);assert response.status_code==200,response.text
        response=client.put('/v1/shelters/shelter-a/receiver',headers=auth('test-dispatcher-a'),json={'device_id':value['receiver']['device_id'],'expected_revision':0})
        assert response.status_code==200,response.text
        response=client.post('/v1/relay/requests',headers=auth('test-dispatcher-a'),json=value['signed'])
        assert response.status_code==201,response.text
        response=client.post('/v1/requests',headers=auth('test-requester-a'),json=value['submission'])
        assert response.status_code==200,response.text
        identifier=value['submission']['request_id']
        assert client.get('/v1/requests/'+identifier,headers=auth('test-requester-a')).status_code==200
        assert client.get('/v1/requests/'+identifier,headers=auth('test-requester-b')).status_code==404
        evidence={'status':'PASS','request_id':identifier,'scope':'Native CryptoKit signature/encryption with Python fixture-auth API; not physical wireless or live AWS verification','gateway_ingestion':'PASS','direct_upload_dedup':'PASS','original_owner_preserved':'PASS','foreign_account_read_denied':'PASS'}
        Path(args.output).write_text(json.dumps(evidence,indent=2));print(json.dumps(evidence,indent=2))


if __name__=='__main__':main()
