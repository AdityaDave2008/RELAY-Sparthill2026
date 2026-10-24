# Approval proposal — first live backend verification

Status: **LIVE TESTING AUTHORIZED — 2026-10-24**. After receiving this proposal, the user explicitly requested the actual service flow with a sample recording, transcript and model result. Proceeding within the previously presented $2 incremental limit and bounded local-hosted scope. Results and created resources are recorded separately.

Account `928489693154`, region `us-east-1`; verified workshop session. Local HTTP smoke tests pass with fixtures, which do not verify AWS inference. Nova Lite availability reports agreement AVAILABLE and authorization AUTHORIZED. Cognito requires MFA and supports authenticator TOTP.

## Requested approval

Approve up to **US$2 in incremental AWS charges** for this bounded verification, using synthetic data only:

- Reuse `relay-messages` only under partition prefix `RELAY_MVP_V1#`; reuse the private `relay-artifacts-928489693154-use1` bucket only under `cloud-mvp-v1/`. Preserve existing resources, policies, data and MFA.
- Create one public Cognito client `RELAY-Cloud-MVP-Native`, one pool domain `relay-mvp-928489693154`, and four synthetic test accounts with authenticator MFA. Suppress invitation messages; no emails or SMS will be sent. The accounts receive only the backend's synthetic incident/shelter memberships, not the existing agency dispatcher group.
- Run the API and worker on this Mac's loopback address, authenticated with real Cognito tokens and backed by DynamoDB, S3, Amazon Bedrock and Amazon Transcribe. No public tunnel or hosted deployment in this approval.
- Accept at most 30 new synthetic requests and five short audio recordings. Each recording is mono PCM16 WAV, at most 60 seconds and 2 MiB. Start with one synthetic/TTS clip. This checks plumbing, not accuracy on noisy human speech.
- Use only `amazon.nova-lite-v1:0` through Converse, at most 512 output tokens per attempt. Each request allows three automatic attempts and at most two explicit retry cycles (nine inference attempts total). Use one deterministic Transcribe job name per recording.
- Verify a real text result, missing information/negation handling, transcript review/resubmission, authorization isolation, duplicate/conflict behavior and restart recovery. Record safe request/job IDs and usage; never record tokens or presigned forms.

Expected service consumption is substantially below the requested $2 allowance at this scale. This is a conservative spending ceiling, **not an AWS-enforced dollar cap**: record-count/attempt limits bound usage, and billing data can lag. Stop on unexpected pricing, service restrictions, increased scope or provider change. Do not purchase subscriptions, accept new provider terms, launch compute/GPU instances, train ASR or create paid Marketplace resources.

Temporary workshop access may expire and centrally funded workshop charges/credits are not yet independently reconciled. Report usage-derived estimates separately from actual billed charges.

## Excluded / separate approval

Public hosting, Lambda/API Gateway deployment, organizer IAM changes, native app integration, public tunnels, other models, streaming/TTS APIs and custom ASR hosting. Prepare deployment files and an organizer request for review while these remain unresolved.

## Cleanup

Keep an exact manifest of newly created client/domain/users and synthetic resource IDs. Cleanup must target only those manifest resources and the isolated namespaces; do not delete the existing pool, table, bucket, dispatcher group or participant role. Retain the verified backend and evidence for integration until cleanup is requested.

## Recorded outcome

Real Cognito MFA, S3, Transcribe, Nova Lite and DynamoDB verification passed. The run used 12 accepted requests, 16 total model calls including diagnostics, and one recording. See LIVE_AWS_DEMO.md, BACKEND_TEST_RESULTS.md and RESOURCE_MANIFEST.json. Public hosting was not performed.
