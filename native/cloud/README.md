# RELAY cloud MVP

A runnable, separately authenticated backend for immutable resource requests and reviewed short recordings. **Pre-send previews, optional request location/structured fields, and coordinator inventory reservations/fulfillment now pass the real public-HTTPS Swift HTTP workflow, with independent AWS result/ledger readback. Sixty backend fixture tests also pass.** See [the current deployment handoff](docs/CLOUD_DEPLOYMENT_HANDOFF.md) and [exact API contract](docs/PREVIEW_INVENTORY_CONTRACT.md). The native task owns app integration and separate native UI verification.

The API durably commits work before acknowledging acceptance. A worker proposes structured fields through Bedrock and validates them in code. Pre-send previews stay out of inboxes; explicit Send binds a matching preview to one request without a second model call. Models cannot allocate inventory. Authorized coordinators reserve/fulfill/release stock through atomic, idempotent transactions; cancellation releases reserved stock. Ledger fulfillment records a human action and does not prove physical delivery. Recorded speech is a separate owned upload/job and still requires explicit review.

Build-9 evidence established Cognito MFA, S3, Transcribe, Nova Lite and DynamoDB through the authorized temporary HTTPS tunnel. Build-10 evidence additionally verifies one real pre-send preview reused on Send, synthetic location persistence, and atomic inventory reservation/fulfillment/replay; the existing completed transcription was reused without another ASR job. Managed Lambda/API Gateway hosting remains blocked by the missing dedicated role/PassRole; prior prepared ZIPs are stale for this feature.

## Run without AWS or charges

From the repository root, using Python 3.13:

```sh
python3.13 -m venv cloud/.venv
cloud/.venv/bin/python -m pip install -r cloud/requirements.lock
cloud/.venv/bin/python cloud/scripts/bootstrap_local.py --runtime-dir /tmp/relay-local-demo
PYTHONPATH=cloud cloud/.venv/bin/python -m relay_backend serve --config /tmp/relay-local-demo/local-config.json
```

In a second terminal:

```sh
PYTHONPATH=cloud cloud/.venv/bin/python -m relay_backend worker --config /tmp/relay-local-demo/local-config.json
```

API: `http://127.0.0.1:8787`, interactive contract: `/docs`. Opening the local base address redirects to `/docs`. Fixture mode deliberately refuses non-loopback binding. Tokens are generated privately for four synthetic actors and expire in one hour. Re-run bootstrap to refresh them; it preserves the database/key. Use a new runtime directory for a clean demo. Do not put runtime directories in Git.

```sh
cloud/.venv/bin/python -m pytest cloud/tests -q
cloud/.venv/bin/python cloud/scripts/smoke_client.py --base-url http://127.0.0.1:8787 --tokens /tmp/relay-local-demo/local-test-tokens.json --audio cloud/fixtures/synthetic-speech.wav --output /tmp/relay-local-http.json
cloud/.venv/bin/python cloud/scripts/restart_smoke.py --runtime-dir /tmp/relay-restart-demo
```

The committed WAV is locally generated synthetic/TTS speech; its format and checksum are recorded beside it. Supply your own compatible WAV with `--audio`, or omit that option to test text alone. Fixture transcription is a fixed sentence and is not an ASR accuracy test. `restart_smoke.py` needs a fresh directory and free port 18787. Refresh dates and UUIDs before sending the static typed-request example.

## Use real AWS locally, after the test proposal is approved

1. Read `docs/AWS_TEST_PROPOSAL.md`. The recorded live run was authorized within its `$2` limit; additional runs must remain within that same approval and the remaining resource counters. Do not infer spending approval from an AWS login.
2. Use the official AWS CLI v2 browser login with profile `relay-workshop`, region `us-east-1`, and private task-specific config/cache paths. Boto3 requires its `crt` extra for this login. `configure_workshop.py` is an alternative for organizer-issued temporary credentials entered privately. Never extract browser tokens.
3. Run `scripts/audit_session.py` using that session to recheck identity/ownership. Existing resources must match account 928489693154 and the documented schema/policies.
4. Preview `provision_demo_auth.py --runtime-dir /private/runtime`. Only after approval, append `--apply-approved-scope`. It creates a new secretless client/domain and four synthetic users, enrolls TOTP MFA, and saves credentials/tokens only in that directory. It aborts on unexplained existing same-name resources. It does not weaken MFA or send invitations.
5. Start the same API and worker with the generated `aws-config.json`. Stop the fixture service first or select a different port. Keep the API bound to loopback until a separately approved hosting plan is ready.
6. Run smoke_client with `aws-test-tokens.json`, a synthetic WAV, and `--allow-chargeable-aws`. This explicitly permits the script to submit chargeable work; the operator must already have obtained approval. Preserve its safe evidence JSON.

The API checks STS account identity at startup. The server holds the AWS session; the native client only uses a short-lived Cognito access token and one-object S3 upload grants. A temporary session expiring requires operator reauthentication, not app credential changes. No arbitrary bucket paths or user/role assertions are accepted.

## Hosted deployment — prepared, not deployed

`infra/template.yaml` uses the existing data resources and an organizer-created dedicated execution role. Read `docs/ORGANIZER_REQUEST.md` and `docs/DEPLOYMENT.md`. Never reuse WSParticipantRole as a Lambda execution role. The template contains no IAM resources and does not modify existing table streams, bucket policies or pool settings.

Contract and examples: `openapi/relay-v1.yaml`, `fixtures/`, `docs/INTEGRATION_HANDOFF.md`. Re-export after API changes with:

```sh
PYTHONPATH=cloud cloud/.venv/bin/python cloud/scripts/export_contract.py
```

Live evidence and the exact sample transcript/model output are in `docs/LIVE_AWS_DEMO.md`. The running service on this Mac currently uses real AWS; the fixture commands above remain available for offline contract testing.
