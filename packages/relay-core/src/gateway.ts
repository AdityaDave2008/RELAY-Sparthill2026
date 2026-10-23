import { isIdentifier, validateMessage, type RelayMessage } from './message.ts';
import { receive } from './sync.ts';
import type { MessageStore } from './store.ts';

export interface GatewayOptions {
  baseUrl: string;
  deviceId: string;
  token?: string;
  fetch?: typeof globalThis.fetch;
  now?: number;
}
export interface GatewaySyncReport {
  uploadedIds: string[];
  receivedIds: string[];
  rejected: { id: string; reason: string }[];
}

// Relay devices also collect replies for residents whose requests they carry.
// Failed uploads stay pending; only explicit server receipts clear the queue.
export async function syncWithGateway(store: MessageStore, options: GatewayOptions): Promise<GatewaySyncReport> {
  if (!isIdentifier(options.deviceId)) throw new TypeError('Invalid device ID');
  const base = new URL(options.baseUrl.endsWith('/') ? options.baseUrl : options.baseUrl + '/');
  if (!['http:', 'https:'].includes(base.protocol)) throw new TypeError('Invalid API URL');
  const fetcher = options.fetch ?? globalThis.fetch;
  const now = options.now ?? Date.now();
  const report: GatewaySyncReport = { uploadedIds: [], receivedIds: [], rejected: [] };
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (options.token) headers.Authorization = `Bearer ${options.token}`;

  const json = async (path: string, init?: RequestInit): Promise<any> => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15_000);
    try {
      const response = await fetcher(new URL(path, base), { ...init, headers, signal: controller.signal });
      if (!response.ok) throw new Error(`Gateway request failed (${response.status})`);
      return await response.json();
    } finally { clearTimeout(timer); }
  };

  for (const messages of chunks(store.pendingUpload(now), 50)) {
    const result = await json('v1/messages/batch', { method: 'POST', body: JSON.stringify({ deviceId: options.deviceId, messages }) });
    const sent = new Set(messages.map(m => m.id));
    if (!result || !Array.isArray(result.acceptedIds) || result.acceptedIds.some((id: unknown) => typeof id !== 'string' || !sent.has(id)) ||
        !Array.isArray(result.rejected) || result.rejected.some((r: any) => !r || !sent.has(r.id) || typeof r.reason !== 'string')) {
      throw new TypeError('Invalid upload receipt');
    }
    store.markUploaded(result.acceptedIds);
    report.uploadedIds.push(...result.acceptedIds);
    report.rejected.push(...result.rejected);
  }

  const recipients = new Set([options.deviceId, ...store.list().filter(m => m.kind === 'help_request' && m.expiresAt > now).map(m => m.originDeviceId)]);
  for (const deviceId of recipients) {
    let cursor: string | null = null;
    const seen = new Set<string>();
    for (let page = 0; page < 100; page++) {
      const query = new URLSearchParams({ deviceId, limit: '50', ...(cursor ? { cursor } : {}) });
      const result = await json(`v1/messages?${query}`);
      if (!result || !Array.isArray(result.messages) || result.messages.length > 50 ||
          result.messages.some((m: unknown) => validateMessage(m).length > 0) ||
          (result.nextCursor !== null && typeof result.nextCursor !== 'string')) throw new TypeError('Invalid delivery response');
      const messages = result.messages as RelayMessage[];
      if (messages.some(m => m.kind !== 'warning' && !(m.kind === 'ack' && m.recipientDeviceId === deviceId))) {
        throw new TypeError('Gateway returned a message for another recipient');
      }
      const received = receive(store, { messages }, now);
      const accepted = [...received.added, ...received.rejected.filter(r => r.reason === 'duplicate').map(r => r.id)];
      store.markUploaded(accepted);
      report.receivedIds.push(...received.added);
      report.rejected.push(...received.rejected.filter(r => r.reason !== 'duplicate'));
      cursor = result.nextCursor;
      if (cursor === null) break;
      if (!cursor || seen.has(cursor) || page === 99) throw new Error('Invalid or excessive gateway pagination');
      seen.add(cursor);
    }
  }
  return report;
}

function chunks<T>(items: T[], size: number): T[][] {
  return Array.from({ length: Math.ceil(items.length / size) }, (_, i) => items.slice(i * size, (i + 1) * size));
}
