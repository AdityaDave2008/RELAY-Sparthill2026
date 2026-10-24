"""Export the versioned API contract without creating a service or calling AWS."""
import json
from pathlib import Path

import yaml

from relay_backend.api import create_app
from relay_backend.config import Settings

root = Path(__file__).resolve().parents[1]
settings = Settings(mode='aws', storage='dynamodb', runtime_dir=Path('/tmp/relay-contract-unused'),
                    issuer='https://cognito-idp.us-east-1.amazonaws.com/us-east-1_f7wyKUgiY',
                    client_id='DEPLOYED_PUBLIC_CLIENT_ID', memberships={}, shelters=[])
contract = create_app(settings, service=object()).openapi()
contract['info']['description'] += ' See docs/INTEGRATION_HANDOFF.md for idempotency, PKCE, review and retry semantics.'
fixture = {'schema_version': 1, 'operation_id': 'a0000000-0000-4000-8000-000000000001',
           'request_id': 'b0000000-0000-4000-8000-000000000001', 'incident_id': 'synthetic-demo-01',
           'destination_shelter_id': 'shelter-a', 'origin_device_id': 'c0000000-0000-4000-8000-000000000001',
           'original_text': 'Shelter A needs 20 water packs.', 'input_mode': 'text',
           'created_at': '2026-10-24T04:00:00Z', 'expires_at': '2026-10-25T04:00:00Z', 'revision': 1}
contract['components']['schemas']['RequestSubmission']['examples'] = [fixture]
contract['components']['schemas']['ErrorResponse']['examples'] = [{'error': {'code': 'idempotency_conflict',
    'message': 'An identifier was already used with different immutable content', 'retryable': False}}]
proposal = {'status': 'ready_for_review', 'proposal': {'item_id': 'water_packs', 'quantity': 20, 'unit': 'pack',
            'shelter_id': 'shelter-a', 'negated': False, 'missing_fields': [], 'summary': 'Shelter A requests 20 water packs.'},
            'review_reasons': [], 'allocation_authorized': False}
contract['components']['schemas']['ValidatedResult']['examples'] = [proposal]
contract['paths']['/v1/requests']['post']['responses']['200']['content'] = {
    'application/json': {'schema': {'$ref': '#/components/schemas/RequestResult'}}}
(root / 'openapi/relay-v1.json').write_text(json.dumps(contract, indent=2) + '\n')
(root / 'openapi/relay-v1.yaml').write_text(yaml.safe_dump(contract, sort_keys=False))
(root / 'fixtures/typed-request.json').write_text(json.dumps(fixture, indent=2) + '\n')
(root / 'fixtures/validated-proposal.json').write_text(json.dumps(proposal, indent=2) + '\n')
(root / 'fixtures/semantic-cases.json').write_text(json.dumps([
 {'text': 'Shelter A needs 20 water packs.', 'expected': 'ready_for_review'},
 {'text': 'Shelter A needs water packs.', 'expected': 'needs_review'},
 {'text': 'Do not send 20 water packs to Shelter A.', 'expected': 'needs_review'},
 {'text': 'Shelter B needs 20 water packs.', 'expected': 'needs_review'}], indent=2) + '\n')
print('Exported contract and synthetic fixtures; no AWS calls.')
