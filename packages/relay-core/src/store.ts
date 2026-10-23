import { compareByImportance, isExpired, validateMessage, type RelayMessage } from './message.ts';

export type AddResult = 'added' | 'duplicate' | 'expired' | 'invalid' | 'rejected_full';

// Offline message storage on one device. In-memory for now; the app can
// persist it with toJSON()/fromJSON() until a SQLite-backed store is added.
export class MessageStore {
  readonly capacity: number;
  private readonly messages = new Map<string, RelayMessage>();
  private readonly uploaded = new Set<string>();

  constructor(options: { capacity?: number } = {}) {
    this.capacity = options.capacity ?? 500;
  }

  get size(): number {
    return this.messages.size;
  }

  has(id: string): boolean {
    return this.messages.has(id);
  }

  get(id: string): RelayMessage | undefined {
    return this.messages.get(id);
  }

  add(message: RelayMessage, now: number = Date.now()): AddResult {
    if (validateMessage(message).length > 0) return 'invalid';
    if (this.messages.has(message.id)) return 'duplicate';
    if (isExpired(message, now)) return 'expired';

    this.prune(now);
    if (this.messages.size >= this.capacity) {
      const leastImportant = this.list().at(-1)!;
      // Never push out something more important than the incoming message.
      if (compareByImportance(message, leastImportant) > 0) return 'rejected_full';
      this.delete(leastImportant.id);
    }
    this.messages.set(message.id, structuredClone(message));
    return 'added';
  }

  // All live messages, most important first.
  list(): RelayMessage[] {
    return [...this.messages.values()].sort(compareByImportance);
  }

  prune(now: number = Date.now()): number {
    let removed = 0;
    for (const message of this.messages.values()) {
      if (isExpired(message, now)) {
        this.delete(message.id);
        removed++;
      }
    }
    return removed;
  }

  // Messages not yet sent to AWS, for when a connection is available.
  pendingUpload(now: number = Date.now()): RelayMessage[] {
    return this.list().filter((m) => !this.uploaded.has(m.id) && !isExpired(m, now));
  }

  markUploaded(ids: Iterable<string>): void {
    for (const id of ids) {
      if (this.messages.has(id)) this.uploaded.add(id);
    }
  }

  toJSON(): { messages: RelayMessage[]; uploaded: string[] } {
    return { messages: this.list(), uploaded: [...this.uploaded] };
  }

  static fromJSON(
    data: { messages: RelayMessage[]; uploaded?: string[] },
    options: { capacity?: number; now?: number } = {},
  ): MessageStore {
    const store = new MessageStore(options);
    for (const message of data.messages) store.add(message, options.now);
    store.markUploaded(data.uploaded ?? []);
    return store;
  }

  private delete(id: string): void {
    this.messages.delete(id);
    this.uploaded.delete(id);
  }
}
