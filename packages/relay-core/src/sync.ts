import { canForward, type RelayMessage } from './message.ts';
import type { AddResult, MessageStore } from './store.ts';

// Transport-agnostic store-and-forward exchange between two nearby devices.
// The transport (Bluetooth LE, Wi-Fi Direct, Multipeer, or a test harness)
// only has to carry these JSON payloads:
//
//   A -> B  offer(A)               ids A can forward
//   B -> A  request(B, offer)      ids B is missing
//   A -> B  fulfil(A, request)     the messages, hop count incremented
//   B       receive(B, batch)      validate, dedupe, store

export interface Offer {
  ids: string[];
}

export interface Request {
  ids: string[];
}

export interface Batch {
  messages: RelayMessage[];
}

export interface ReceiveReport {
  added: string[];
  rejected: { id: string; reason: Exclude<AddResult, 'added'> }[];
}

export function offer(store: MessageStore, now: number = Date.now()): Offer {
  return { ids: store.list().filter((m) => canForward(m, now)).map((m) => m.id) };
}

export function request(store: MessageStore, incoming: Offer, limit: number = 50): Request {
  if (!Number.isInteger(limit) || limit < 0 || limit > 50) throw new RangeError('request limit must be 0 to 50');
  if (!incoming || !Array.isArray(incoming.ids) || incoming.ids.length > 10_000 || incoming.ids.some(id => typeof id !== 'string')) throw new TypeError('Invalid offer');
  return { ids: [...new Set(incoming.ids)].filter((id) => !store.has(id)).slice(0, limit) };
}

export function fulfil(store: MessageStore, req: Request, now: number = Date.now()): Batch {
  if (!req || !Array.isArray(req.ids) || req.ids.length > 50 || req.ids.some(id => typeof id !== 'string')) throw new TypeError('Invalid request');
  const messages: RelayMessage[] = [];
  for (const id of new Set(req.ids)) {
    const message = store.get(id);
    if (message && canForward(message, now)) {
      messages.push({ ...structuredClone(message), hops: message.hops + 1 });
    }
  }
  return { messages };
}

export function receive(store: MessageStore, batch: Batch, now: number = Date.now()): ReceiveReport {
  if (!batch || !Array.isArray(batch.messages) || batch.messages.length > 50) throw new TypeError('Invalid batch');
  const report: ReceiveReport = { added: [], rejected: [] };
  for (const message of batch.messages) {
    const result = store.add(message, now);
    if (result === 'added') report.added.push(message.id);
    else report.rejected.push({ id: message?.id ?? '', reason: result });
  }
  return report;
}

// Runs a full two-way exchange between two in-process stores. Useful for
// tests and the demo simulator; real devices run the four steps over a link.
export function exchange(
  a: MessageStore,
  b: MessageStore,
  options: { limit?: number; now?: number } = {},
): { aToB: ReceiveReport; bToA: ReceiveReport } {
  const now = options.now ?? Date.now();
  const oneWay = (from: MessageStore, to: MessageStore) =>
    receive(to, fulfil(from, request(to, offer(from, now), options.limit), now), now);
  return { aToB: oneWay(a, b), bToA: oneWay(b, a) };
}
