# @relay/core

The offline messaging core of RELAY: the message format, on-device storage,
and the store-and-forward exchange that moves messages between nearby phones
without a network. It has no dependencies or UI. The app can use its text
transport frames and HTTP gateway helper without bundling AWS credentials.

```sh
cd packages/relay-core
npm test   # Node >= 22.18 runs the TypeScript directly
```

## Message

| Field | Notes |
| --- | --- |
| `kind` | `help_request` (two-way), `warning` (one-way broadcast), `status`, `ack` (needs `replyTo`) |
| `priority` | 0 to 3. Defaults: help 3, warning and ack 2, status 1 |
| `expiresAt` | Defaults: 24 h, or 12 h for warnings. Expired messages are never stored or forwarded |
| `hops` / `maxHops` | Each forward adds a hop. Forwarding stops at `maxHops` (default 8) |
| `location` | Optional `{ lat, lon, accuracyM }` |

Create messages with `createMessage()`. Check anything that arrives from
another device with `validateMessage()`; `MessageStore.add()` already does this.

## Storage

`MessageStore` removes duplicates by `id`, drops expired messages, and has a
capacity limit. When it is full, it removes the least important message, but
never one more important than the message arriving. `pendingUpload()` and
`markUploaded()` form the queue for the AWS uplink. `toJSON()` and
`fromJSON()` support snapshot adapters. `MessageStore.open()` connects a
persistence adapter, including the provided localStorage adapter.

## Sync protocol

A transport only has to carry these four JSON payloads between two devices:

```
A -> B  offer(storeA)              ids A can forward
B -> A  request(storeB, offer)     ids B is missing (default limit 50)
A -> B  fulfil(storeA, request)    messages, with hops + 1
B       receive(storeB, batch)     validates, removes duplicates, stores, reports
```

`exchange(a, b)` runs both directions in one process, for tests and the
demo simulator.

## Remaining platform integrations

- Message signing and authenticity checks. Right now any device can claim
  any `originDeviceId`.
- A device-to-device transport, such as BLE or Wi-Fi Direct through a React
  Native module.
- A native SQLite storage adapter, if required by the eventual native app.

## Frontend integration

`MessageStore.open(localStoragePersistence(localStorage, "relay:device-id"))`
loads durable state. Writes happen before mutations report success; handle
storage exceptions in the UI. Use one active owner for each storage key.

`encodeTransfer(store, { ids? })` returns QR-ready text frames, including
fragmentation for multilingual messages. A `TransferReceiver` accepts frames
in any order, tolerates repeats, validates their checksum, and returns its
actual receive report when complete. The camera and QR renderer belong to
the frontend; a successful software exchange is not a physical-device test.

`syncWithGateway(store, { baseUrl, deviceId, token? })` uploads pending messages
and retrieves approved warnings and replies. Relays retrieve replies for the
original request senders so they can carry them back offline. Retry failures
with the same message IDs; only explicit server receipts clear the outbox.

Warning `title` and `translations` survive storage and transport. Translations
are `{ [languageCode]: { title, body } }`, matching the frontend contract.
Optional `recipientDeviceId` addresses replies, and `incidentId` links warnings
to frontend-owned zones. These fields are included in duplicate conflict checks.

For backend routes and delivery-label semantics, see
[`services/api/README.md`](../../services/api/README.md).
