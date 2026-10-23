import { timingSafeEqual } from 'node:crypto';
import { createMessage, isIdentifier, sameMessage, validateMessage, type RelayMessage } from '@relay/core';
import type { Classifier } from './bedrock.ts';
import type { Repository, RequestRecord } from './repository.ts';
import type { RequestProcessor } from './processing.ts';

export const MAX_REQUEST_BYTES = 262_144;
export interface ApiOptions {
  repository: Repository;
  classifier?: Classifier;
  processor?: RequestProcessor;
  autoClassify?: boolean;
  deviceToken?: string;
  coordinatorToken?: string;
  allowUnauthenticated?: boolean;
  allowedOrigins?: string[];
  now?: () => number;
}
class ApiError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) { super(message); this.status = status; this.code = code; }
}
const error = (status: number, code: string, message: string): never => { throw new ApiError(status, code, message); };
const identifier = (value: unknown): string => isIdentifier(value) ? value : error(400, 'invalid_id', 'A valid identifier is required');

export function createApi(options: ApiOptions): (request: Request) => Promise<Response> {
  const repo = options.repository;
  const now = options.now ?? Date.now;
  const classifications = new Map<string, Promise<RequestRecord>>();
  const authorized = (request: Request, role: 'device' | 'coordinator') => {
    if (!options.deviceToken || !options.coordinatorToken) {
      if (options.allowUnauthenticated && !options.deviceToken && !options.coordinatorToken) return;
      return error(503, 'auth_not_configured', 'Configure both demo access tokens');
    }
    const token = request.headers.get('authorization')?.replace(/^Bearer /, '') ?? '';
    const matches = (expected: string) => {
      const a = Buffer.from(token), b = Buffer.from(expected);
      return a.length === b.length && timingSafeEqual(a, b);
    };
    if (!matches(options.coordinatorToken) && !(role === 'device' && matches(options.deviceToken))) error(401, 'unauthorized', 'A valid access token is required');
  };
  const json = async (request: Request): Promise<Record<string, unknown>> => {
    if (request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') error(415, 'content_type', 'Use application/json');
    const text = await request.text();
    if (Buffer.byteLength(text) > MAX_REQUEST_BYTES) error(413, 'body_too_large', 'Request body exceeds 256 KiB');
    let value: unknown;
    try { value = JSON.parse(text); } catch { error(400, 'invalid_json', 'Request body is not valid JSON'); }
    if (!value || typeof value !== 'object' || Array.isArray(value)) error(400, 'invalid_body', 'Expected a JSON object');
    return value as Record<string, unknown>;
  };
  const liveRequest = async (id: string): Promise<RequestRecord> => {
    const record = await repo.get(id);
    if (!record || record.message.kind !== 'help_request') return error(404, 'request_not_found', 'Help request not found');
    if (record.message.expiresAt <= now()) error(410, 'request_expired', 'Help request has expired');
    return record;
  };
  const saveCoordinatorMessage = async (input: Record<string, unknown>, kind: 'ack' | 'warning', target?: RequestRecord) => {
    const id = identifier(input.id);
    if (typeof input.body !== 'string' || !input.body.trim() || input.body.length > 1000) error(400, 'invalid_message', 'Body must contain 1 to 1000 characters');
    if (input.ttlMs !== undefined && (!Number.isSafeInteger(input.ttlMs) || Number(input.ttlMs) < 1 || Number(input.ttlMs) > 7 * 86_400_000)) error(400, 'invalid_ttl', 'TTL must be 1 ms to 7 days');
    let message: RelayMessage;
    try {
      message = createMessage({ id, kind, originDeviceId: 'demo-coordinator', body: input.body as string,
        now: now(), ...(input.ttlMs !== undefined ? { ttlMs: input.ttlMs as number } : {}),
        ...(input.location !== undefined ? { location: input.location as RelayMessage['location'] } : {}),
        ...(input.incidentId !== undefined ? { incidentId: identifier(input.incidentId) } : {}),
        ...(input.title !== undefined ? { title: input.title as string } : {}),
        ...(input.translations !== undefined ? { translations: input.translations as RelayMessage['translations'] } : {}),
        ...(target ? { replyTo: target.message.id, recipientDeviceId: target.message.originDeviceId } : {}),
      });
    } catch { return error(400, 'invalid_message', 'Message fields are invalid'); }
    const retryMatches = (original: RelayMessage) => sameMessage(original, { ...message,
      createdAt: original.createdAt, expiresAt: original.createdAt + message.expiresAt - message.createdAt });
    const existing = await repo.get(id);
    if (existing) {
      if (!retryMatches(existing.message)) return error(409, 'id_conflict', 'This message ID already has different content');
      if (existing.message.expiresAt <= now()) return error(410, 'message_expired', 'Use a new message ID for a new warning or reply');
      return { status: 200, message: existing.message };
    }
    if (!await repo.putIfAbsent({ message, receivedAt: now() })) {
      const duplicate = await repo.get(id);
      if (duplicate && retryMatches(duplicate.message)) return { status: 200, message: duplicate.message };
      return error(409, 'id_conflict', 'This message ID already has different content');
    }
    return { status: 201, message };
  };

  return async request => {
    const origin = request.headers.get('origin');
    const headers = new Headers({ 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', Vary: 'Origin' });
    if (origin && options.allowedOrigins?.includes(origin)) {
      headers.set('Access-Control-Allow-Origin', origin);
      headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    }
    const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
    try {
      if (origin && !options.allowedOrigins?.includes(origin)) error(403, 'origin_not_allowed', 'Origin is not allowed');
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
      const url = new URL(request.url);
      const path = url.pathname;
      if (request.method === 'GET' && path === '/v1/health') return respond({ ok: true, mode: 'simulation', storage: repo.kind, bedrockConfigured: Boolean(options.classifier) });
      if (request.method === 'POST' && path === '/v1/messages/batch') {
        authorized(request, 'device');
        const input = await json(request);
        identifier(input.deviceId);
        if (!Array.isArray(input.messages) || input.messages.length > 50) error(400, 'invalid_batch', 'A batch contains at most 50 messages');
        const acceptedIds: string[] = [], rejected: { id: string; reason: string }[] = [];
        for (const candidate of input.messages as unknown[]) {
          const id = candidate && typeof candidate === 'object' && typeof (candidate as RelayMessage).id === 'string' ? (candidate as RelayMessage).id : '';
          if (validateMessage(candidate).length) { rejected.push({ id, reason: 'invalid' }); continue; }
          const message = candidate as RelayMessage;
          const time = now();
          if (message.expiresAt <= time) { rejected.push({ id, reason: 'expired' }); continue; }
          if (message.createdAt > time + 300_000 || message.expiresAt - message.createdAt > 7 * 86_400_000) { rejected.push({ id, reason: 'invalid_timestamp' }); continue; }
          const existing = await repo.get(id);
          if (existing) {
            if (sameMessage(existing.message, message)) {
              acceptedIds.push(id);
              if (message.kind === 'help_request' && !existing.classification && options.autoClassify !== false) options.processor?.schedule(id);
            }
            else rejected.push({ id, reason: 'conflict' });
            continue;
          }
          if (message.kind !== 'help_request' && message.kind !== 'status') { rejected.push({ id, reason: 'unauthorized_kind' }); continue; }
          if (await repo.putIfAbsent({ message, receivedAt: time })) {
            acceptedIds.push(id);
            if (message.kind === 'help_request' && options.autoClassify !== false) options.processor?.schedule(id);
          }
          else {
            const concurrent = await repo.get(id);
            if (concurrent && sameMessage(concurrent.message, message)) acceptedIds.push(id);
            else rejected.push({ id, reason: 'conflict' });
          }
        }
        return respond({ acceptedIds: [...new Set(acceptedIds)], rejected });
      }
      if (request.method === 'GET' && (path === '/v1/messages' || path === '/v1/requests')) {
        const coordinator = path === '/v1/requests';
        authorized(request, coordinator ? 'coordinator' : 'device');
        const deviceId = coordinator ? undefined : identifier(url.searchParams.get('deviceId'));
        const limit = Number(url.searchParams.get('limit') ?? 50);
        if (!Number.isInteger(limit) || limit < 1 || limit > 50) error(400, 'invalid_limit', 'Limit must be 1 to 50');
        const cursor = url.searchParams.get('cursor');
        let afterId: string | undefined;
        if (cursor !== null) {
          if (cursor.length > 128) error(400, 'invalid_cursor', 'Invalid pagination cursor');
          afterId = Buffer.from(cursor, 'base64url').toString('utf8');
          if (!isIdentifier(afterId) || Buffer.from(afterId).toString('base64url') !== cursor) error(400, 'invalid_cursor', 'Invalid pagination cursor');
        }
        const page = await repo.page({ limit, afterId, now: now(), ...(coordinator ? { kind: 'help_request' as const } : { recipientDeviceId: deviceId }) });
        const nextCursor = page.afterId ? Buffer.from(page.afterId).toString('base64url') : null;
        return respond(coordinator ? { requests: page.records, nextCursor } : { messages: page.records.map(r => r.message), nextCursor });
      }
      const action = /^\/v1\/requests\/([^/]+)\/(classify|replies|response-draft)$/.exec(path);
      if (request.method === 'POST' && action) {
        authorized(request, 'coordinator');
        const id = identifier(action[1]);
        const record = await liveRequest(id);
        if (action[2] === 'replies') {
          const result = await saveCoordinatorMessage(await json(request), 'ack', record);
          await repo.markReplied(id, result.message.createdAt);
          return respond({ message: result.message }, result.status);
        }
        let draftInput: Record<string, unknown> | undefined;
        if (action[2] === 'response-draft') {
          draftInput = await json(request);
          if (typeof draftInput.notes !== 'string' || !draftInput.notes.trim() || draftInput.notes.length > 6000 ||
              (draftInput.language !== undefined && (typeof draftInput.language !== 'string' || !draftInput.language.trim() || draftInput.language.length > 80))) {
            error(400, 'invalid_bulletin', 'Provide source notes (1 to 6000 characters) and an optional language (1 to 80 characters)');
          }
        }
        if (record.classification && !draftInput) return respond(record);
        if (!options.classifier) error(503, 'bedrock_not_configured', 'Configure AWS access and BEDROCK_MODEL_ID to classify requests');
        let pending = classifications.get(id);
        if (!pending && !record.classification) {
          pending = (async () => {
            if (options.processor) {
              try { return await options.processor.classify(id) ?? error(410, 'request_expired', 'Help request has expired'); }
              catch { return error(502, 'classification_failed', 'Bedrock extraction failed; the original request is saved and can be retried'); }
            }
            let classification;
            try { classification = await options.classifier!.classify(record.message); }
            catch { return error(502, 'classification_failed', 'Bedrock extraction failed; the original request is saved and can be retried'); }
            const updated = await repo.classify(id, classification, now());
            return updated ?? error(410, 'request_expired', 'Help request expired during classification');
          })();
          classifications.set(id, pending);
        }
        let classified: RequestRecord;
        try { classified = record.classification ? record : await pending!; } finally { classifications.delete(id); }
        if (!draftInput) return respond(classified);
        if (!options.classifier?.draftBulletin) error(503, 'bedrock_not_configured', 'Configure Bedrock to prepare a response');
        try {
          const draft = await options.classifier!.draftBulletin!(draftInput.notes as string,
            (draftInput.language as string | undefined) ?? 'English', classified.classification);
          return respond({ request: classified, draft });
        } catch { return error(502, 'draft_failed', 'Bedrock could not prepare the response; no reply was sent'); }
      }
      if (request.method === 'POST' && path === '/v1/warnings') {
        authorized(request, 'coordinator');
        const result = await saveCoordinatorMessage(await json(request), 'warning');
        return respond({ message: result.message }, result.status);
      }
      if (request.method === 'POST' && path === '/v1/bulletins/draft') {
        authorized(request, 'coordinator');
        const input = await json(request);
        if (typeof input.notes !== 'string' || !input.notes.trim() || input.notes.length > 6000 ||
            (input.language !== undefined && (typeof input.language !== 'string' || !input.language.trim() || input.language.length > 80))) {
          error(400, 'invalid_bulletin', 'Provide source notes (1 to 6000 characters) and an optional language (1 to 80 characters)');
        }
        if (!options.classifier?.draftBulletin) error(503, 'bedrock_not_configured', 'Configure AWS access and BEDROCK_MODEL_ID to draft bulletins');
        try { return respond(await options.classifier!.draftBulletin!(input.notes as string, (input.language as string | undefined) ?? 'English')); }
        catch { return error(502, 'draft_failed', 'Bedrock could not draft the bulletin; no warning was published'); }
      }
      return error(404, 'not_found', 'Endpoint not found');
    } catch (caught) {
      if (caught instanceof ApiError) return respond({ error: { code: caught.code, message: caught.message } }, caught.status);
      return respond({ error: { code: 'internal_error', message: 'The operation failed; retry using the same message IDs' } }, 500);
    }
  };
}
