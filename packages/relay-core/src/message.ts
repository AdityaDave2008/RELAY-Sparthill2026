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
    ...(input.location && { location: input.location }),
    ...(input.replyTo && { replyTo: input.replyTo }),
  };
  const errors = validateMessage(message);
  if (errors.length > 0) {
    throw new Error(`Invalid message: ${errors.join('; ')}`);
  }
  return message;
}

const KINDS: readonly MessageKind[] = ['help_request', 'warning', 'status', 'ack'];

// Validates untrusted input, e.g. a message received from a nearby device.
export function validateMessage(value: unknown): string[] {
  const errors: string[] = [];
  if (typeof value !== 'object' || value === null) return ['not an object'];
  const m = value as Record<string, unknown>;

  if (typeof m.id !== 'string' || m.id.length === 0 || m.id.length > 64) errors.push('id');
  if (!KINDS.includes(m.kind as MessageKind)) errors.push('kind');
  if (!Number.isInteger(m.priority) || (m.priority as number) < 0 || (m.priority as number) > 3) {
    errors.push('priority');
  }
  if (typeof m.originDeviceId !== 'string' || m.originDeviceId.length === 0) errors.push('originDeviceId');
  if (!Number.isFinite(m.createdAt)) errors.push('createdAt');
  if (!Number.isFinite(m.expiresAt) || (m.expiresAt as number) <= (m.createdAt as number)) {
    errors.push('expiresAt');
  }
  if (!Number.isInteger(m.hops) || (m.hops as number) < 0) errors.push('hops');
  if (!Number.isInteger(m.maxHops) || (m.maxHops as number) < 0) errors.push('maxHops');
  if (typeof m.body !== 'string' || m.body.length > MAX_BODY_LENGTH) errors.push('body');
  if (m.location !== undefined && !isGeoPoint(m.location)) errors.push('location');
  if (m.replyTo !== undefined && typeof m.replyTo !== 'string') errors.push('replyTo');
  if (m.kind === 'ack' && typeof m.replyTo !== 'string') errors.push('ack requires replyTo');
  return errors;
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
    (p.accuracyM === undefined || (typeof p.accuracyM === 'number' && p.accuracyM >= 0))
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
