# Backend test results — real AWS verification, 2026-10-24 UTC

**The actual Cognito → S3 → Transcribe → reviewed request → Nova Lite → DynamoDB flow passes through the locally hosted API.** The earlier fixture-only report is superseded by this evidence. The live run was authorized after the user requested actual service testing in response to the bounded $2 proposal. Public hosting and native integration remain unverified.

| Area | Status | Evidence / limits |
|---|---|---|
| Automated backend tests | PASS | 30 pytest cases, 2.78 seconds; includes regression checks from real model failures |
| Local fixture HTTP/restart tests | PASS | Retained earlier evidence; not counted as AWS proof |
| Real Cognito authentication | PASS | Four synthetic users; TOTP setup and repeated SOFTWARE_TOKEN_MFA sign-in; authenticated API access |
| Access isolation / idempotency | PASS | Actual HTTP requests with real Cognito tokens; wrong-owner/wrong-shelter/requester privilege denials, identical replay and changed-content conflict |
| Real Bedrock | PASS | On-demand Converse with amazon.nova-lite-v1:0; actual outputs and usage recorded |
| Real Transcribe | PASS | One real batch job completed; raw transcript independently matched private S3 output |
| Private S3 upload/sealing | PASS | Presigned POST worked; three owned objects verified AES256 and expected-account ownership; sealed SHA-256 matched |
| Durable DynamoDB | PASS | Accepted requests/results persisted; six selected results matched independent strongly consistent SDK reads; all 12 test requests enumerated in the owned inbox |
| AWS process crash/restart | PASS | API killed after commit, restarted, unchanged replay returned existing request; separate worker recovered one logical request and one model analysis |
| API reachability on this Mac | PASS | http://127.0.0.1:8787; mode aws, storage dynamodb; `/` opens `/docs` |
| Lambda artifact/template | PASS (build/syntax only) | Linux arm64 packaging and prior AWS ValidateTemplate; no deployment claim |
| Public API / Lambda runtime | NOT TESTED | Dedicated execution role absent, no hosted stack or public tunnel |
| Native PKCE browser flow | NOT TESTED | Public client/domain/code flow configured; scripted password + TOTP was tested |
| Native app / physical iPhones / offline gateway | NOT TESTED | No Swift/signing/transport changes; this endpoint is loopback-only |
| Noisy human-speech accuracy | NOT TESTED | Short synthetic/TTS recording; a shelter-name transcription error occurred |

## Actual sample flow and results

Audio: 62,464-byte mono PCM16 WAV, 16 kHz, 1.824 seconds, generated locally with macOS speech. SHA-256 `9d5ceb99bb4ab2f3375cf0d2bdcf3286f42fa1155bc3c87bcf3b94475b6f2271`.

Spoken: **“Shelter A needs two water packs.”**

Actual Transcribe output: **“Sheltering needs 2 water packs.”**

The initial independent client submitted the returned text through the same request API and received a quantity-2 water-pack proposal. The agent then explicitly reviewed the known sample, corrected the shelter name to **“Shelter A needs 2 water packs.”**, and submitted a separate synthetic reviewed request. Its model result was item `water_packs`, quantity `2`, unit `pack`, shelter `shelter-a`, negated `false`, no missing fields, and `ready_for_review`. It is durably accepted, with `allocation_authorized: false`; nothing was allocated or fulfilled. This was an agent-reviewed test, not a native human review UI.

The full HTTP smoke ran **2026-10-24T05:36:49.128804+00:00 → 2026-10-24T05:37:14.548931+00:00**. The corrected reviewed result completed **2026-10-24T05:38:35.863525+00:00**.

| Model input | Result | Bedrock request ID | Input / output tokens |
|---|---|---|---|
| SYNTHETIC: Shelter A needs 20 water packs. | ready_for_review | `REDACTED-ID-7c84489d73bf` | 491 / 50 |
| Shelter A needs water packs. | needs_review | `REDACTED-ID-d72b39abe4ca` | 484 / 55 |
| Do not send 20 water packs to Shelter A. | needs_review | `REDACTED-ID-ad68aa3030c1` | 489 / 53 |
| Sheltering needs 2 water packs. | ready_for_review | `REDACTED-ID-b4492e943b7f` | 486 / 47 |
| Shelter A needs 2 water packs. | ready_for_review | `REDACTED-ID-3cf9478856b9` | 486 / 48 |
| Shelter A needs 7 blankets. | ready_for_review | `REDACTED-ID-cf5a8948bdc0` | 485 / 45 |

Model: `amazon.nova-lite-v1:0`, region `us-east-1`, Converse API, temperature 0, maximum 512 output tokens. A system instruction and explicit flat output contract were tested; native JSON-schema enforcement is **not** used or assumed.

Transcription UUID: `REDACTED-ID-bae40cd8379c`. Job: `relay-mvp-REDACTED-ID-bae40cd8379c`. Start request ID: `REDACTED-ID-f1a9b5b208bf`; completed poll request ID: `REDACTED-ID-0ccd99475f3f`. Provider status COMPLETED was independently confirmed. Only the known owned S3 output key was read; arbitrary provider-returned URLs were not fetched.

Corrected request UUID: `REDACTED-ID-17d6b0083baf`. Restart request UUID: `REDACTED-ID-0659055efa73`. The restart test completed `2026-10-24T05:39:08.083402+00:00` and observed exactly one logical request and one model attempt. Direct storage verification completed at `2026-10-24T05:40:38.643950+00:00` with the work queue empty.

## Live defects found and handling

Initial real responses used Markdown fences or echoed the input envelope. The original strict parser rejected them and retained durable acceptance with needs_review. System instructions were revised to separate input data from the flat output contract; ordinary requests then returned valid JSON.

Nova Lite also invented quantity 1 for text with no quantity. The backend caught quantity_not_grounded. Validation was strengthened to clear invented quantity values and explicitly mark missing quantity from the source text. Missing quantity and negation now remain explicit even when the model emits malformed JSON. One missing-quantity response still ended with an extra `]`; it correctly produced needs_review with invalid_model_output and missing_quantity. This remains a model reliability limitation, not silently repaired or described as valid extraction. The final end-to-end test passes because the required safe review state is reached.

The real transcript misheard “Shelter A” as “Sheltering.” The explicit review/edit step corrected it. Do not infer ASR accuracy from plumbing success. Typed requests remain independent of speech.

MFA verification found that registering/verifying a software token did not populate the user's enabled-MFA list until preference activation. Provisioning now explicitly enables/prefers TOTP only for the four new synthetic users. Each was then signed in again with an actual SOFTWARE_TOKEN_MFA challenge. The original pool still requires MFA; original users, client and dispatcher group were not changed.

Earlier local-only issues (sentence-ending number parsing and concurrent SQLite initialization) remain fixed. One Starlette TestClient deprecation warning persists; tests and the separate HTTP client pass.

## Authentication, resources and usage

Account `928489693154`, region `us-east-1`. Pre-write STS request ID `REDACTED-ID-375d0ce6748a`; ownership/schema/MFA checks passed and the reserved MVP namespaces were empty before writes. Public app client `dfulb5lau8283nlgil7ddu36i`, domain `relay-mvp-928489693154.auth.us-east-1.amazoncognito.com` ACTIVE. Authentication verification timestamp `2026-10-24T05:43:16.476975+00:00`. Requester-A repeat MFA auth request ID `REDACTED-ID-4eb27bc982e8`. No client secret, bearer token, password, TOTP seed or AWS credentials are in committed evidence.

Usage observed: **12 accepted synthetic requests, 16 real model calls including 4 diagnostic calls, 6,948 input tokens, 1,181 output tokens, one transcription job.** This includes failed formatting diagnostics. Actual billed charges/credits are not reconciled; see COST_AND_CLEANUP.md and RESOURCE_MANIFEST.json. The run remains within the proposed 30-request/five-recording scope; no hosted services, TTS API, custom ASR or training were created.

## Remaining hosting gate

`relay-cloud-mvp-execution` does not exist: IAM returned `NoSuchEntity` at `2026-10-24T05:37:38.946882+00:00`, request ID `REDACTED-ID-9b2e49bfafd3`. The participant role is not a suitable Lambda execution role; its trust was not weakened. No Lambda/API Gateway deployment was attempted. Obtain the organizer role/scoped PassRole, approve hosting scope, deploy, rerun the external endpoint tests, then integrate and test native PKCE and physical iPhones.

## Reproduction / evidence

- `scripts/smoke_client.py` against the real API with the private Cognito token file, the committed synthetic WAV and `--allow-chargeable-aws`.
- `scripts/aws_restart_smoke.py` with the private AWS config/tokens and the explicit paid-test flag; stop other workers first. It creates one new synthetic request, kills only its own API process, replays unchanged and starts a separate worker.
- `scripts/verify_live_storage.py` performs independent read-only AWS checks of the smoke/review/restart records and known owned S3/job objects.
- `evidence/aws-live-http-smoke.json`, `aws-live-reviewed-audio.json`, `aws-live-restart.json`, `aws-live-storage.json`, `aws-live-authentication.json` and `aws-live-usage.json` contain safe actual results and request IDs.
- Earlier failure/diagnostic evidence is retained as `aws-*-diagnostic*.json` and `aws-*-format-failure.json`; it is not presented as final success.

All implementation/evidence changes are under cloud/**. The mobile checkout and original untracked reports remain preserved.

## 2026-10-24 — pre-send preview and inventory source validation

Source based on native integration `8c207e736d269b02d52d888b8de12ac360ed1db7`, isolated branch `feature/cloud-inventory-preview`; changes confined to cloud/**. **60 fixture tests PASS**, including the prior suite and new pre-send, location and inventory cases. Timestamp/output are recorded in `evidence/preview-inventory-fixture-tests.json` and `.txt`.

Verified durable preview acceptance/replay with no request inbox side effect; completed-transcription ownership; bounded transient/crash retry; reuse of one analysis budget slot on explicit Send; concurrent preview-consumption protection; backward immutable request digests and committed event replay; strict coordinates/unit/count validation and omission of structured location from model prompts.

Inventory checks cover authorization, stock revisions, underflow, independent-connection overbooking races, atomic reserve/fulfill/release, requester cancellation, cancellation racing fulfillment, recovery after a lost response and restart, three immutable ledger changes for stock/reserve/fulfill, and preventing old progress endpoints from bypassing fulfillment. A full ordinary reply history cannot trap reserved stock. Reported ledger fulfillment remains distinct from physical delivery.

No new AWS calls, paid inference, transcription jobs, shared-runtime changes or deployment were performed for this implementation. The last separately verified live counts were 17/30 slots and 3/5 recordings. Native physical UI and the new live AWS inventory flow are not established by fixture tests. There is one existing Starlette TestClient deprecation warning. The native task will inspect/cherry-pick, rerun the suite, then coordinate retirement of stale API/worker processes before bounded live validation; the older cfcaade deployment ZIP must not be used for this source.

### Subsequent coordinated live validation — 08:12 UTC

Native integrated the backend as fe7b88d, reran 60 backend/49 Swift tests, exercised the complete fixture HTTP flow, then replaced the old API/AWS worker with the integrated source. Public health/new-route checks passed and the old 8787 listener was absent. Native ran one real preview with password/MFA/refresh authentication, reused the existing owned transcription, explicitly sent the request with location/structured fields, and reserved/fulfilled synthetic stock with same-operation replays.

Independent strongly consistent AWS readback at 2026-10-24T08:12:06.162379Z confirmed preview `REDACTED-ID-ac62a5abca09` bound to request `REDACTED-ID-d4dddd0f1bf6`, one Nova Lite analysis attempt and identical saved provider evidence on the request. Stock ledger: seed20 → reserve2 → fulfill2 → restore2; final on_hand20/reserved0/available20, revision4. History has two unique events, ledger allocation verified and physical delivery unverified. Counters18/30 analysis slots and3/5 recordings; queue empty. No new calls or mutations were added by the independent audit. Evidence files: `preview-inventory-live-readback.json`, `preview-inventory-native-cli.json`, `preview-inventory-runtime-readonly.json`, `preview-inventory-source.json`.

This is public-HTTPS Swift CLI and AWS persistence evidence. The native task's separate Mac UI and phone tests are not inferred from it. Managed Lambda/API Gateway hosting remains blocked; no IAM or MFA settings were changed.
