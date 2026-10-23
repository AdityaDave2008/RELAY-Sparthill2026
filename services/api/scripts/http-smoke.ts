import assert from 'node:assert/strict';
import { setTimeout } from 'node:timers/promises';
import { createMessage } from '@relay/core';

const base = process.env.RELAY_API_URL ?? 'http://127.0.0.1:8787';
async function call(path: string, body?: unknown, coordinator = false): Promise<any> {
  const token = coordinator ? process.env.RELAY_COORDINATOR_TOKEN : process.env.RELAY_DEVICE_TOKEN;
  const response = await fetch(base + path, { method: body === undefined ? 'GET' : 'POST',
    headers: { ...(body === undefined ? {} : { 'content-type': 'application/json' }), ...(token ? { authorization: `Bearer ${token}` } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(30_000) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error?.code ?? 'HTTP request failed');
  return result;
}
async function findRequest(id: string) {
  let cursor: string | null = null;
  do {
    const page = await call('/v1/requests?' + new URLSearchParams({ limit: '50', ...(cursor ? { cursor } : {}) }), undefined, true);
    const found = page.requests.find((record: any) => record.message.id === id);
    if (found) return found;
    cursor = page.nextCursor;
  } while (cursor);
  return undefined;
}

try {
  const health = await call('/v1/health');
  assert.equal(health.bedrockConfigured, true);
  const id = 'http-demo-' + crypto.randomUUID();
  const message = createMessage({ id, kind: 'help_request', originDeviceId: 'http-demo-resident',
    body: 'Fictional drill. Four people on the third floor need drinking water.', incidentId: 'demo-zone' });
  assert.deepEqual((await call('/v1/messages/batch', { deviceId: 'http-demo-volunteer', messages: [message] })).acceptedIds, [id]);
  let record;
  for (let attempt = 0; attempt < 40; attempt++) {
    record = await findRequest(id);
    if (record?.classification) break;
    await setTimeout(500);
  }
  assert.equal(record?.classification?.source, 'amazon-bedrock', 'Automatic Bedrock analysis did not complete');
  const prepared = await call(`/v1/requests/${id}/response-draft`, {
    notes: 'Fictional drill. The coordinator verified that Demo Shelter A at 100 Example Street has drinking water until 18:00. No delivery or transport is confirmed.',
    language: 'Spanish',
  }, true);
  const reply = await call(`/v1/requests/${id}/replies`, { id: 'ack-' + crypto.randomUUID(), body: prepared.draft.message }, true);
  assert.equal(reply.message.recipientDeviceId, message.originDeviceId);
  assert.equal((await findRequest(id)).repliedAt, reply.message.createdAt);
  console.log(JSON.stringify({ success: true, transport: 'real HTTP', automaticUploadClassification: true,
    modelId: record.classification.modelId, extractionRequestId: record.classification.awsRequestId,
    draftRequestId: prepared.draft.awsRequestId, responseLanguage: prepared.draft.language,
    approvedReplyId: reply.message.id, coordinatorReplyPersisted: true }, null, 2));
} catch (caught) {
  console.error('Live HTTP smoke test failed:', caught instanceof Error ? caught.message : 'UnknownError');
  process.exitCode = 1;
}
