// The resident's phone: its core MessageStore, delivery tracking, and the
// upload/download loop that runs whenever the API is reachable.
//
// Integration points for the transport (Codex):
//   device.store            the shared @relay/core MessageStore
//   device.commit()         call after changing the store, so it saves and the UI updates
//   device.recordRelay(...) call after handing messages to a nearby device
import { useSyncExternalStore } from 'react';
import { createMessage, MessageStore, type GeoPoint } from '@relay/core';
import { api } from '../api/index.ts';
import { formatRequestBody, toIdentifier, type DeliveryState, type Lang, type Need, type WireMessage } from '../contract.ts';

const KEY = 'relay.device.v1';

interface Persisted {
  deviceId: string;
  zoneId: string;
  lang: Lang;
  store: ReturnType<MessageStore['toJSON']>;
  relays: Record<string, { at: number; peers: string[] }>;
  uploadedAt: Record<string, number>;
  seen: string[];
}

export interface SyncStatus {
  online: boolean;
  syncing: boolean;
  lastSuccess: number | null;
  lastError: string | null;
}

function readPersisted(): Persisted | null {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Persisted) : null;
  } catch {
    return null;
  }
}

class Device {
  deviceId: string;
  zoneId: string;
  lang: Lang;
  store: MessageStore;
  sync: SyncStatus = { online: navigator.onLine, syncing: false, lastSuccess: null, lastError: null };
  private relays: Persisted['relays'];
  private uploadedAt: Persisted['uploadedAt'];
  private seen: Set<string>;
  private listeners = new Set<() => void>();
  private version = 0;
  loadError: string | null = null;
  private retryMs = 5_000;
  private timer: ReturnType<typeof setTimeout> | undefined;

  constructor() {
    const p = readPersisted();
    this.deviceId = p?.deviceId ?? `phone-${crypto.randomUUID().slice(0, 8)}`;
    this.zoneId = p?.zoneId ?? 'north-hills';
    this.lang = p?.lang ?? 'en';
    this.store = new MessageStore();
    if (p) {
      try {
        this.store = MessageStore.fromJSON(p.store);
      } catch {
        this.loadError = 'Saved messages on this phone could not be read.';
      }
    }
    this.relays = p?.relays ?? {};
    this.uploadedAt = p?.uploadedAt ?? {};
    this.seen = new Set(p?.seen ?? []);
  }

  subscribe = (fn: () => void) => {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  };

  getVersion = () => this.version;

  commit(): void {
    try {
      const data: Persisted = {
        deviceId: this.deviceId,
        zoneId: this.zoneId,
        lang: this.lang,
        store: this.store.toJSON(),
        relays: this.relays,
        uploadedAt: this.uploadedAt,
        seen: [...this.seen],
      };
      localStorage.setItem(KEY, JSON.stringify(data));
    } catch {
      // Private mode or full storage: keep working in memory.
    }
    this.version++;
    for (const fn of this.listeners) fn();
  }

  setPrefs(prefs: { zoneId?: string; lang?: Lang }): void {
    if (prefs.zoneId) this.zoneId = prefs.zoneId;
    if (prefs.lang) this.lang = prefs.lang;
    this.commit();
    void this.syncNow();
  }

  createHelpRequest(input: { needs: Need[]; people: number | null; notes: string; location?: GeoPoint }): WireMessage {
    const message: WireMessage = {
      ...createMessage({
        kind: 'help_request',
        originDeviceId: this.deviceId,
        body: formatRequestBody(input.needs, input.people, input.notes),
        location: input.location,
      }),
      incidentId: this.zoneId,
    };
    this.store.add(message);
    this.commit();
    void this.syncNow();
    return message;
  }

  // A volunteer types in a paper help card. It is stored and carried like any
  // other request, so it can travel offline from the volunteer's phone.
  addPaperRequest(input: { zoneId: string; volunteer: string; needs: Need[]; people: number | null; notes: string }): WireMessage {
    const message: WireMessage = {
      ...createMessage({
        kind: 'help_request',
        originDeviceId: toIdentifier('paper', input.volunteer),
        body: formatRequestBody(input.needs, input.people, input.notes),
      }),
      incidentId: input.zoneId,
    };
    this.store.add(message);
    this.commit();
    void this.syncNow();
    return message;
  }

  paperRequests(): WireMessage[] {
    return (this.store.list() as WireMessage[])
      .filter((m) => m.kind === 'help_request' && m.originDeviceId.startsWith('paper:'))
      .sort((a, b) => b.createdAt - a.createdAt);
  }

  recordRelay(ids: string[], peerId: string): void {
    const at = Date.now();
    for (const id of ids) {
      const entry = (this.relays[id] ??= { at, peers: [] });
      if (!entry.peers.includes(peerId)) entry.peers.push(peerId);
    }
    this.commit();
  }

  markSeen(ids: string[]): void {
    let changed = false;
    for (const id of ids) if (!this.seen.has(id)) (this.seen.add(id), (changed = true));
    if (changed) this.commit();
  }

  isSeen(id: string): boolean {
    return this.seen.has(id);
  }

  mine(): WireMessage[] {
    return this.store
      .list()
      .filter((m) => m.kind === 'help_request' && m.originDeviceId === this.deviceId)
      .sort((a, b) => b.createdAt - a.createdAt) as WireMessage[];
  }

  warnings(): WireMessage[] {
    return (this.store.list() as WireMessage[])
      .filter((m) => m.kind === 'warning' && (!m.incidentId || m.incidentId === this.zoneId))
      .sort((a, b) => b.priority - a.priority || b.createdAt - a.createdAt);
  }

  ackFor(id: string): WireMessage | undefined {
    return (this.store.list() as WireMessage[]).find((m) => m.kind === 'ack' && m.replyTo === id);
  }

  delivery(id: string): { state: DeliveryState; times: Partial<Record<DeliveryState, number>>; peers: number } {
    const message = this.store.get(id);
    const ack = this.ackFor(id);
    const times: Partial<Record<DeliveryState, number>> = { saved: message?.createdAt };
    if (this.relays[id]) times.relayed = this.relays[id].at;
    if (this.uploadedAt[id]) times.uploaded = this.uploadedAt[id];
    if (ack) times.acknowledged = ack.createdAt;
    const state: DeliveryState = ack ? 'acknowledged' : this.uploadedAt[id] ? 'uploaded' : this.relays[id] ? 'relayed' : 'saved';
    return { state, times, peers: this.relays[id]?.peers.length ?? 0 };
  }

  pendingCount(): number {
    return this.uploadable().length;
  }

  private uploadable(): WireMessage[] {
    return this.store.pendingUpload().filter((m) => m.kind === 'help_request' || m.kind === 'status') as WireMessage[];
  }

  setOnline(online: boolean): void {
    this.sync = { ...this.sync, online };
    this.commit();
    if (online) void this.syncNow();
  }

  // Upload anything waiting (this device's and relayed-in messages), then
  // download warnings and replies, including replies for residents whose
  // requests this phone is carrying. Retries with backoff on failure.
  // Mirrors syncWithGateway() in @relay/core; switch to it once merged.
  syncNow = async (): Promise<void> => {
    clearTimeout(this.timer);
    if (this.sync.syncing) return;
    if (!navigator.onLine) {
      this.sync = { ...this.sync, online: false };
      this.commit();
      return;
    }
    this.sync = { ...this.sync, syncing: true, online: true };
    this.commit();
    try {
      const pending = this.uploadable();
      for (let i = 0; i < pending.length; i += 50) {
        const { acceptedIds } = await api.uploadBatch(this.deviceId, pending.slice(i, i + 50));
        const now = Date.now();
        for (const id of acceptedIds) this.uploadedAt[id] ??= now;
        this.store.markUploaded(acceptedIds);
      }
      const recipients = new Set([this.deviceId, ...this.store.list().filter((m) => m.kind === 'help_request').map((m) => m.originDeviceId)]);
      for (const recipient of recipients) {
        let cursor: string | null = null;
        for (let page = 0; page < 20; page++) {
          const res: { messages: WireMessage[]; nextCursor: string | null } = await api.fetchMessages(recipient, cursor);
          for (const m of res.messages) this.store.add(m);
          // Downloaded messages came from the server; don't upload them back.
          this.store.markUploaded(res.messages.map((m) => m.id));
          cursor = res.nextCursor;
          if (!cursor) break;
        }
      }
      this.retryMs = 5_000;
      this.sync = { ...this.sync, syncing: false, lastSuccess: Date.now(), lastError: null };
      this.timer = setTimeout(this.syncNow, 15_000);
    } catch (err) {
      this.sync = { ...this.sync, syncing: false, lastError: err instanceof Error ? err.message : String(err) };
      this.timer = setTimeout(this.syncNow, this.retryMs);
      this.retryMs = Math.min(this.retryMs * 2, 60_000);
    }
    this.commit();
  };

  resetForDemo(): void {
    localStorage.removeItem(KEY);
    location.reload();
  }
}

export const device = new Device();

window.addEventListener('online', () => device.setOnline(true));
window.addEventListener('offline', () => device.setOnline(false));

export function useDevice(): Device {
  useSyncExternalStore(device.subscribe, device.getVersion);
  return device;
}
