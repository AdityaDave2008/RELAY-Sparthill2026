# RELAY — actual AWS sample flow

**PASS: Cognito → private S3 → Amazon Transcribe → reviewed text → Amazon Bedrock Nova Lite → DynamoDB.** This used real AWS services and a synthetic 1.824-second recording. The API runs on this Mac at http://127.0.0.1:8787/docs; public hosting and iPhone integration remain unverified.

| Step | Actual observed result |
|---|---|
| Cognito | Four synthetic users signed in with authenticator MFA; repeated MFA sign-in also passed |
| S3 | WAV uploaded with a short-lived grant, validated, and sealed privately; encryption verified |
| Transcribe | Completed job `relay-mvp-REDACTED-ID-bae40cd8379c` |
| Review/edit | Corrected the misheard shelter name against the known sample |
| Nova Lite | Extracted quantity 2, water packs, destination shelter-a |
| DynamoDB | Accepted request and validated proposal persisted; independently read back |
| Restart | Killed/restarted an API process; unchanged replay recovered one request and one analysis |

**Spoken sample:** “Shelter A needs two water packs.”

**Actual raw transcript:** “Sheltering needs 2 water packs.”

**Reviewed text submitted:** “Shelter A needs 2 water packs.”

The shelter-name error demonstrates why transcript review is required. This short synthetic recording is not an accuracy benchmark for real/noisy speech. The agent performed this sample correction; no native review UI was tested.

**Actual validated model proposal:**

```json
{
  "item_id": "water_packs",
  "quantity": 2,
  "unit": "pack",
  "shelter_id": "shelter-a",
  "negated": false,
  "missing_fields": [],
  "summary": "Shelter A needs 2 water packs."
}
```

Cloud state: **accepted**. Analysis state: **ready_for_review**. Allocation authorized: **false**. Nothing was assigned, allocated or fulfilled.

Reviewed request UUID: `REDACTED-ID-17d6b0083baf`. Bedrock request ID: `REDACTED-ID-3cf9478856b9`. Transcribe start request ID: `REDACTED-ID-f1a9b5b208bf`. The edited result completed at `2026-10-24T05:38:35.863525+00:00`.

The complete real HTTP smoke ran from `2026-10-24T05:36:49.128804+00:00` to `2026-10-24T05:37:14.548931+00:00`. Thirty automated tests pass. Real tests also verified duplicate/conflict behavior, owner/shelter restrictions, requester-versus-dispatcher separation, missing quantity, negation, invalid shelter and malformed model output going to review. Raw evidence and limitations are in `BACKEND_TEST_RESULTS.md` and `evidence/`.

**Remaining:** the organizer-provided `relay-cloud-mvp-execution` role is absent. Lambda/API Gateway deployment, a phone-reachable HTTPS URL, native PKCE and physical-iPhone integration have not been tested. Existing Apple app sources remain untouched.
