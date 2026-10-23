# @relay/core

The offline messaging core of RELAY: the message format, on-device storage,
and the store-and-forward exchange that moves messages between nearby phones
without a network. It has no dependencies and no UI, transport, or AWS code,
so the app, the device-to-device link, and the cloud uplink can all build on it.

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
`fromJSON()` let the app save the store (AsyncStorage or a file) until a
SQLite store is added.

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

## Not done yet (open for whoever picks them up)

- Message signing and authenticity checks. Right now any device can claim
  any `originDeviceId`.
- A device-to-device transport, such as BLE or Wi-Fi Direct through a React
  Native module.
- A Bedrock or Lambda endpoint that receives `pendingUpload()` batches.
- Persistent storage (SQLite).
