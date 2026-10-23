import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test, type TestContext } from 'node:test';
import { createMessage, encodeTransfer, MessageStore, syncWithGateway, TransferReceiver } from '@relay/core';
import { createApi, type ApiOptions } from '../src/app.ts';
import { configuredApi } from '../src/config.ts';
import { createLambdaHandler } from '../src/lambda.ts';
import { FileRepository, type Classification } from '../src/repository.ts';
import type { Classifier } from '../src/bedrock.ts';

const NOW = 1_790_000_000_000;
const classification: Classification = { needs: ['water'], peopleCount: 4, locationDescription: 'Third floor',
  summary: 'Four people request water.', requiresHumanReview: true, source: 'amazon-bedrock', modelId: 'unit-test-double' };
const classifier: Classifier = {
  classify: async () => classification,
  draftBulletin: async (_notes, language) => ({ message: 'Demo Shelter A reports water available until 18:00.',
    spokenMessage: 'Demo Shelter A reports water available until 18:00.', noticeTitle: 'Water update',
    noticeLines: ['Demo Shelter A', 'Water available until 18:00'], language, requiresHumanApproval: true,
    source: 'amazon-bedrock', modelId: 'unit-test-double' }),
};
const help = (id = 'request-1') => createMessage({ id, kind: 'help_request', originDeviceId: 'resident',
  body: 'Four of us on the third floor need water.', location: { lat: 37.33, lon: -121.88, accuracyM: 20 }, now: NOW });

function fixture(t: TestContext, extra: Partial<ApiOptions> = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'relay-api-test-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const path = join(directory, 'data.json');
  const repository = new FileRepository(path);
  const api = createApi({ repository, allowUnauthenticated: true, now: () => NOW, ...extra });
  const call = (path: string, body?: unknown, headers?: Record<string, string>) => api(new Request('http://local' + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { ...(body === undefined ? {} : { 'content-type': 'application/json' }), ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }));
  return { api, call, repository, path };
}

test('uploads are durable, idempotent across restarts, and refuse changed content', async t => {
  const { call, path, repository } = fixture(t);
  const upload = (messages: unknown[]) => call('/v1/messages/batch', { deviceId: 'volunteer', messages });
  assert.deepEqual(await (await upload([help()])).json(), { acceptedIds: ['request-1'], rejected: [] });
  assert.deepEqual(await (await upload([{ ...help(), hops: 2 }])).json(), { acceptedIds: ['request-1'], rejected: [] });
  assert.deepEqual(await (await upload([{ ...help(), body: 'Changed' }])).json(), { acceptedIds: [], rejected: [{ id: 'request-1', reason: 'conflict' }] });
  assert.equal((await new FileRepository(path).get('request-1'))?.message.body, help().body);
  assert.equal((await repository.get('request-1'))?.classification, undefined);
});

test('bad packets and forged coordinator warnings are rejected independently', async t => {
  const { call, repository } = fixture(t);
  const warning = createMessage({ id: 'forged', kind: 'warning', originDeviceId: 'pretend-official', body: 'Unapproved', now: NOW });
  const result = await (await call('/v1/messages/batch', { deviceId: 'volunteer', messages: [
    null, help(), { ...help('expired'), createdAt: NOW - 1000, expiresAt: NOW }, warning, { ...help('future'), createdAt: NOW + 1_000_000, expiresAt: NOW + 2_000_000 },
  ] })).json();
  assert.deepEqual(result.acceptedIds, ['request-1']);
  assert.deepEqual(result.rejected.map((r: { reason: string }) => r.reason), ['invalid', 'expired', 'unauthorized_kind', 'invalid_timestamp']);
  assert.equal(await repository.get('forged'), undefined);
});

test('filtered pagination advances through empty pages instead of hiding requests', async t => {
  const { call } = fixture(t);
  const status = createMessage({ id: 'a-status', kind: 'status', originDeviceId: 'resident', body: 'Safe', now: NOW });
  await call('/v1/messages/batch', { deviceId: 'resident', messages: [status, help('z-help')] });
  const first = await (await call('/v1/requests?limit=1')).json();
  assert.deepEqual(first.requests, []);
  assert.ok(first.nextCursor);
  const second = await (await call('/v1/requests?limit=1&cursor=' + first.nextCursor)).json();
  assert.equal(second.requests[0].message.id, 'z-help');
  assert.equal(second.nextCursor, null);
  assert.equal((await call('/v1/requests?cursor=invalid!')).status, 400);
});

test('device access cannot approve warnings or read the coordinator inbox', async t => {
  const { call } = fixture(t, { allowUnauthenticated: false, deviceToken: 'device-demo-token', coordinatorToken: 'coordinator-demo-token' });
  assert.equal((await call('/v1/requests')).status, 401);
  assert.equal((await call('/v1/requests', undefined, { authorization: 'Bearer device-demo-token' })).status, 401);
  assert.equal((await call('/v1/requests', undefined, { authorization: 'Bearer coordinator-demo-token' })).status, 200);
  assert.equal((await call('/v1/health')).status, 200);
});

test('allowed-origin preflight works and unlisted origins are refused', async t => {
  const { api } = fixture(t, { allowedOrigins: ['http://localhost:5173'] });
  const preflight = await api(new Request('http://local/v1/messages/batch', { method: 'OPTIONS', headers: { Origin: 'http://localhost:5173' } }));
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), 'http://localhost:5173');
  assert.equal((await api(new Request('http://local/v1/health', { headers: { Origin: 'https://unlisted.invalid' } }))).status, 403);
});

test('AI failure preserves the original request and never invents a successful result', async t => {
  const { call, repository } = fixture(t, { classifier: { classify: async () => { throw new Error('provider failure'); } } });
  await call('/v1/messages/batch', { deviceId: 'resident', messages: [help()] });
  const response = await call('/v1/requests/request-1/classify', {});
  assert.equal(response.status, 502);
  assert.equal((await response.json()).error.code, 'classification_failed');
  assert.equal((await repository.get('request-1'))?.message.body, help().body);
  assert.equal((await repository.get('request-1'))?.classification, undefined);
});

test('prepare-response uses extracted needs and source notes, then waits for approval', async t => {
  const actions: string[] = [];
  const { call } = fixture(t, { classifier: {
    classify: async message => { actions.push('extract'); assert.equal(message.body, help().body); return classification; },
    draftBulletin: async (notes, language, context) => {
      actions.push('draft'); assert.equal(notes, 'Demo Shelter A: water until 18:00');
      assert.equal(context?.peopleCount, 4);
      return classifier.draftBulletin!(notes, language, context);
    },
  } });
  await call('/v1/messages/batch', { deviceId: 'resident', messages: [help()] });
  const response = await call('/v1/requests/request-1/response-draft', { notes: 'Demo Shelter A: water until 18:00', language: 'English' });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.request.classification.requiresHumanReview, true);
  assert.equal(result.draft.requiresHumanApproval, true);
  assert.deepEqual(actions, ['extract', 'draft']);
  assert.deepEqual((await (await call('/v1/messages?deviceId=resident')).json()).messages, []);
  const approved = await call('/v1/requests/request-1/replies', { id: 'approved-reply', body: result.draft.message });
  assert.equal(approved.status, 201);
  const delivered = await (await call('/v1/messages?deviceId=resident')).json();
  assert.equal(delivered.messages[0].replyTo, 'request-1');
  assert.equal(delivered.messages[0].recipientDeviceId, 'resident');
  assert.equal((await (await call('/v1/requests')).json()).requests[0].repliedAt, NOW);
  assert.deepEqual((await (await call('/v1/messages?deviceId=other-resident')).json()).messages, []);
});

test('coordinator retries are safe and changed warning coordinates cannot reuse an ID', async t => {
  const { call } = fixture(t);
  const input = { id: 'warning-1', body: 'Fictional water update', location: { lat: 1, lon: 2 }, title: 'Water',
    translations: { es: { title: 'Agua', body: 'Actualización ficticia' } } };
  const created = await call('/v1/warnings', input);
  assert.equal(created.status, 201);
  const published = (await created.json()).message;
  assert.equal(published.title, input.title);
  assert.deepEqual(published.translations, input.translations);
  assert.equal((await call('/v1/warnings', input)).status, 200);
  assert.equal((await call('/v1/warnings', { ...input, location: { lat: 3, lon: 2 } })).status, 409);
  assert.equal((await call('/v1/warnings', { ...input, id: 'bad-location', location: null })).status, 400);
});

test('the full resident-relay-coordinator return path keeps message identity', async t => {
  const { api, call } = fixture(t, { classifier });
  const resident = new MessageStore(), volunteer = new MessageStore();
  resident.add(help(), NOW);
  const outbound = new TransferReceiver(volunteer, { now: () => NOW });
  for (const frame of await encodeTransfer(resident, { now: NOW })) await outbound.accept(frame);
  const fetchApi: typeof fetch = async (input, init) => api(new Request(input, init));
  const options = { baseUrl: 'http://local/', deviceId: 'volunteer', now: NOW, fetch: fetchApi };
  assert.deepEqual((await syncWithGateway(volunteer, options)).uploadedIds, ['request-1']);
  const prepared = await (await call('/v1/requests/request-1/response-draft', { notes: 'Fictional shelter source notes' })).json();
  await call('/v1/requests/request-1/replies', { id: 'reply-1', body: prepared.draft.message });
  assert.deepEqual((await syncWithGateway(volunteer, options)).receivedIds, ['reply-1']);
  const inbound = new TransferReceiver(resident, { now: () => NOW });
  for (const frame of await encodeTransfer(volunteer, { ids: ['reply-1'], now: NOW })) await inbound.accept(frame);
  assert.equal(resident.get('reply-1')?.replyTo, 'request-1');
  assert.equal(resident.get('reply-1')?.body, prepared.draft.message);
  assert.deepEqual(resident.get('request-1')?.location, help().location);
});

test('Lambda adapter handles base64 JSON and returns normal HTTP responses', async t => {
  const { api } = fixture(t);
  const handler = createLambdaHandler(api);
  const response = await handler({ rawPath: '/v1/messages/batch', requestContext: { http: { method: 'POST' } },
    headers: { 'content-type': 'application/json' }, isBase64Encoded: true,
    body: Buffer.from(JSON.stringify({ deviceId: 'volunteer', messages: [help()] })).toString('base64') });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body).acceptedIds, ['request-1']);
});

test('invalid JSON, oversized bodies and unconfigured Bedrock produce explicit errors', async t => {
  const { api, call } = fixture(t);
  assert.equal((await api(new Request('http://local/v1/messages/batch', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{' }))).status, 400);
  assert.equal((await api(new Request('http://local/v1/messages/batch', { method: 'POST', headers: { 'content-type': 'application/jsonp' }, body: '{}' }))).status, 415);
  assert.equal((await api(new Request('http://local/v1/messages/batch', { method: 'POST', headers: { 'content-type': 'application/json' }, body: 'x'.repeat(262_145) }))).status, 413);
  await call('/v1/messages/batch', { deviceId: 'resident', messages: [help()] });
  assert.equal((await call('/v1/requests/request-1/classify', {})).status, 503);
  assert.equal((await call('/v1/bulletins/draft', { notes: 'Fictional source notes' })).status, 503);
});

test('workshop Region and network token requirements are enforced before startup', () => {
  assert.throws(() => configuredApi({ AWS_REGION: 'us-west-2' }), /us-east-1/);
  assert.throws(() => configuredApi({ RELAY_HOST: '0.0.0.0' }), /tokens|TOKEN/);
  assert.throws(() => configuredApi({ RELAY_HOST: '0.0.0.0', RELAY_DEVICE_TOKEN: 'same-token-123456', RELAY_COORDINATOR_TOKEN: 'same-token-123456' }), /different/);
});

test('corrupt server state is preserved rather than silently reset', t => {
  const { path } = fixture(t);
  writeFileSync(path, '{corrupt');
  assert.throws(() => new FileRepository(path));
  assert.equal(readFileSync(path, 'utf8'), '{corrupt');
});
