// Frontend view of the shared contract. The source of truth is
// services/api/README.md (owned by Codex). Frontend-only data and proposed
// additions are marked below and listed in apps/web/CONTRACT.md.
import type { RelayMessage } from '@relay/core';

export type Need = 'water' | 'food' | 'medical' | 'shelter' | 'evacuation' | 'power' | 'other';
export type Pictogram = 'water' | 'food' | 'medical' | 'shelter' | 'danger' | 'route' | 'info';
export type Lang = 'en' | 'es' | 'vi' | 'zh';

export const LANG_LABEL: Record<Lang, string> = {
  en: 'English',
  es: 'Español',
  vi: 'Tiếng Việt',
  zh: '中文',
};

// Optional fields used by the frontend that core does not validate yet
// (proposal P2 in CONTRACT.md). Core keeps unknown fields as they are.
export interface MessageExtras {
  recipientDeviceId?: string;
  incidentId?: string;
  title?: string;
  translations?: Partial<Record<Lang, { title: string; body: string }>>;
}
export type WireMessage = RelayMessage & MessageExtras;

export type DeliveryState = 'saved' | 'relayed' | 'uploaded' | 'acknowledged';
export const DELIVERY_STATES: DeliveryState[] = ['saved', 'relayed', 'uploaded', 'acknowledged'];

// Frontend-owned incident zones. A zone's id is the warning's incidentId.
export interface Zone {
  id: string;
  name: string;
  population: number;
  connectivity: 'online' | 'degraded' | 'offline';
  reach: { digital: number; radio: number; none: number }; // share of residents, 0..1
  x: number; // position on the stylised demo map, 0..100
  y: number;
}

// --- services/api contract -------------------------------------------------

export interface Classification {
  needs: string[];
  peopleCount: number | null;
  locationDescription: string | null;
  summary: string;
  requiresHumanReview: true;
  source: 'amazon-bedrock' | 'mock';
  modelId: string;
}

export interface RequestRecord {
  message: WireMessage;
  receivedAt: number;
  classification?: Classification;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

export interface Health {
  ok: boolean;
  mode: string;
  storage: string;
  bedrockConfigured: boolean;
}

// Language names sent to POST /v1/bulletins/draft.
export const LANG_NAME: Record<Lang, string> = {
  en: 'English',
  es: 'Spanish',
  vi: 'Vietnamese',
  zh: 'Simplified Chinese',
};

// Codex's API returns one BulletinDraft per language; the client merges them
// into this view (see api/http.ts).
export interface BulletinDraft {
  message: string;
  spokenMessage: string;
  noticeTitle: string;
  noticeLines: string[];
  language: string;
  requiresHumanApproval: true;
  source: 'amazon-bedrock';
  modelId: string;
}

export interface WarningDraft {
  title: string;
  body: string;
  noticeLines: string[];
  translations: Partial<Record<Lang, { title: string; body: string }>>;
  pictograms: Pictogram[];
  radioScript: string;
  uncertain: string[];
  source: 'amazon-bedrock' | 'mock';
  modelId: string;
}

export interface RelayApi {
  readonly mode: 'live' | 'mock';
  health(): Promise<Health>;
  uploadBatch(deviceId: string, messages: WireMessage[]): Promise<{ acceptedIds: string[]; rejected: { id: string; reason: string }[] }>;
  fetchMessages(deviceId: string, cursor: string | null): Promise<{ messages: WireMessage[]; nextCursor: string | null }>;
  requests(cursor: string | null): Promise<{ requests: RequestRecord[]; nextCursor: string | null }>;
  classify(requestId: string): Promise<RequestRecord>;
  reply(requestId: string, replyId: string, body: string): Promise<WireMessage>;
  publishWarning(input: { id: string; body: string; incidentId?: string; ttlMs?: number; title?: string; translations?: WarningDraft['translations'] }): Promise<WireMessage>;
  draftWarning(rawReport: string, incidentId: string, languages: Lang[]): Promise<WarningDraft>;
}

// --- Help-request body (frontend convention, see CONTRACT.md) --------------

export function formatRequestBody(needs: Need[], people: number | null, notes: string): string {
  const header = `NEEDS: ${needs.length ? needs.join(', ') : 'unspecified'} | PEOPLE: ${people ?? 'unknown'}`;
  return notes.trim() ? `${header}\n${notes.trim()}` : header;
}

export function parseRequestBody(body: string): { needs: Need[]; people: number | null; notes: string } {
  const [first, ...rest] = body.split('\n');
  const match = /^NEEDS: (.*) \| PEOPLE: (.*)$/.exec(first ?? '');
  if (!match) return { needs: [], people: null, notes: body };
  const needs = match[1] === 'unspecified' ? [] : (match[1].split(', ') as Need[]);
  const people = Number.parseInt(match[2], 10);
  return { needs, people: Number.isFinite(people) ? people : null, notes: rest.join('\n') };
}

// Core identifiers: /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/
export function toIdentifier(prefix: string, label: string): string {
  const slug = label.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '');
  return `${prefix}:${slug || 'anon'}`.slice(0, 64);
}
