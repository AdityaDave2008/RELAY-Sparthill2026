# RELAY cloud integration handoff — contract v1

**Build-8 integration update:** the native client is implemented and builds on iOS/macOS; 43 Swift + 35 backend tests pass. `/v1/me`, request `/history` and `/events` are now part of the contract. The Swift HTTP client passed real AWS text/audio/reviewed-text/history tests through `http://127.0.0.1:8788`. Public HTTPS, native PKCE/microphone/phone UI and signed carrier ingestion remain unverified or pending. See ../../CLOUD_INTEGRATION.md and ../../TEST_RESULTS.md. Sections below describe the original backend handoff; the public Cognito configuration remains unchanged.

## Current endpoint and verified scope

Actual local endpoint: **http://127.0.0.1:8787**, `/v1/health` and `/docs`. The base address redirects to `/docs`. Hosting: this Mac, loopback only, with **real Cognito authentication, DynamoDB storage, private S3, Amazon Transcribe and Amazon Bedrock Nova Lite**. Health now reports mode `aws` and storage `dynamodb`.

The real HTTP text/audio flow passed at 2026-10-24 05:36:49–05:37:14 UTC. A corrected reviewed transcript was submitted at 05:38:33 UTC and produced a persisted proposal. Actual AWS process-crash/replay recovery also passed. See `LIVE_AWS_DEMO.md` and `BACKEND_TEST_RESULTS.md` for the exact transcript, model output, request/job IDs and limitations.

This endpoint is not reachable from a separate iPhone: localhost on an iPhone refers to the phone. No public HTTPS endpoint or tunnel exists. The dedicated Lambda execution role is still absent (`NoSuchEntity` checked at 05:37:38 UTC). The backend contract and AWS integrations are verified for this synthetic sample; public hosting and native PKCE/phone integration are the remaining gates.

## Authentication and public app configuration

| Field | Value / status |
|---|---|
| Region | `us-east-1` |
| User pool | `us-east-1_f7wyKUgiY` |
| Issuer | `https://cognito-idp.us-east-1.amazonaws.com/us-east-1_f7wyKUgiY` |
| New public app client | `RELAY-Cloud-MVP-Native`, client ID `dfulb5lau8283nlgil7ddu36i` (created and verified) |
| Hosted login domain | `relay-mvp-928489693154.auth.us-east-1.amazoncognito.com` (ACTIVE) |
| Native callback | `relay://oauth/callback` configured in Cognito; not registered in Apple app |
| Native logout | `relay://oauth/signout` configured in Cognito |
| Scopes | `openid email` |
| Flow | Authorization code with PKCE S256; no client secret |
| MFA | Existing pool requires MFA; software authenticator enabled |

The existing `RELAY-Dispatcher-Web` client does not have the required OAuth/PKCE configuration; do not silently reuse it. For the new public client, use ASWebAuthenticationSession to open `/oauth2/authorize` with `response_type=code`, client_id, redirect_uri, scopes, unpredictable state and an S256 code challenge. Validate returned state; exchange the code at `/oauth2/token` using the original verifier and redirect URI. Store tokens in Keychain. The backend requires the **access token**, validates its signature/issuer/expiry/client_id/token_use, and maps its real `sub` to server-controlled incident/shelter membership. ID tokens, device UUIDs, display names and caller-supplied roles do not authorize access. Membership removal is operator-controlled; JWT revocation is not checked online on every request, so token expiration and membership removal bound access after revocation.

The provisioning/test script successfully authenticated four synthetic users with password + TOTP. A second sign-in for each returned SOFTWARE_TOKEN_MFA, completed that challenge and accessed the API. TOTP is enabled/preferred for these synthetic accounts; pool MFA remains required. Native PKCE browser login remains untested. Never put AWS access keys, a client secret, test signing keys or shared server tokens in the app.

Reference: [Cognito public clients](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-client-apps.html), [token exchange/PKCE](https://docs.aws.amazon.com/en_en/cognito/latest/developerguide/token-endpoint.html).

## Identities, acceptance and retries

Use API version `/v1` and `schema_version: 1`. `request_id` must equal the original immutable relay message UUID; keep it unchanged across retries. `operation_id` is a separate stable UUID for that operation. `origin_device_id` identifies the originating installation, not the authenticated user. Incident IDs and shelter IDs are directory identifiers; names are labels. Server JWT subject is authoritative for ownership.

The first accepted submission returns **201** after an atomic data/queue commit. Replaying the exact same request ID/content/operation ID returns **200** and the current record. A changed immutable field with the same request ID returns **409**. Canonical UTC timestamps are normalized; text is preserved exactly. Revision 1 is immutable; revisions, editing accepted records, supersession and cancellation are not implemented. Editing a completed transcript before the first request submission is supported.

A timeout or 503 can mean the commit succeeded and its response was lost. Retry the identical payload; never generate a new message UUID to resolve uncertainty. Exponential backoff with jitter (1, 2, 4, 8 seconds, cap 30 seconds) is appropriate for retryable responses. Refresh auth after 401. Surface 409 conflicts for review; do not overwrite. Respect the demo cap on 429; there is no automatic quota reset. Newly submitted expired requests return 410, while exact replays of already accepted requests still retrieve acceptance.

Cloud acceptance is separate from `analysis_state`: `pending`, `retrying`, `ready_for_review`, `needs_review`, `failed`. Even ready_for_review requires dispatcher review. `allocation_authorized` is always false; assignment and fulfillment remain `not_implemented`. A provider failure never erases acceptance. At most three automatic dispatches occur per analysis cycle, including crash-reclaimed dispatches; a POST to `/v1/requests/{id}/retry-analysis` with a new stable operation ID allows at most two explicit retry cycles. It returns 202. Repeating that same retry operation is idempotent.

## Routes

| Route | Success | Meaning |
|---|---|---|
| GET `/v1/health` | 200 | Public liveness; never invokes AI or certifies its availability |
| GET `/v1/shelters` | 200 | Only caller-authorized synthetic shelters |
| POST `/v1/requests` | 201 / 200 | New durable acceptance / exact replay |
| GET `/v1/requests/{UUID}` | 200 | Owner or authorized destination dispatcher |
| GET `/v1/requests?view=mine&limit=20` | 200 | Caller-owned inbox; next_cursor pagination |
| GET `/v1/requests?view=shelter&shelter_id=...` | 200 | Dispatcher only, authorized shelter |
| POST `/v1/requests/{UUID}/retry-analysis` | 202 | Explicit bounded retry of failed analysis |
| POST `/v1/transcriptions` | 201 | Allocate or renew an identical owned upload record |
| POST `/v1/transcriptions/{UUID}/start` | 202 | Validate/seal recording, durably queue one named job |
| GET `/v1/transcriptions/{UUID}` | 200 | Owner only, including editable transcript |

List limits are 1–50. Treat cursors as opaque and reuse them only for the same user/view/shelter. A dispatcher may read authorized request proposals but cannot read another user's raw transcription record. Requesters have no dispatcher inbox privilege. Unauthorized record lookups return 404.

See `openapi/relay-v1.yaml` for full schemas and examples. Bodies are limited to 32 KiB; original text is 1–4096 characters. Lifetimes must be positive and at most seven days; creation timestamps may be at most five minutes in the future.

## Short recorded audio

1. Record **mono, uncompressed PCM16 WAV**, 8 kHz or 16 kHz, duration greater than zero and at most **60 seconds**, total at most **2 MiB**, language `en-US`. AAC/M4A/stereo recordings must be converted on device before upload.
2. Compute byte length and lowercase SHA-256 of the exact upload bytes. POST `/v1/transcriptions` with schema_version, stable operation_id, transcription_id UUID, incident_id, content_type `audio/wav`, byte_length, sha256, language_code.
3. Read `upload`: in AWS mode it is a **multipart S3 POST** with a URL and form fields. Send every returned field unchanged, then a `file` part containing the WAV. Do not add the API bearer token to S3. Native URLSession requires no browser CORS configuration. The grant lasts **300 seconds**, permits one allocated object key and exact declared size; treat it as a short-lived secret and never log it. Fixture mode instead returns an authenticated local PUT, for local tests only.
4. Call `/start` with one stable start operation_id. Server verifies size/checksum/WAV/duration and copies valid bytes to a separate private sealed key. Reusing the upload grant cannot change that sealed job input. No caller-controlled S3 URI is accepted. Identical starts reuse one deterministic Transcribe job name; differing start IDs conflict.
5. Poll GET every 2–3 seconds with a bounded UI timeout. States: awaiting_upload, upload_expired, queued, processing, completed, failed. Server polling is bounded at 900 seconds per start cycle. Hosted recovery may add up to roughly a minute after a lost wakeup. Worker retries transient provider failures at most three times. A retryable failed transcription may be resumed with the original start operation up to three start cycles; terminal provider failures require a new recording. It never creates a second job for the same transcription UUID.
6. Present the completed transcript for **explicit user review/edit**. No request is submitted automatically. After review, POST the normal request body with `input_mode: reviewed_transcript`, the owned completed transcription_id, and the reviewed text as original_text. Preserve the originating message UUID. Typed text is always usable without a transcription record.

For expired uploads, repeat the exact allocation body to renew authorization. For invalid uploads, a visible error is attached to the awaiting-upload record; correct/reupload bytes matching the original checksum or allocate a new recording for different content. Uploads are bearer capabilities scoped to an authenticated owner's allocation, not permanently bound to the owner's device. Private originals/transcripts require explicit cleanup; no retention deletion is currently automatic.

## Error envelope and timing

All application errors use `{"error":{"code":"...","message":"...","retryable":false}}`. Schema mismatch 422; invalid shelter/lifetime/cursor 400; authentication 401; wrong role/shelter 403; hidden/missing record 404; conflicting immutable IDs or concurrent transition 409; expired new request 410; oversized body 413; demo cap 429; unavailable/uncertain storage/provider 503. Gateway-generated deployment errors may have a different envelope, so clients must also handle non-JSON responses. Retry only indicated recoverable errors, or transport failures with the identical operation.

Use an API timeout around 30 seconds and S3 upload timeout around 60 seconds. A `/start` response may be lost during validation; safe replay is required. Poll analysis for up to 4 minutes in the demo UI, then retain the accepted request for later status lookup. Do not interpret a UI polling timeout as rejection or resubmit with a new ID.

Live tests found that Nova Lite can still emit malformed JSON or invent an unstated quantity. Invalid output stays needs_review; ungrounded quantity values are cleared, and missing quantity/negation are checked from source text even when parsing fails. Model output is parsed as JSON and validated by the backend; native model schema enforcement is not assumed. Missing quantity, negation, contradictory shelters, unsupported quantities/units and malformed output are sent to review. Supported demo items are water packs, food packs and blankets; this is intentionally conservative English extraction, not a general logistics decision model.

## Swift URLSession documentation examples

These original examples are now supplemented by the built native implementation in App/Cloud*.swift and Sources/RelayCore/Cloud*.swift. Native browser/device flow still needs hosted verification.

```swift
// body comes from the persisted original message; never regenerate its IDs on retry.
func submitRequest(baseURL: URL, accessToken: String, body: Data) async throws -> (Data, Int) {
    var request = URLRequest(url: baseURL.appendingPathComponent("v1/requests"))
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return (data, http.statusCode) // Handle 201/200 separately from AI completion.
}
```

```swift
// S3 multipart upload: use every returned field verbatim, file last, no API token.
func uploadWAV(url: URL, fields: [String: String], wav: Data) async throws {
    let boundary = "RELAY-\(UUID().uuidString)"
    var body = Data()
    func append(_ text: String) { body.append(Data(text.utf8)) }
    for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }
    append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
    body.append(wav)
    append("\r\n--\(boundary)--\r\n")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    let (_, response) = try await URLSession.shared.upload(for: request, from: body)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { throw URLError(.badServerResponse) }
    // Next: authenticated /start, poll, then explicitly review/edit transcript.
}
```

## Remaining integration gates

Real AWS tests and scripted Cognito MFA login now pass. Next resolve the dedicated execution role and separately approve HTTPS hosting; run the independent client against that hosted URL; then register the native callback, implement PKCE/Keychain, map the existing persisted message IDs, add cloud acceptance/result state and optional reviewed audio. Finally test on physical iPhones. No native integration, offline gateway sync, signed gateway ingestion, inventory allocation, fulfillment, custom ASR, TTS or Android support is claimed here.

Future relay/gateway ingestion needs a separately versioned signed envelope, original-sender proof, replay protection and membership verification. No unsigned gateway endpoint exists; forwarding another person's text under the gateway's token does not authenticate the original sender.
