import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { validateMessage, type RelayMessage } from '@relay/core';

export const NEEDS = ['water', 'food', 'medical', 'shelter', 'evacuation', 'power', 'other'] as const;
export interface Classification {
  needs: (typeof NEEDS)[number][];
  peopleCount: number | null;
  locationDescription: string | null;
  summary: string;
  requiresHumanReview: true;
  source: 'amazon-bedrock';
  modelId: string;
  awsRequestId?: string;
}
export interface RequestRecord {
  message: RelayMessage;
  receivedAt: number;
  classification?: Classification;
  repliedAt?: number;
}
export interface PageOptions {
  limit: number;
  afterId?: string;
  now: number;
  kind?: 'help_request';
  recipientDeviceId?: string;
}
export interface RecordPage { records: RequestRecord[]; afterId: string | null }
export interface Repository {
  readonly kind: 'file' | 'dynamodb';
  get(id: string): Promise<RequestRecord | undefined>;
  putIfAbsent(record: RequestRecord): Promise<boolean>;
  classify(id: string, classification: Classification, now: number): Promise<RequestRecord | undefined>;
  markReplied(id: string, repliedAt: number): Promise<void>;
  page(options: PageOptions): Promise<RecordPage>;
}

export function visible(record: RequestRecord, options: PageOptions): boolean {
  const m = record.message;
  if (m.expiresAt <= options.now) return false;
  if (options.kind) return m.kind === options.kind;
  return m.kind === 'warning' || (m.kind === 'ack' && m.recipientDeviceId === options.recipientDeviceId);
}

// Single-process local development storage. Persist an atomic snapshot before
// acknowledging writes; AWS uses conditional DynamoDB writes instead.
export class FileRepository implements Repository {
  readonly kind = 'file' as const;
  private records = new Map<string, RequestRecord>();
  private path: string;

  constructor(path: string) {
    this.path = resolve(path);
    if (!existsSync(this.path)) return;
    const data = JSON.parse(readFileSync(this.path, 'utf8'));
    if (data?.version !== 1 || !Array.isArray(data.records) || data.records.length > 10_000 ||
        data.records.some((r: RequestRecord) => !r || validateMessage(r.message).length > 0 || !Number.isSafeInteger(r.receivedAt))) {
      throw new Error('Invalid API data file; preserve it for recovery');
    }
    for (const record of data.records as RequestRecord[]) {
      if (this.records.has(record.message.id)) throw new Error('Duplicate message ID in API data file');
      this.records.set(record.message.id, record);
    }
  }

  async get(id: string): Promise<RequestRecord | undefined> {
    const record = this.records.get(id);
    return record && structuredClone(record);
  }

  async putIfAbsent(record: RequestRecord): Promise<boolean> {
    if (this.records.has(record.message.id)) return false;
    const next = new Map(this.records);
    // This local demo store is bounded. Expired records can be removed safely.
    for (const [id, value] of next) if (value.message.expiresAt <= record.receivedAt) next.delete(id);
    if (next.size >= 10_000) throw new Error('API data store capacity reached');
    next.set(record.message.id, structuredClone(record));
    this.commit(next);
    return true;
  }

  async classify(id: string, classification: Classification, now: number): Promise<RequestRecord | undefined> {
    const record = this.records.get(id);
    if (!record || record.message.expiresAt <= now) return undefined;
    const updated = { ...record, classification: structuredClone(classification) };
    const next = new Map(this.records);
    next.set(id, updated);
    this.commit(next);
    return structuredClone(updated);
  }

  async page(options: PageOptions): Promise<RecordPage> {
    const sorted = [...this.records.values()].sort((a, b) => a.message.id < b.message.id ? -1 : a.message.id > b.message.id ? 1 : 0)
      .filter(r => !options.afterId || r.message.id > options.afterId);
    const evaluated = sorted.slice(0, options.limit);
    return {
      records: evaluated.filter(r => visible(r, options)).map(r => structuredClone(r)),
      afterId: sorted.length > evaluated.length ? evaluated.at(-1)!.message.id : null,
    };
  }

  async markReplied(id: string, repliedAt: number): Promise<void> {
    const record = this.records.get(id);
    if (!record) throw new Error('Help request not found');
    if (record.repliedAt !== undefined) return;
    const next = new Map(this.records);
    next.set(id, { ...record, repliedAt });
    this.commit(next);
  }

  private commit(records: Map<string, RequestRecord>): void {
    mkdirSync(dirname(this.path), { recursive: true });
    const temporary = `${this.path}.${crypto.randomUUID()}.tmp`;
    let descriptor: number | undefined;
    try {
      descriptor = openSync(temporary, 'wx', 0o600);
      writeFileSync(descriptor, JSON.stringify({ version: 1, records: [...records.values()] }));
      fsyncSync(descriptor);
      closeSync(descriptor); descriptor = undefined;
      renameSync(temporary, this.path);
      this.records = records;
    } catch (error) {
      if (descriptor !== undefined) closeSync(descriptor);
      if (existsSync(temporary)) unlinkSync(temporary);
      throw error;
    }
  }
}
