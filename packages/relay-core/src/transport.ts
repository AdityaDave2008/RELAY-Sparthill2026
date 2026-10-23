import { isIdentifier } from './message.ts';
import { fulfil, offer, receive, type ReceiveReport } from './sync.ts';
import type { MessageStore } from './store.ts';

const CHUNK_BYTES = 720;
const MAX_BYTES = 65_536;
const MAX_FRAMES = Math.ceil(MAX_BYTES / CHUNK_BYTES);
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });
interface Frame { protocol: 'relay'; version: 1; transferId: string; checksum: string; index: number; total: number; data: string }
interface Pending { checksum: string; total: number; updatedAt: number; chunks: Map<number, Uint8Array> }

async function checksum(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', Uint8Array.from(bytes).buffer);
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

// Text frames can travel over QR or any text-capable link. Hops increment only
// on the outgoing copy; the sender's stored message remains intact.
export async function encodeTransfer(store: MessageStore, options: { ids?: string[]; now?: number } = {}): Promise<string[]> {
  const now = options.now ?? Date.now();
  const ids = options.ids ?? offer(store, now).ids.slice(0, 50);
  const batch = fulfil(store, { ids }, now);
  if (!batch.messages.length) return [];
  const bytes = encoder.encode(JSON.stringify(batch));
  if (bytes.length > MAX_BYTES) throw new RangeError('Transfer exceeds 64 KiB; select fewer messages');
  const hash = await checksum(bytes);
  const transferId = crypto.randomUUID();
  const total = Math.ceil(bytes.length / CHUNK_BYTES);
  return Array.from({ length: total }, (_, index) => {
    const chunk = bytes.subarray(index * CHUNK_BYTES, (index + 1) * CHUNK_BYTES);
    return JSON.stringify({ protocol: 'relay', version: 1, transferId, checksum: hash,
      index, total, data: btoa(String.fromCharCode(...chunk)) } satisfies Frame);
  });
}

export type TransferProgress = { complete: false; received: number; total: number } |
  { complete: true; received: number; total: number; report: ReceiveReport };

export class TransferReceiver {
  private pending = new Map<string, Pending>();
  private store: MessageStore;
  private now: () => number;

  constructor(store: MessageStore, options: { now?: () => number } = {}) {
    this.store = store;
    this.now = options.now ?? Date.now;
  }

  async accept(text: string): Promise<TransferProgress> {
    if (typeof text !== 'string' || encoder.encode(text).length > 1600) throw new TypeError('Invalid transfer frame');
    const frame = JSON.parse(text) as Frame;
    if (!frame || frame.protocol !== 'relay' || frame.version !== 1 || !isIdentifier(frame.transferId) ||
        typeof frame.checksum !== 'string' || !/^[a-f0-9]{64}$/.test(frame.checksum) ||
        !Number.isInteger(frame.total) || frame.total < 1 || frame.total > MAX_FRAMES ||
        !Number.isInteger(frame.index) || frame.index < 0 || frame.index >= frame.total || typeof frame.data !== 'string' ||
        frame.data.length > 960 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(frame.data)) {
      throw new TypeError('Invalid transfer frame');
    }
    const now = this.now();
    for (const [id, transfer] of this.pending) if (now - transfer.updatedAt > 120_000) this.pending.delete(id);
    let transfer = this.pending.get(frame.transferId);
    if (!transfer) {
      if (this.pending.size >= 8) throw new RangeError('Too many incomplete transfers');
      transfer = { checksum: frame.checksum, total: frame.total, updatedAt: now, chunks: new Map() };
      this.pending.set(frame.transferId, transfer);
    }
    if (transfer.total !== frame.total || transfer.checksum !== frame.checksum) throw new TypeError('Conflicting transfer frames');
    const chunk = Uint8Array.from(atob(frame.data), char => char.charCodeAt(0));
    const previous = transfer.chunks.get(frame.index);
    if (previous && (previous.length !== chunk.length || previous.some((value, index) => value !== chunk[index]))) {
      throw new TypeError('Conflicting transfer frame contents');
    }
    transfer.chunks.set(frame.index, chunk);
    transfer.updatedAt = now;
    if (transfer.chunks.size < transfer.total) return { complete: false, received: transfer.chunks.size, total: transfer.total };

    this.pending.delete(frame.transferId);
    const length = [...transfer.chunks.values()].reduce((sum, item) => sum + item.length, 0);
    if (length > MAX_BYTES) throw new RangeError('Transfer exceeds 64 KiB');
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (let index = 0; index < transfer.total; index++) {
      const item = transfer.chunks.get(index)!;
      bytes.set(item, offset); offset += item.length;
    }
    if (await checksum(bytes) !== transfer.checksum) throw new TypeError('Transfer checksum mismatch');
    const batch = JSON.parse(decoder.decode(bytes));
    const report = receive(this.store, batch, now);
    return { complete: true, received: transfer.total, total: transfer.total, report };
  }
}
