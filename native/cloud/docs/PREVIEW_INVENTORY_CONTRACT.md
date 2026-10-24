# Pre-send preview, location and inventory contract

Implemented from native integration commit `8c207e736d269b02d52d888b8de12ac360ed1db7` on `feature/cloud-inventory-preview`; backend commit `62dcf9035bc0bf02054debe53b08a478e4bf379e`, integrated as `fe7b88dad016c43066a6f272f2a0f6ae94855667`. Changes are confined to `cloud/`. Implementation used fixture tests without runtime changes or paid calls. The native task subsequently coordinated runtime replacement and one bounded live workflow; independent AWS readback passed at 08:12 UTC. See [CLOUD_DEPLOYMENT_HANDOFF.md](CLOUD_DEPLOYMENT_HANDOFF.md) for current evidence and the remaining managed-hosting gate.

## Request flow

1. Optionally upload/transcribe speech through the existing authenticated transcription endpoints. Read and correct the transcript.
2. Create a durable interpretation and poll it. It is a private draft: it creates no submitted help request, inbox entry, reservation or inventory effect.
3. Display the validated proposal, including missing fields/review reasons. Let the requester confirm/edit structured fields and optionally attach a location.
4. Explicit Send submits the ordinary request with a **new operation ID**, the same text/shelter/incident/transcription, and the interpretation ID. Its saved analysis is reused without another Bedrock call.
5. The authorized coordinator reads inventory and reserves stock, then records fulfillment or releases the reservation.

All non-health routes require the existing verified Cognito access token and server-side membership. Keep secrets out of configuration and logs. Existing MFA requirements are unchanged.

## Pre-send interpretations

`POST /v1/interpretations` returns HTTP **201** on first acceptance, **200** for identical replay:

```json
{
  "operation_id": "REDACTED-ID-576f18824476",
  "interpretation_id": "REDACTED-ID-95eb2692c90e",
  "incident_id": "synthetic-demo-01",
  "destination_shelter_id": "shelter-a",
  "original_text": "Shelter A needs 2 water packs.",
  "transcription_id": null
}
```

`GET /v1/interpretations/{interpretation_id}` returns the same response shape:

```json
{
  "interpretation_id": "REDACTED-ID-95eb2692c90e",
  "status": "pending",
  "result": null,
  "error": null
}
```

Status is `pending | ready_for_review | needs_review | failed`. `result` uses the existing `ValidatedResult` schema; `allocation_authorized` always remains false. Only its owner can read/use a preview, and current shelter membership is checked. If supplied, transcription must be owned, completed, and belong to the same incident. Changed content with reused identifiers returns 409.

The existing durable worker queue handles previews with the same lease, bounded transient retry, and persisted dispatch count used for requests. Crash recovery cannot retry paid analysis indefinitely. Failed previews are not silently resubmitted: a fresh explicit preview requires new IDs and another budget slot. Preview validity for Send is 24 hours.

**Budget:** each new preview uses one existing `requests` budget slot. Sending its matching result binds it atomically to one request ID and uses no second slot/call. Abandoned/failed previews still count. Concurrent consumers cannot create two requests from one preview. A submission without a preview retains the old bounded analysis path. This changes the counter's meaning from only submitted requests to **request/preview analysis slots**; the configured cap is unchanged. Last live counters before this implementation were 17/30 slots and 3/5 recordings; fixture tests do not alter them.

## Backward-compatible request fields

`POST /v1/requests` keeps existing required fields and adds optional nullable:

```json
{
  "interpretation_id": "REDACTED-ID-95eb2692c90e",
  "location": {
    "latitude": 37.3352,
    "longitude": -121.8811,
    "horizontal_accuracy": 25,
    "captured_at": "2026-10-24T08:00:00Z",
    "precision": "approximate",
    "source": "device"
  },
  "structured_fields": {
    "item_id": "water_packs",
    "quantity": 2,
    "unit": "pack",
    "people": null,
    "landmark": "Synthetic gate"
  }
}
```

Location requires finite latitude [-90,90], longitude [-180,180], nonnegative accuracy in meters (maximum 20,000,000), timezone-aware captured_at, precision `precise|approximate`, and source `device|manual`. No coordinate/location or landmark fields are added to the model prompt. User-entered original text remains the text analyzed. Location is carried only in the authenticated request record; native transport decisions are owned by the app task.

Structured item is `water_packs|food_packs|blankets|other`; quantity is an optional strict integer 1–10000; unit is optional `pack|piece|bottle`; people is optional strict integer 1–1000000; landmark is optional text up to 500 characters. Unknown quantity/unit/people may be null or omitted. Known item/unit pairs must agree. Structured fields and location may be edited before Send without a new preview; changing original_text, incident, shelter or transcription requires a new preview.

Absent/null new fields are excluded from immutable stored digests, preserving replay of pre-upgrade submissions. A used preview cannot be attached to a second request; replay the original complete request and IDs after a lost response. Pending/failed previews cannot be submitted through interpretation_id.

## Inventory

`GET /v1/inventory?shelter_id=shelter-a` is dispatcher-only and scoped to membership:

```json
{
  "shelter_id": "shelter-a",
  "items": [{"item_id":"water_packs","unit":"pack","on_hand":0,"reserved":0,"available":0,"revision":0}]
}
```

The real response lists all three supported items: water_packs/pack, food_packs/pack, blankets/piece. An absent item starts at zero stock/revision 0. No initial stock is invented. `available = on_hand - reserved`. Revisions are per shelter/item and increment for each committed stock change.

Dispatcher `POST /v1/inventory/{shelter_id}/adjust`:

```json
{"operation_id":"REDACTED-ID-b4b6412c243e","item_id":"water_packs","quantity_delta":10,"expected_revision":0,"note":"Synthetic demo stock"}
```

Returns the full inventory response, HTTP 200. Delta is a nonzero strict integer between -1000000 and 1000000; nonblank note required, at most 500 characters. Stock cannot exceed 1,000,000,000 or drop below reserved quantity. A stale expected revision returns 409. This is a human-entered ledger adjustment, not a sensor verification of physical stock.

## Request reservation and coordinator actions

`GET /v1/requests/{request_id}/inventory` is readable by the owner or authorized dispatcher. Dispatcher-only `POST` to the same path accepts:

```json
{"operation_id":"REDACTED-ID-676a3a34ff0f","action":"reserve","item_id":"water_packs","quantity":2,"expected_inventory_revision":1}
```

Response for both methods, HTTP 200:

```json
{
  "request_id":"REDACTED-ID-072e4e6126bd",
  "reservation":{"item_id":"water_packs","quantity":2,"unit":"pack","status":"reserved"},
  "history":{"request_id":"REDACTED-ID-072e4e6126bd","revision":1,"status":"accepted","events":[],"resource_allocation_verified":true,"physical_delivery_verified":false}
}
```

The example omits the actual generated history event for brevity; real responses include it. No reservation returns null plus current history.

| Action | Inventory effect | Reservation / history |
|---|---|---|
| reserve | reserved += quantity; requires enough available stock | reserved / accepted |
| fulfill | on_hand -= quantity AND reserved -= quantity, once | fulfilled / completed |
| release | reserved -= quantity; on_hand unchanged | released / rejected |

Reserve may omit item/quantity when explicit structured fields or a ready-for-review proposal supplies them. Staff invocation is still required; models never reserve. Prefer sending explicit reviewed item/quantity. Only the three supported inventory items are reservable. Fulfill/release affect the entire existing reservation; optional item/quantity, if present, must match it. expected_inventory_revision is optional but enforced when supplied. Each request gets one reservation lifecycle; terminal/released requests cannot reserve again.

Each operation atomically writes stock, reservation, history, immutable ledger entry and actor-scoped idempotency result. An overbooking race allows only the transaction matching the current versions. Reusing the same operation/body returns its original committed response snapshot and makes no second stock/history effect; use GET for current state after later actions. Reusing the operation ID with changed content returns 409. Unknown outcomes may be retried with the identical operation/body; revision conflicts require refreshing the state before a new decision.

`assignment_state` in RequestResult becomes `unassigned|reserved|released|fulfilled`; `fulfillment_state` becomes `not_fulfilled|fulfilled`. Old `not_implemented` values remain accepted by the response schema. Analysis result `allocation_authorized` remains false. History `resource_allocation_verified:true` means a ledger reservation/fulfillment committed, **not physical delivery**; physical_delivery_verified is always false.

## Cancellation and older progress clients

Requester `/events` cancellation atomically releases active stock. Dispatcher rejection through `/events` does the same. They cannot trap reservations at the ordinary 100-event reply cap. Cancellation and fulfillment races produce exactly one coherent outcome.

Old `/events` accepted/in_progress without a reservation returns 409 `inventory_action_required`. Completed always requires the inventory fulfill endpoint. Replies remain supported; accepted reservations may transition to in_progress through `/events`. Already committed old event operations still replay after upgrade without changing stock. Existing terminal legacy requests are not retroactively counted as verified inventory fulfillment.

Common errors retain `{error:{code,message,retryable}}`: `idempotency_conflict`, `interpretation_not_ready`, `interpretation_mismatch`, `interpretation_already_used`, `interpretation_expired`, `inventory_revision_conflict`, `revision_conflict`, `insufficient_inventory`, `reservation_not_active`, `reservation_mismatch`, `request_terminal`, `inventory_action_required`; missing reservation details return 422. Unrelated users see 404 for another request/preview; role/shelter violations return 403.

## Validation and coordinated rollout

Fixture-only suite: 60 tests pass, including independent SQLite connection races for overbooking, cancellation/fulfillment, and one-preview/two-request consumption; durable restarts, lost-response idempotency, old digest/event replay, audio ownership, location bounds and prompt omission. Existing SDK wire-contract tests pass. These are not new live DynamoDB/Bedrock or native-phone results.

Before exposing the new API, cherry-pick this backend commit into the native source and validate its DTO/client flow. Stop the old shared worker before a new preview can enter `RELAY_MVP_V1#WORK`: old workers cannot understand interpretation tasks. Start the merged API and worker with the preserved private config/durable data and existing caps. No table migration or new IAM grant is required; new records stay under the existing isolated prefix.

The old 8787 process had old write logic; new endpoint guards cannot protect requests mutated through a stale API. The native task retired that listener and the old AWS worker during rollout; independent process checks confirmed this at 08:11 UTC. Keep mutation traffic on the coordinated new 8788 API and do not restart the old source. The temporary tunnel continues targeting 8788. Do not deploy the older cfcaade ZIP over this new source.

The agreed bounded live preview/inventory flow passed after coordination and is documented separately in the handoff. Synthetic stock is a ledger test, not real inventory. HTTP/CLI success does not establish physical UI or AWS Lambda hosting deployment.
