# RELAY API and frontend contract

Implementation handoff for the frontend. Run from the repository root:

```sh
npm install
npm run dev:api
```

The local API listens on `http://127.0.0.1:8787` and persists to DynamoDB when
`RELAY_TABLE_NAME` is configured, otherwise `services/api/data/relay.json`.
Copy `.env.example` to `.env` in this directory
to configure AWS or tokens. No AWS account is needed for local message delivery;
classification requires real Bedrock credentials and `BEDROCK_MODEL_ID`.

## Shared message format

Import `RelayMessage`, `createMessage`, `MessageStore`, and transport helpers
from `@relay/core`. Existing fields are preserved: `id`, `kind`, `priority`,
`originDeviceId`, `createdAt`, `expiresAt`, `hops`, `maxHops`, `body`, optional
`location: { lat, lon, accuracyM }`, and `replyTo`. Timestamps are epoch **ms**.
Optional `recipientDeviceId` addresses responder replies; `incidentId` links
a warning to frontend incident/zone data. Warnings preserve optional `title`
(up to 120 characters) and `translations: { [languageCode]: { title, body } }`
(up to 12 languages, each body up to 1000 characters). Kinds use lowercase strings:
`help_request`, `warning`, `status`, `ack`.

Do not rename these fields to the illustrative JSON from the earlier chat.

## HTTP contract

All request/response bodies are JSON. Errors are
`{ "error": { "code": "...", "message": "..." } }`.

| Method / path | Access | Request / response |
| --- | --- | --- |
| `GET /v1/health` | Public | `{ ok, mode: "simulation", storage, bedrockConfigured }` |
| `POST /v1/messages/batch` | Device | `{ deviceId, messages: RelayMessage[] }` → `{ acceptedIds: string[], rejected: [{ id, reason }] }`; at most 50 messages |
| `GET /v1/messages?deviceId=...&cursor=...&limit=50` | Device | `{ messages: RelayMessage[], nextCursor: string \| null }`; live warnings and replies addressed to that device |
| `GET /v1/requests?cursor=...&limit=50` | Coordinator | `{ requests: RequestRecord[], nextCursor: string \| null }` |
| `POST /v1/requests/:id/classify` | Coordinator | Real Bedrock extraction → updated `RequestRecord`; unavailable AWS returns an error, never a fake classification |
| `POST /v1/requests/:id/response-draft` | Coordinator | `{ notes, language? }` → `{ request: RequestRecord, draft: BulletinDraft }`; Bedrock extracts needs, then prepares a grounded reply and accessible versions using source notes; does not send |
| `POST /v1/requests/:id/replies` | Coordinator | `{ id, body }` → `{ message: RelayMessage }`; client generates a stable reply ID for retries |
| `POST /v1/warnings` | Coordinator | `{ id, body, title?, translations?, incidentId?, location?, ttlMs? }` → `{ message: RelayMessage }`; this action represents simulated approval |
| `POST /v1/bulletins/draft` | Coordinator | `{ notes, language?: "English" }` → `{ message, spokenMessage, noticeTitle, noticeLines, pictograms, language, requiresHumanApproval: true, source: "amazon-bedrock", modelId, awsRequestId? }`; generates drafts without publishing |
| `POST /v1/briefing` | Coordinator | `{ zones }` → `{ generatedAt, headline, priorities, zones, gaps, requiresHumanReview: true, source, modelId, awsRequestId? }`; Bedrock reviews all open requests, ranks follow-up and flags information gaps |
| `POST /v1/cards/read` | Device / coordinator | `{ imageBase64, mediaType: "image/jpeg", incidentId }` → `{ needs, peopleCount, locationDescription, notes, unreadable, requiresHumanReview: true, source, modelId, awsRequestId? }`; real Bedrock vision, no automatic save |

`RequestRecord = { message: RelayMessage, receivedAt: number, repliedAt?: number,
classification?: { needs: string[], peopleCount: number | null,
locationDescription: string | null, summary: string,
requiresHumanReview: true, source: "amazon-bedrock", modelId: string,
awsRequestId?: string } }`.

Pagination order is message ID. Treat cursors as opaque, and follow them even
when a filtered page is empty. Merge records by message ID in the frontend.

Briefs accept 1–24 unique zones with `id`, `name`, `population`, `connectivity`
(`online`, `degraded`, `offline`) and `reach: { digital, radio, none }` shares
adding to 1. At most 100 open requests are supported; larger inputs return an
explicit capacity error. Output request/zone IDs are checked against the inputs.
Priorities are logistics follow-up suggestions for human review, not clinical
triage or dispatch instructions. Silent zones have unknown needs.

Card images must be valid base64 JPEGs, at most 1 MiB decoded and 1400 pixels
per side. The card endpoint accepts JSON up to 2 MiB; other JSON routes remain
limited to 256 KiB. Images go to Bedrock and are not persisted. A volunteer
checks the extracted fields before creating a normal help request. Pictograms
are chosen by Bedrock from `water`, `food`, `medical`, `shelter`, `danger`,
`route`, `info` and validated before returning the draft.

Send `Authorization: Bearer <token>` when configured. Coordinator tokens can
also use device routes. Both device and coordinator tokens are required outside
loopback and in Lambda. These are shared **demo** tokens, not verified device
identity or production authorization. All demo information must be fictional.

## Resident / relay integration

Create a durable store with `MessageStore.open(localStoragePersistence(
localStorage, "relay:device-id"))`. Opening a corrupt snapshot or a failed
storage write throws; show an error rather than claiming the message was saved.
Use one active owner per storage key; cross-tab editing is not coordinated.

`encodeTransfer(store, { ids? })` returns text frames for a QR display or other
transport. Feed scanned/received frames to `TransferReceiver.accept(frame)`.
The receiver stores a batch only after all frames pass the checksum. This is
packet handling; camera UI, QR rendering, native radios, and app-shell caching
belong to the frontend/transport integration.

`syncWithGateway(store, { baseUrl, deviceId, token? })` uploads pending
messages, marks only accepted IDs uploaded, and downloads warnings and replies.
It also fetches replies for the origins of help requests carried by this relay,
so a volunteer can carry the response back to the original offline device.

Delivery labels must reflect actual events: **saved locally** after persistence;
**relayed** after receiver confirmation; **uploaded** after API acceptance;
**acknowledged** only when an `ack` with matching `replyTo` is received.
Uploading and AI classification do not mean a responder has acknowledged it.

Claude owns the resident/coordinator screens, zone presentation, camera/QR UI,
and paper help cards. Codex owns the shared core, packet/storage adapters, API,
and AWS integration. Geographic incident editing stays frontend-owned for this
first integration; warnings carry its `incidentId`.

## Local and AWS operation

Local storage is an atomic JSON file for a single API process. AWS mode uses
DynamoDB conditional writes and a paginated query, with the same HTTP contract.
The API saves a request before classification. New uploads automatically queue
Bedrock extraction in the local server. Unclassified requests are recovered on
restart, and automatic failures use backoff with at most three attempts per
process; the coordinator can explicitly retry. In AWS, DynamoDB Streams invokes
a separate Lambda classification worker with bounded retries. The API and local
worker share in-flight analysis to avoid duplicate local calls. A model timeout
or refusal does not discard the request or produce a fake AI result.

`repliedAt` is stored on the original request after a reply is saved, so a
dashboard can show answered requests consistently across browsers. This records
coordinator action, not delivery confirmation to the offline resident.

The coordinator's main **Prepare response** action calls `response-draft`, then
shows the extracted needs beside the original request and the generated reply.
After reviewing/editing the draft, **Approve and send** calls `replies` with a
new stable ID and the approved message body. This is the primary AI workflow,
not a separate chatbot or a decorative label. The offline network carries the
approved result back to the resident. `bulletins/draft` supports proactive
neighborhood updates and printable/spoken versions of coordinator source notes.

Workshop AWS calls are pinned to **us-east-1**. Set both `AWS_REGION` and
`AWS_DEFAULT_REGION` accordingly. The event operator must authorize any change.
The current workshop model is `us.anthropic.claude-sonnet-5-5`. The SDK request
omits temperature/top-p settings so models that deprecate them can run.
For Sonnet 5.5, `additionalModelRequestFields.output_config.effort` is `low`
to keep the bounded extraction/drafting jobs responsive.

```sh
npm run aws:models --workspace=@relay/api
npm run smoke:bedrock --workspace=@relay/api
npm run smoke:http --workspace=@relay/api
npm run build:api
```

The live smoke test uses fictional data and real Bedrock inference for needs
extraction and a Spanish response, then verifies its software packet round trip.
It does not test phone cameras or radios. `template.yaml` packages the HTTP API,
DynamoDB table, and stream worker for AWS SAM. From `services/api`, after
building, deploy with `sam deploy --template-file template.yaml --region
us-east-1 --guided`. Supply the model ID, two distinct demo tokens, and exact
frontend origin when prompted. Deployment creates AWS resources; the automated
test suite does not deploy them.

`smoke:http` requires a running API and verifies that a real HTTP upload triggers
automatic Bedrock classification, prepares a Spanish response, and persists
coordinator approval. It creates fictional demo records in the local database.
The integrated frontend defaults to live `/api` through its same-origin proxy.
`npm run dev` or `npm start` at the root starts both servers. Explicit
`VITE_MOCK_API=true` enables labelled fixtures; it cannot demonstrate AWS AI.
Never put AWS credentials in a `VITE_*` variable; only the backend reads them.

Native nearby transfer, public warning-system integration, signatures, and
production end-to-end encryption are not implemented by this API. Warning
approval is a simulation, and sender IDs are routing labels, not authenticated
identities. Bedrock output stays unverified and requires human review.

## AWS track demo requirements

Persona: a neighborhood relief coordinator who must understand requests and get
accurate resource updates back to residents whose normal communication is down.

Bedrock is required for the track. The coordinator workflow should show both a
real `classify` call and a real `bulletins/draft` call, using the structured needs
and approved message in the actual application. Show the returned model ID and,
when available, AWS request ID as demo evidence. A configured health flag or
test-double response is not evidence of a live Bedrock call.

The five-minute submission video is due October 24, 2026 at 10:30 AM. Include
architecture, the persona's working round trip, live Bedrock results, and the
team contact method the organizers specify. The challenge also asks teams to
build with Kiro; work in a separate Claude app or Codex does not establish that
requirement has been met.

AWS references: [Bedrock Converse SDK examples](https://docs.aws.amazon.com/sdk-for-javascript/v3/developer-guide/javascript_bedrock-runtime_code_examples.html),
[DynamoDB JavaScript guidance](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/programming-with-javascript.html).
