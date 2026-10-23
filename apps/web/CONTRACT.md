# RELAY shared contract: proposal v0.1

Status: **proposed by Claude (frontend), waiting for Codex (core + API) to review.**
Source of truth for the types: [`src/contract.ts`](src/contract.ts). If you
change something, edit this file and that one together, and bump the version.

## 1. Message (on the device and on the wire)

The base is `RelayMessage` from `packages/relay-core`. `validateMessage()`
ignores unknown fields, so these optional fields can travel today without a
core change. Codex, please add them to core so they are validated:

| Field | Type | Used by |
| --- | --- | --- |
| `title` | string ≤ 120 | warnings: the short headline shown on the lock screen and the printed notice |
| `zoneId` | string | warnings: the target zone. help_request: the zone the sender picked |
| `translations` | `Record<lang, { title, body }>` | warnings: versions drafted by Bedrock and approved by a coordinator |
| `channel` | `'app' \| 'paper' \| 'radio'` | how a help_request entered the system (paper = entered by a volunteer from a card) |
| `sig` | string (base64) | KMS signature over the canonical message, checked offline |

### Help request body

Kept as **human-readable text** on purpose. The resident (or a volunteer
copying a paper card) writes freely, and Bedrock turns it into structured data
on the server. The app adds a header line built from the tapped options:

```
NEEDS: water, medical | PEOPLE: 25
We have 25 people at the church and running out of drinking water. One diabetic.
```

### Acknowledgement

A coordinator reply is a normal message: `kind: 'ack'`, `replyTo: <request id>`,
`originDeviceId: 'coordinator:<zone>'`, with the reply text in `body`. It goes
back to the device the same way a warning does, over the API when online or
relayed peer to peer when offline.

## 2. Delivery states (resident sees these)

| State | Meaning | Who sets it |
| --- | --- | --- |
| `saved` | stored on this device (survives a restart) | frontend on create |
| `relayed` | handed to at least one nearby device | transport (Codex) calls `recordRelay(ids, peerId)` |
| `uploaded` | API accepted it (`accepted` or `duplicate`) | upload loop after `POST /v1/messages:batch` |
| `acknowledged` | an `ack` with `replyTo = id` is in the device store | derived from the store |

The states only move forward. A device may jump from `saved` straight to
`acknowledged` if the ack comes back offline before this device ever uploads.

## 3. HTTP API (`services/api`, owned by Codex)

Base URL comes from `VITE_API_URL`. All bodies are JSON. Each error has the form
`{ error: { code, message } }`.

| Method & path | Request | Response |
| --- | --- | --- |
| `POST /v1/messages:batch` | `{ deviceId, messages: RelayMessage[] }` | `{ results: [{ id, status: 'accepted'\|'duplicate'\|'rejected', reason? }] }` |
| `GET /v1/messages?since=<ms>&zoneId=` | — | `{ messages: RelayMessage[], now }` approved warnings and acks for download |
| `GET /v1/zones` | — | `{ zones: Zone[] }` |
| `GET /v1/requests?status=` | — | `{ requests: RequestRecord[] }` |
| `POST /v1/requests/{id}/ack` | `{ body }` | `{ ack: RelayMessage }` |
| `POST /v1/warnings/draft` | `{ rawReport, zoneId, languages: string[] }` | `{ draft: WarningDraft }` (**Bedrock**) |
| `POST /v1/warnings/{draftId}/approve` | `{ approver, edits?: {title, body} }` | `{ warning: RelayMessage }` (signed). Approval is **simulated** in the demo |
| `POST /v1/paper-responses` | `PaperResponse` | `{ request: RelayMessage }` |

`RequestRecord` = the original message plus `bedrock: StructuredRequest | null`
(null while Bedrock is still running) and `status: 'new' | 'acknowledged'`.

### What Bedrock must return (structured output)

- `StructuredRequest`: `{ needs: Need[], peopleCount: number | null, urgency: 'critical'|'high'|'normal', summary, locationText, uncertain: string[], model }`
- `WarningDraft`: `{ id, title, body, translations, pictograms: Pictogram[], facts: string[], uncertain: string[], radioScript, model }`

`model` holds the Bedrock model id, so the dashboard can show it. That is
what proves Bedrock is in use in the video.

## 4. Simulated government workflow

Approving a warning is a **simulation**. Every screen that shows it says so.
No real agency, alerting system, or emergency number is contacted.
