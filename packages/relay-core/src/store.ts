import { compareByImportance, isExpired, sameMessage, validateMessage, type RelayMessage } from './message.ts';

export type AddResult = 'added' | 'duplicate' | 'conflict' | 'expired' | 'invalid' | 'rejected_full';
export interface StoreSnapshot { messages: RelayMessage[]; uploaded: string[] }
export interface SnapshotPersistence {
  read(): string | null;
  write(snapshot: string): void;
}

// Persist before changing memory. A failed write must not be reported as saved.
export class MessageStore {
  readonly capacity: number;
  private messages = new Map<string, RelayMessage>();
  private uploaded = new Set<string>();
  private persistence?: SnapshotPersistence;

  constructor(options: { capacity?: number } = {}) {
    this.capacity = options.capacity ?? 500;
    if (!Number.isSafeInteger(this.capacity) || this.capacity < 1 || this.capacity > 10_000) {
      throw new RangeError('capacity must be an integer from 1 to 10000');
    }
  }

  static open(persistence: SnapshotPersistence, options: { capacity?: number; now?: number } = {}): MessageStore {
    const saved = persistence.read();
    const store = saved === null ? new MessageStore(options) : MessageStore.fromJSON(JSON.parse(saved), options);
    store.persistence = persistence;
    return store;
  }

  get size(): number { return this.messages.size; }
  has(id: string): boolean { return this.messages.has(id); }
  get(id: string): RelayMessage | undefined {
    const message = this.messages.get(id);
    return message && structuredClone(message);
  }

  add(message: RelayMessage, now: number = Date.now()): AddResult {
    if (validateMessage(message).length > 0) return 'invalid';
    if (isExpired(message, now)) return 'expired';
    const existing = this.messages.get(message.id);
    if (existing) return sameMessage(existing, message) ? 'duplicate' : 'conflict';
    const messages = new Map([...this.messages].filter(([, m]) => !isExpired(m, now)));
    if (messages.size >= this.capacity) {
      const leastImportant = [...messages.values()].sort(compareByImportance).at(-1)!;
      if (compareByImportance(message, leastImportant) > 0) return 'rejected_full';
      messages.delete(leastImportant.id);
    }
    messages.set(message.id, structuredClone(message));
    this.commit(messages);
    return 'added';
  }

  list(): RelayMessage[] {
    return [...this.messages.values()].sort(compareByImportance).map(m => structuredClone(m));
  }

  prune(now: number = Date.now()): number {
    const messages = new Map([...this.messages].filter(([, m]) => !isExpired(m, now)));
    const removed = this.messages.size - messages.size;
    if (removed) this.commit(messages);
    return removed;
  }

  pendingUpload(now: number = Date.now()): RelayMessage[] {
    return this.list().filter(m => !this.uploaded.has(m.id) && !isExpired(m, now));
  }

  markUploaded(ids: Iterable<string>): void {
    const uploaded = new Set(this.uploaded);
    for (const id of ids) if (this.messages.has(id)) uploaded.add(id);
    if (uploaded.size !== this.uploaded.size) this.commit(new Map(this.messages), uploaded);
  }

  toJSON(): StoreSnapshot { return { messages: this.list(), uploaded: [...this.uploaded] }; }

  static fromJSON(data: unknown, options: { capacity?: number; now?: number } = {}): MessageStore {
    if (!data || typeof data !== 'object') throw new TypeError('Invalid store snapshot');
    const snapshot = data as Partial<StoreSnapshot>;
    if (!Array.isArray(snapshot.messages) || snapshot.messages.length > 10_000 ||
        snapshot.messages.some(m => validateMessage(m).length > 0) ||
        (snapshot.uploaded !== undefined && (!Array.isArray(snapshot.uploaded) || snapshot.uploaded.some(id => typeof id !== 'string')))) {
      throw new TypeError('Invalid store snapshot');
    }
    const store = new MessageStore(options);
    for (const message of snapshot.messages) {
      if (store.add(message, options.now) === 'conflict') throw new TypeError('Conflicting IDs in store snapshot');
    }
    store.markUploaded(snapshot.uploaded ?? []);
    return store;
  }

  private commit(messages: Map<string, RelayMessage>, uploaded = this.uploaded): void {
    const nextUploaded = new Set([...uploaded].filter(id => messages.has(id)));
    this.persistence?.write(JSON.stringify({ messages: [...messages.values()], uploaded: [...nextUploaded] }));
    this.messages = messages;
    this.uploaded = nextUploaded;
  }
}

export function localStoragePersistence(storage: Pick<Storage, 'getItem' | 'setItem'>, key = 'relay:messages'): SnapshotPersistence {
  return { read: () => storage.getItem(key), write: snapshot => storage.setItem(key, snapshot) };
}
