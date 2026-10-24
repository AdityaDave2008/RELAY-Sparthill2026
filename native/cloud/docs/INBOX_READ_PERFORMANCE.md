# Bounded inbox read optimization

The native task measured one public GET /v1/requests?view=mine&limit=50 with 19 items at 7.77 seconds. The old backend made one index Query, then one GetItem for each request and another for each reservation: **39 sequential DynamoDB calls** for that page.

The candidate change keeps the same API schema, authorization, index order, pagination cursor and strongly consistent reads. It fetches request and reservation records together, keyed by their primary keys, then applies the existing can_read check before projecting any result. Empty, dangling and unauthorized index references retain their existing behavior, including a next-page cursor on an empty filtered page.

AWS permits up to 100 distinct keys per BatchGetItem; results are unordered, can omit nonexistent items, and may identify unprocessed keys for retry. ConsistentRead must be explicitly true. The implementation deduplicates/chunks keys, restores order using the original index page, retries only unprocessed keys with bounded backoff, then reads any unresolved keys individually rather than silently omitting records. [AWS BatchGetItem API documentation](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_BatchGetItem.html)

If BatchGetItem is denied, the store remembers that denial for its lifetime and uses existing GetItem permission with at most six concurrent reads. All keys are namespace-validated before any read. Other service failures propagate as failures. No IAM grant, schema mutation, new index, cache of request data, or background job is required. Existing organizer IAM proposals were not changed; deployments without BatchGetItem still work through the fallback.

## Verification

- **67 backend tests passed**, 5.24 seconds, one existing Starlette TestClient deprecation warning.
- New SDK-stub cases cover unordered/partial/missing responses, duplicate keys, the 100-key cap, empty input, denial fallback and remembered denial, exhausted unprocessed keys, service errors and namespace checks.
- The API-level fixture case covers pagination across dangling/foreign references, scoped cursors, stable order and reservation projection while refusing per-record GetItem calls.
- **Read-only AWS check at 2026-10-24T08:46:13.585803Z:** account928489693154/us-east-1, the same synthetic requester-A membership returned 19 items using **one Query + one BatchGetItem**, no GetItem calls, in **0.597 seconds**. BatchGetItem was allowed.

The AWS timing is one direct backend-service read using existing server-side membership, **not a measured public HTTP/Cognito response time** and not a latency distribution. It is not directly comparable to the native task's 7.77-second full HTTP measurement. No AWS data, permissions or running processes were changed; no model or transcription call was made. The native task must cherry-pick the candidate and coordinate rollout before measuring the public endpoint again. API/model serialization is unchanged; no OpenAPI regeneration is needed.

Evidence: `evidence/inbox-batch-readonly-benchmark.json` and `evidence/inbox-batch-fixture-tests.json`. Focused-request polling and avoiding per-row history/inventory fan-out remain native-client responsibilities.
