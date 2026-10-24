# CLOUD_DEPLOYMENT_HANDOFF — RELAY build 10

Updated **2026-10-24T08:12:06.162379Z**. **The temporary HTTPS API has passed a real pre-send AI preview → explicit Send → coordinator inventory reservation → fulfillment flow. Managed Lambda/API Gateway hosting remains blocked.** These are separate facts.

## Endpoint, account and source

| Setting | Verified value |
|---|---|
| Current demo API base | https://resumes-investigated-striking-mba.trycloudflare.com |
| Hosting | Authorized Cloudflare quick tunnel → Mac loopback API 127.0.0.1:8788; real AWS data/AI services |
| AWS account / region | 928489693154 / us-east-1; STS verified 08:12 UTC, request `REDACTED-ID-8b3547721ec5` |
| Participant identity | WSParticipantRole/Participant, verified during the deployment audit |
| Backend feature commit | `62dcf9035bc0bf02054debe53b08a478e4bf379e` on feature/cloud-inventory-preview |
| Native integrated backend commit | `fe7b88dad016c43066a6f272f2a0f6ae94855667` on feature/cloud-integration |
| Source comparison | PASS — all 14 backend modules match the integrated checkout on disk; no in-memory source attestation endpoint exists |
| Managed AWS API base / deployed Lambda source revision | None: no managed API/functions exist in the latest hosting inventory |

At **08:11:32 UTC**, public health returned aws/dynamodb and the public OpenAPI exposed the new interpretation/inventory routes. The old 8787 API listener was absent; new API PID 54243 and AWS worker PID 54245 were running. PID 53866 was an isolated fixture worker, not a second AWS consumer. The native task coordinated replacement of the old API/worker; this AWS audit did not restart anything. At **08:12:06 UTC**, the durable work queue was empty and the real preview/result had completed.

The quick-tunnel hostname is temporary and can change on restart. Availability depends on the Mac, tunnel, API, worker and valid AWS session. It is not a Lambda deployment.

## Timestamped live workflow results

The native task supplied `relay-build10-live-flow.json` after running its Swift HTTP client against the public HTTPS API. This task independently performed strongly consistent AWS reads during **08:12:04–08:12:06 UTC**. No new request, model call, audio job or data mutation was added by this audit.

| Check | Result / safe correlation |
|---|---|
| Swift Cognito password + software MFA + refresh for requester/dispatcher | PASS — native test evidence; no credential values copied |
| Authorized profile/shelter directory and missing/invalid-token rejection | PASS — prior public HTTPS checks, with valid-user shelter isolation at 07:34 UTC |
| Pre-send Bedrock preview | PASS — interpretation `REDACTED-ID-ac62a5abca09`, ready_for_review, one analysis attempt |
| Real Bedrock result | PASS — Nova Lite `amazon.nova-lite-v1:0`, AWS request `REDACTED-ID-314acf1b5971`, 486 input / 48 output tokens |
| Explicit Send reuses preview | PASS — request `REDACTED-ID-d4dddd0f1bf6`; exact preview binding, same stored provider result, no second analysis slot |
| Location and edited structured fields | PASS — persisted in the request; coordinate values omitted from this evidence |
| Reviewed transcript reference | PASS — reused owned transcription `REDACTED-ID-81f7b3f5d045`; no new live ASR job |
| Request/repeated reserve/repeated fulfillment | PASS — native replay checks plus independent unique ledger/history records |
| Coordinator reserve | PASS — 20 on hand, 2 reserved, 18 available; operation `REDACTED-ID-fd467b5bdc71` |
| Coordinator fulfill | PASS — 18 on hand, 0 reserved; operation `REDACTED-ID-b1ab3d67c2cb` |
| Synthetic stock restore | PASS — final 20 on hand, 0 reserved, 20 available, inventory revision 4; operation `REDACTED-ID-bff568117e7c` |
| Request history | PASS — revision 2, exactly two unique accepted/completed events |
| Shared counters | PASS — 18/30 request/preview analysis slots and 3/5 recordings at 08:12 UTC |
| Worker recovery state | PASS — queue empty; stored completed result/reservation/history |

Stock was explicitly seeded with 20 **synthetic demo** water packs, reserved/fulfilled by the coordinator test, then the two consumed demo units were restored. This is a durable inventory ledger, not a sensor reading or real resource delivery. History has resource_allocation_verified:true and physical_delivery_verified:false. The model proposal still has allocation_authorized:false; the model does not allocate inventory.

The last build-9 public flow separately tested real S3 upload → Transcribe → review → Bedrock. Reusing its completed recording here avoids another ASR charge. The remaining two recording slots were preserved. A preview consumes one shared analysis slot; matched Send binds it to one request without another slot. Abandoned/failed previews also count. These are usage bounds, not a reconciled dollar charge.

Native Mac UI login with password/MFA was subsequently reported successful by the native task. Its full UI preview/send/coordinator test and physical-phone workflow were **pending at this handoff timestamp** and are separate from the CLI evidence above. Do not infer UI, microphone/picker, Keychain recovery or physical wireless success from these HTTP checks.

## Implemented app-facing API

Existing health, profile, authorized shelters, request submission/read/history, and recorded-speech routes remain. The new source adds:

- POST /v1/interpretations and GET /v1/interpretations/{id}: private durable pre-send preview, no inbox/stock effect.
- Optional request interpretation_id, location and structured_fields; exact preview binding avoids duplicate model work. Location is not added to the model prompt.
- GET /v1/inventory?shelter_id= and dispatcher POST /v1/inventory/{shelter_id}/adjust.
- GET/POST /v1/requests/{id}/inventory: coordinator reserve, fulfill, release; owner-readable reservation state.
- Atomic stock/reservation/history/ledger/idempotency updates. Requester cancellation and staff rejection release stock. Older progress calls cannot bypass the new fulfillment route.

Exact schema, role rules, nullable fields, idempotency/error semantics and examples: [PREVIEW_INVENTORY_CONTRACT.md](PREVIEW_INVENTORY_CONTRACT.md). Generated OpenAPI is in cloud/openapi/relay-v1.json and .yaml. Native App/Swift changes remain owned by the native task.

**Fixture verification:** 60 backend tests pass, including independent-connection overbooking, cancellation/fulfillment races, one-preview/two-request races, response loss/restart, backward digests/event replay, audio ownership and location bounds. Native reports 49 Swift tests and its complete fixture HTTP flow passing. These are distinct from live AWS and physical-device evidence.

## Managed hosting: precise remaining blocker

Latest direct managed-hosting inventory: **2026-10-24T07:44:57.246002Z**; no subsequent managed deployment was performed by this task.

| Managed resource / permission | Result |
|---|---|
| relay-cloud-mvp-execution | FAIL — absent, IAM NoSuchEntity; request `REDACTED-ID-adf7e3c2e0d8` |
| Lambda trust / scoped role permissions | NOT TESTED — role does not exist |
| Participant PassRole for dedicated role | FAIL in full 06:41 UTC policy audit — no target-role Allow; recheck after organizer provisioning |
| relay-cloud-mvp stack | FAIL — absent; request `REDACTED-ID-46b0987ac0af` |
| relay-cloud-mvp-api Lambda | FAIL — absent; request `REDACTED-ID-c75213c0e803` |
| relay-cloud-mvp-worker Lambda | FAIL — absent; request `REDACTED-ID-64054bfaa861` |
| HTTP API Gateway inventory | FAIL — zero APIs, no more pages; request `REDACTED-ID-17b4100cc2b5` |
| Deployed Lambda CodeSha256/RevisionId and worker status | UNAVAILABLE — no functions |

At the full policy audit, WSParticipantRole had no inline policies or boundary. ws-default-policy v1 allowed PassRole only on WSParticipantRole itself; PowerUserAccess v12 did not grant the dedicated-role permission. Participant trust had no Lambda service principal. The attempted simulator call was denied for **iam:SimulatePrincipalPolicy** (request `REDACTED-ID-33b45bc411af`), not a successful effective PassRole evaluation.

The organizer must provision `arn:aws:iam::928489693154:role/relay-cloud-mvp-execution` with Lambda trust and reviewed scoped permissions, then grant participant PassRole only on that ARN with iam:PassedToService=lambda.amazonaws.com. Exact proposals remain in cloud/infra/organizer-*.json and cloud/docs/ORGANIZER_REQUEST.md. Do not reuse or weaken participant trust. No IAM/MFA changes were made here.

Ready existing services: private S3 relay-artifacts-928489693154-use1 under cloud-mvp-v1/, DynamoDB relay-messages under RELAY_MVP_V1#, Cognito and Bedrock Nova Lite. The template was previously syntax-validated, but syntax is not deployment evidence. The earlier relay-public stack rolled back after iam:CreateRole denial; its former API t9xj4xi8k4 was deleted and is not usable.

**Exact remaining managed-deployment step:** obtain the scoped organizer role/PassRole, then agree the final integrated source with the native task, build a fresh artifact, and deploy the reviewed stack under the hosting approval. Record actual Lambda hashes/status and API URL, then repeat authenticated endpoint tests. The old cfcaade ZIP is **superseded for build 10** and must not overwrite this new backend. Nothing in this feature run uploaded or deployed a Lambda artifact.

## Cognito configuration and enrolled test access

Configuration was directly verified at 06:41–06:43 UTC; later password/MFA and refresh tests succeeded. Native now supports direct Cognito sign-in; the registered OAuth settings remain available.

| Setting | Value |
|---|---|
| User pool | us-east-1_f7wyKUgiY |
| Native public client ID | dfulb5lau8283nlgil7ddu36i — RELAY-Cloud-MVP-Native, no client secret |
| Issuer | https://cognito-idp.us-east-1.amazonaws.com/us-east-1_f7wyKUgiY |
| Login domain | https://relay-mvp-928489693154.auth.us-east-1.amazoncognito.com |
| Authorization / token paths | /oauth2/authorize / /oauth2/token |
| Callback / logout | relay://oauth/callback / relay://oauth/signout |
| Additional local callback | http://localhost:8400/callback |
| OAuth scopes / flow | openid email; authorization code with native PKCE S256 |
| MFA | ON; software TOTP enabled/preferred for all four synthetic users |
| Self sign-up | Disabled; enrolled accounts only |
| Token lifetime | Access/ID 60 minutes, refresh 1 day; revocation enabled |

Use test-requester-a / test-dispatcher-a for shelter-a, or the corresponding -b actors for shelter-b isolation. On this Mac, the existing owner-only account store is:

```text
/Users/RELAY_DEVELOPER/Documents/Codex/2026-10-23/b/work/relay-runtime/live/demo-identities.private.json
```

Open only the needed actor privately and use its enrolled account and software authenticator in the app. The file is mode 0600 in a mode-0700 directory. Do not reset MFA, paste the record into chat/source/screenshots, or put private test token files into the mobile app. Synthetic .invalid emails cannot receive recovery mail. No passwords, tokens, AWS credentials, seeds or signed upload URLs appear in this handoff.

## Sanitized evidence

- evidence/preview-inventory-live-readback.json: independent AWS result, reservation, history, inventory and ledger reads.
- evidence/preview-inventory-native-cli.json: native Swift public-URL workflow assertions.
- evidence/preview-inventory-runtime-readonly.json: public health/new routes and process roles.
- evidence/preview-inventory-source.json: integrated backend module hashes/source comparison.
- evidence/preview-inventory-fixture-tests.json and .txt: 60 fixture tests with timestamps.

The API contract and handoff are also saved in the task's outputs directory. No additional live test or stock mutation is required to reproduce this read-only audit.
