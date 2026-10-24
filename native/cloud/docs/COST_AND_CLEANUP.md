# Cost observations and cleanup

**Observed consumption:** 12 durably accepted synthetic requests, 16 real Nova Lite invocations (4 standalone diagnostic calls included), **6,948 input tokens and 1,181 output tokens**, and one 1.824-second batch Transcribe job. One public Cognito client/domain and four synthetic MFA users were created. Three private S3 objects were verified (upload, sealed input, transcript). No Lambda/API Gateway stack was deployed.

This run was authorized after the user explicitly requested real service testing in response to the proposed $2 scope. Usage stayed within the 30-request/five-recording bounds; 18 request slots and four recording slots remain. The invocation total includes unsuccessful formatting tests, not just successful outputs. Actual billed charges and workshop credits are **not reconciled**; observed usage is not an invoice. See `evidence/aws-live-usage.json` for individual AWS request IDs and token counts.

The server still enforces three model dispatches per cycle, at most two explicit retry cycles, 512 maximum output tokens, and deterministic transcription job names. No TTS API, streaming, GPU instance, training or Marketplace subscription was used. The audio fixture was generated locally with macOS speech. Hosting is separate and remains unapproved/blocked; no scheduled Lambda idle charges exist. A running local worker queries DynamoDB while idle, so stop it when the approved demo window ends. Scope limits are not a hard AWS dollar cap.

Reference pricing pages: [Bedrock](https://aws.amazon.com/bedrock/pricing/), [Transcribe](https://aws.amazon.com/transcribe/pricing/). Reconcile actual charges before making claims about credits or final spend.

## Cleanup review

The exact new client, domain, synthetic users, Transcribe job, three S3 object keys and 12 request IDs are recorded in `RESOURCE_MANIFEST.json`. Preserve the private runtime `created-resources.json`; only non-secret resource IDs and test references were copied into the repository. Never copy `demo-identities.private.json`, tokens, passwords, TOTP secrets, browser login caches or presigned forms.

When cleanup is requested:

1. Stop the task's API/worker processes. If hosted later, disable recovery invocations and delete only the recorded `relay-cloud-mvp` stack. Confirm the stack owns each resource before deletion. The existing table/pool/bucket and organizer-managed role are outside that stack.
2. Delete only manifest-listed `relay-mvp-{transcription UUID}` jobs and their exact upload/sealed/transcript object keys. For deployment artifacts, delete only recorded object keys. Do not empty or delete the bucket or alter its policies.
3. Remove only manifest-owned synthetic request/transcription records, owner/shelter index references, operation records, work entries and counters in the `RELAY_MVP_V1#` namespace. Do not scan/delete the entire table or delete anything outside that prefix. Inspect pending work and export needed evidence first. If the namespace has acquired another producer, reconcile ownership instead of deleting the whole namespace.
4. Delete only the four synthetic users, newly created public client and newly created domain whose IDs match the runtime manifest. Never delete the existing user pool, original web client, dispatcher group or actual users. Confirm no app still depends on the new client/domain before deleting them.
5. Log out the task-specific CLI session and remove only task-owned temporary credential/token/TOTP files when no longer needed. Keep source, PR and sanitized test evidence. Never delete the user's unrelated AWS profiles or credentials.

No automatic cleanup or retention timer is enabled. These instructions describe a reviewable future cleanup; no destructive action has been performed.
