// Message model shared by every part of RELAY: the app, peer-to-peer transfer,
// and the AWS uplink. Kept to erasable TypeScript so Node can run it directly.

export type MessageKind =
  | 'help_request' // two-way: someone near the emergency needs help
  | 'warning' // one-way: broadcast to people in the surrounding area
  | 'status' // "I'm safe" / check-in updates
  | 'ack'; // responder acknowledgement of a help request

// Higher number = forwarded and kept first.
export const PRIORITY = {
  low: 0,
  normal: 1,
  high: 2,
  critical: 3,
} as const;
export type Priority = (typeof PRIORITY)[keyof typeof PRIORITY];

export interface GeoPoint {
  lat: number;
  lon: number;
  accuracyM?: number;
}

export interface WarningTranslation { title: string; body: string }
export type WarningTranslations = Partial<Record<string, WarningTranslation>>;

export interface RelayMessage {
  id: string;
  kind: MessageKind;
  priority: Priority;
  originDeviceId: string;
  createdAt: number; // epoch ms
  expiresAt: number; // epoch ms
  hops: number; // devices this copy has passed through
  maxHops: number;
  body: string;
  location?: GeoPoint;
  replyTo?: string; // id of the message an ack answers
  recipientDeviceId?: string;
  incidentId?: string;
  title?: string;
  translations?: WarningTranslations;
}

export const MAX_BODY_LENGTH = 1000;

const DEFAULT_TTL_MS: Record<MessageKind, number> = {
  help_request: 24 * 60 * 60 * 1000,
  warning: 12 * 60 * 60 * 1000,
  status: 24 * 60 * 60 * 1000,
  ack: 24 * 60 * 60 * 1000,
};

const DEFAULT_PRIORITY: Record<MessageKind, Priority> = {
  help_request: PRIORITY.critical,
  warning: PRIORITY.high,
  status: PRIORITY.normal,
  ack: PRIORITY.high,
};

export interface NewMessage {
  kind: MessageKind;
  originDeviceId: string;
  body: string;
  location?: GeoPoint;
  replyTo?: string;
  recipientDeviceId?: string;
  incidentId?: string;
  title?: string;
  translations?: WarningTranslations;
  priority?: Priority;
  ttlMs?: number;
  maxHops?: number;
  now?: number;
  id?: string;
}

export function createMessage(input: NewMessage): RelayMessage {
  const now = input.now ?? Date.now();
  const message: RelayMessage = {
    id: input.id ?? crypto.randomUUID(),
    kind: input.kind,
    priority: input.priority ?? DEFAULT_PRIORITY[input.kind],
    originDeviceId: input.originDeviceId,
    createdAt: now,
    expiresAt: now + (input.ttlMs ?? DEFAULT_TTL_MS[input.kind]),
    hops: 0,
    maxHops: input.maxHops ?? 8,
    body: input.body,
    ...(input.location !== undefined && { location: input.location }),
    ...(input.replyTo !== undefined && { replyTo: input.replyTo }),
    ...(input.recipientDeviceId !== undefined && { recipientDeviceId: input.recipientDeviceId }),
    ...(input.incidentId !== undefined && { incidentId: input.incidentId }),
    ...(input.title !== undefined && { title: input.title }),
    ...(input.translations !== undefined && { translations: input.translations }),
  };
  const errors = validateMessage(message);
  if (errors.length > 0) {
    throw new Error(`Invalid message: ${errors.join('; ')}`);
  }
  return message;
}

const KINDS: readonly MessageKind[] = ['help_request', 'warning', 'status', 'ack'];

export function isIdentifier(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/.test(value);
}

// Validates untrusted input, e.g. a message received from a nearby device.
export function validateMessage(value: unknown): string[] {
  const errors: string[] = [];
  if (typeof value !== 'object' || value === null) return ['not an object'];
  const m = value as Record<string, unknown>;

  if (!isIdentifier(m.id)) errors.push('id');
  if (!KINDS.includes(m.kind as MessageKind)) errors.push('kind');
  if (!Number.isInteger(m.priority) || (m.priority as number) < 0 || (m.priority as number) > 3) {
    errors.push('priority');
  }
  if (!isIdentifier(m.originDeviceId)) errors.push('originDeviceId');
  if (!Number.isSafeInteger(m.createdAt) || (m.createdAt as number) < 0) errors.push('createdAt');
  if (!Number.isSafeInteger(m.expiresAt) || (m.expiresAt as number) <= (m.createdAt as number)) {
    errors.push('expiresAt');
  }
  if (!Number.isInteger(m.hops) || (m.hops as number) < 0) errors.push('hops');
  if (!Number.isInteger(m.maxHops) || (m.maxHops as number) < 0 || (m.maxHops as number) > 64) errors.push('maxHops');
  if ((m.hops as number) > (m.maxHops as number)) errors.push('hops exceeds maxHops');
  if (typeof m.body !== 'string' || !m.body.trim() || m.body.length > MAX_BODY_LENGTH) errors.push('body');
  if (m.location !== undefined && !isGeoPoint(m.location)) errors.push('location');
  if (m.replyTo !== undefined && !isIdentifier(m.replyTo)) errors.push('replyTo');
  if (m.recipientDeviceId !== undefined && !isIdentifier(m.recipientDeviceId)) errors.push('recipientDeviceId');
  if (m.incidentId !== undefined && !isIdentifier(m.incidentId)) errors.push('incidentId');
  if (m.title !== undefined && !validText(m.title, 120)) errors.push('title');
  if (m.translations !== undefined && !validTranslations(m.translations)) errors.push('translations');
  if (m.kind === 'ack' && !isIdentifier(m.replyTo)) errors.push('ack requires replyTo');
  return errors;
}

function validText(value: unknown, limit: number): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= limit;
}

function validTranslations(value: unknown): value is WarningTranslations {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const entries = Object.entries(value);
  return entries.length <= 12 && entries.every(([language, text]) =>
    /^[A-Za-z][A-Za-z0-9_-]{0,39}$/.test(language) && text && typeof text === 'object' &&
    validText(text.title, 120) && validText(text.body, MAX_BODY_LENGTH));
}

function isGeoPoint(value: unknown): value is GeoPoint {
  if (typeof value !== 'object' || value === null) return false;
  const p = value as Record<string, unknown>;
  return (
    typeof p.lat === 'number' &&
    p.lat >= -90 &&
    p.lat <= 90 &&
    typeof p.lon === 'number' &&
    p.lon >= -180 &&
    p.lon <= 180 &&
    (p.accuracyM === undefined || (typeof p.accuracyM === 'number' && Number.isFinite(p.accuracyM) && p.accuracyM >= 0))
  );
}

export function isExpired(message: RelayMessage, now: number = Date.now()): boolean {
  return message.expiresAt <= now;
}

export function canForward(message: RelayMessage, now: number = Date.now()): boolean {
  return !isExpired(message, now) && message.hops < message.maxHops;
}

// Ordering used for storage eviction and transfer: most important, then newest.
export function compareByImportance(a: RelayMessage, b: RelayMessage): number {
  return b.priority - a.priority || b.createdAt - a.createdAt;
}

// Copies taking different routes may differ in hop count, never original content.
export function sameMessage(a: RelayMessage, b: RelayMessage): boolean {
  const identity = (m: RelayMessage) => [m.id, m.kind, m.priority, m.originDeviceId,
    m.createdAt, m.expiresAt, m.maxHops, m.body, m.location?.lat, m.location?.lon,
    m.location?.accuracyM, m.replyTo, m.recipientDeviceId, m.incidentId, m.title,
    Object.entries(m.translations ?? {}).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
      .map(([language, text]) => [language, text?.title, text?.body])];
  return JSON.stringify(identity(a)) === JSON.stringify(identity(b));
}
