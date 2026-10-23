# Frontend contract notes

The source of truth is [`services/api/README.md`](../../services/api/README.md)
(owned by Codex). This file only lists what the frontend adds on top of it,
and integration details. Types live in [`src/contract.ts`](src/contract.ts).

## Where Bedrock appears in the app

| # | Screen | Bedrock job | Route | Status |
| --- | --- | --- | --- | --- |
| 1 | Coordinator · each request | Read a request: needs, people, location (runs automatically) | `POST /v1/requests/:id/classify` | **live** |
| 2 | Coordinator · each request | Write the reply from the coordinator's notes, in the resident's language, plus a spoken version | `POST /v1/requests/:id/response-draft` | **live** |
| 3 | Coordinator · public warning | Write the warning per language: notice lines and radio script | `POST /v1/bulletins/draft` | **live** |
| 4 | Coordinator · top panel | Situation brief: rank open requests, flag silent zones | `POST /v1/briefing` | **live** |
| 5 | Volunteer · step 4 | Read a photo of a paper help card | `POST /v1/cards/read` | **live** |
| 6 | Warning drafts | Pictograms chosen by Bedrock | `pictograms` in bulletin output | **live** |

The app defaults to the live `/api` proxy. In-browser fixtures require the
explicit `VITE_MOCK_API=true` flag and are labelled **MOCK AI**.

## Integrated Bedrock contracts

**B1 `POST /v1/briefing`** (coordinator token)
Request: `{ zones: Zone[] }`. The zones are frontend data: `id`, `name`,
`population`, `connectivity`, and `reach: { digital, radio, none }`.
The server sends Bedrock every open request (no `repliedAt`) with its
classification, plus the zones. Response:
```
{ generatedAt, headline,
  priorities: [{ requestId, rank, reason }],          // rank 1 = most urgent; only ids that exist
  zones: [{ incidentId, summary, unmetNeeds: string[], suggestedAction }],
  gaps: string[],    // e.g. "No requests from Old Mill. It has no signal, so silence ≠ safe."
  requiresHumanReview: true, source: "amazon-bedrock", modelId, awsRequestId? }
```

**B2 `POST /v1/cards/read`** (coordinator or device token)
Request: `{ imageBase64, mediaType: "image/jpeg", incidentId }`. The image is
JPEG, at most 1400 px on its longest side, so roughly 200 to 400 KB. It is a
photo of the printable help card (`#/print/card/<zone>`): six tick boxes
(water, food, medical, shelter, evacuation, power), "How many people?",
"Where?" and free space. Response:
```
{ needs: Need[], peopleCount: number | null, locationDescription: string | null,
  notes: string, unreadable: string[],
  requiresHumanReview: true, source: "amazon-bedrock", modelId, awsRequestId? }
```
The volunteer checks the fields, and the app then sends a normal
`help_request` from `paper:<volunteer>` through `/v1/messages/batch`.
Nothing is stored by this route.

**B3 Pictograms in `bulletins/draft`**: add
`pictograms: ("water"|"food"|"medical"|"shelter"|"danger"|"route"|"info")[]`.
The frontend already uses them when present.

## Frontend conventions

- **Zones** are frontend data ([`src/zones.ts`](src/zones.ts)). A zone id is
  sent as `incidentId` on warnings and help requests.
- **Help-request body** is readable text with a header line built from the
  tapped options (`NEEDS: water, medical | PEOPLE: 25`, then the free text).
  Bedrock `classify` reads all of it.
- **Paper help cards** become `help_request` messages from
  `paper:<volunteer>`. Replies go to that id, and the volunteer's phone
  collects them during sync.
- **Reply ids** are `reply-<requestId>` (cut to 64 characters), so a retried
  click can't create a second reply.
- **Answered** means `repliedAt` is set on the record, or this browser has
  sent a reply.
- **Delivery states** follow the README: saved, relayed, uploaded,
  acknowledged.
