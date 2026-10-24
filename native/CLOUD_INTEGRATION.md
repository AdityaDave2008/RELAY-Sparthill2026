# Native cloud integration — build 13

The native app uses one backend contract with server-authorized requester and
coordinator workspaces. Help is the default requester screen; coordinator accounts
open Inbox and Inventory. Settings holds account and engineering tools. The same
SwiftUI/core sources build for iOS and macOS.

## Request flow

1. Sign in with the existing Cognito app account, password and authenticator code.
   Tokens are held in Keychain and refreshed with the public app client; AWS IAM
   credentials never enter the app. Roles come from `/v1/me`, not a UI selector.
2. Choose a shelter from the authorized directory. Speak or type a synthetic
   request. Voice records mono PCM16 WAV at 16 kHz, at most 60 seconds/2 MiB;
   supported 8/16 kHz WAV files can also be imported.
3. Transcribe through AWS, inspect/correct the transcript, then prepare editable
   structured fields with Bedrock. A preview never creates a shelter request or
   moves stock. People/quantity remain unknown when not reliably supplied.
4. Optionally attach one current location snapshot, including accuracy, precision
   and capture time. Permission is requested on demand. Approximate location,
   denial, removed location and landmark-only input are supported. Coordinates
   stay out of model input and the current plaintext nearby transport.
5. Review and Send. The same immutable request UUID is durably queued locally.
   Sending a matching preview reuses its result rather than running analysis again.
6. The coordinator reviews and reserves stock, replies, records handover or releases
   the reservation. Each command retains a durable operation ID for safe retries.

Drafts, outbox and pending commands are scoped to account/endpoint and persisted
in SQLite. Creation/retries do not depend on keeping an HTTP connection alive.
Existing device identities, nearby messages, shelters and receipt state are retained.
Foreground networking automatically discovers nearby peers. Background/terminated
encounters remain unsupported.

## Inventory semantics

Available = on hand − reserved. Approval reserves stock without changing on hand.
Handover deducts on hand and clears the reservation. Release or requester cancellation
returns availability. Stock, reservation, request history and audit entries commit
atomically with revision checks. Replaying an operation cannot duplicate a stock
movement; concurrent oversubscription and cancel-versus-handover are tested.

The model proposes fields; it never authorizes an allocation. A recorded handover
is a coordinator assertion and does not independently prove physical delivery.
Supported demo stock is water packs, food packs and blankets. Manual stock adjustments
retain an operation ID, reason and revision; use synthetic quantities only.

## Hosting and credentials

The bundled HTTPS URL points through Cloudflare to the API on this Mac. The API
and a single worker use real Cognito, S3, Transcribe, Bedrock Nova Lite and DynamoDB.
See [DEMO_HOSTING.md](DEMO_HOSTING.md) for runtime requirements. Permanent AWS
Lambda/API Gateway deployment is still blocked on the organizer role/PassRole.

The two owned DEBUG phone installations were prepared with existing MFA-authenticated
sessions over the trusted device connection. A bounded one-use file is imported
into Keychain and deleted. This code is excluded from Release. TestFlight uses
normal native account/MFA sign-in; no password, token or private configuration is
embedded in the distributed binary. Account self-registration is disabled.

For another endpoint, configure `RELAY_CLOUD_API_URL` when generating the project,
then build/upload with a new number. HTTP endpoints or URLs containing credentials,
queries or fragments are rejected. Existing saved endpoint overrides the default;
engineering configuration is under Settings → Developer tools. Queues are scoped,
so changing an endpoint is not an automatic migration of its old outbox.

## Verification and remaining work

49 Swift and 67 backend tests pass. Shared Swift HTTP tests cover live MFA/refresh,
preview reuse, synthetic location, stock reserve/fulfill/replay and restored stock.
Native Mac UI tests cover password/MFA, preview, Review/Send, approval, stock totals
and release with independent AWS readback. Build 13 is installed and launched on both
phones with prior stores preserved, and is Testing in the internal TestFlight group.
See [TEST_RESULTS.md](TEST_RESULTS.md) for exact evidence and [MOBILE_TEST.md](MOBILE_TEST.md)
for the requested phone test.

Phone microphone capture, actual GPS permissions/accuracy, the full phone sequence,
long-duration native session refresh and account-switch races need further device
verification. The WAV picker correction compiled but was not reverified after the fix.
Noisy-speech quality and multilingual coverage are not measured.

A cloud request currently waits for its originating device to reconnect to internet.
An authenticated carrier-to-cloud gateway, encrypted cross-transport location and
trusted offline return replies remain pending. Existing P2P text/receipt forwarding
continues separately, without organizational authentication or confidentiality.
Controlled physical no-router A–E tests remain unverified. This is a prototype,
not a production emergency service or a demonstrated disaster-resilient network.
