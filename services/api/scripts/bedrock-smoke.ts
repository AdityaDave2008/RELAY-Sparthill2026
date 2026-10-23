import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createMessage, encodeTransfer, MessageStore, syncWithGateway, TransferReceiver } from '@relay/core';
import { createApi } from '../src/app.ts';
import { BedrockClassifier } from '../src/bedrock.ts';
import { FileRepository } from '../src/repository.ts';

const directory = mkdtempSync(join(tmpdir(), 'relay-live-bedrock-'));
try {
  const modelId = process.env.BEDROCK_MODEL_ID;
  if (!modelId) throw new Error('BEDROCK_MODEL_ID is required');
  if ((process.env.AWS_REGION && process.env.AWS_REGION !== 'us-east-1') ||
      (process.env.AWS_DEFAULT_REGION && process.env.AWS_DEFAULT_REGION !== 'us-east-1')) throw new Error('Use us-east-1');
  const api = createApi({ repository: new FileRepository(join(directory, 'data.json')),
    classifier: new BedrockClassifier({ modelId, region: 'us-east-1' }), allowUnauthenticated: true });
  const call = async (path: string, body: unknown) => {
    const response = await api(new Request('http://local' + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }));
    const result = await response.json();
    if (!response.ok) throw new Error(result.error?.code ?? 'API request failed');
    return result;
  };
  const resident = new MessageStore(), relay = new MessageStore();
  const request = createMessage({ id: 'live-demo-request', kind: 'help_request', originDeviceId: 'demo-resident',
    body: 'Fictional drill: Four people on the third floor need drinking water. Please reply in Spanish.',
    location: { lat: 37.33, lon: -121.88, accuracyM: 20 } });
  resident.add(request);
  const incoming = new TransferReceiver(relay);
  for (const frame of await encodeTransfer(resident)) await incoming.accept(frame);
  const fetchApi: typeof fetch = async (input, init) => api(new Request(input, init));
  const gateway = { baseUrl: 'http://local/', deviceId: 'demo-volunteer', fetch: fetchApi };
  await syncWithGateway(relay, gateway);
  const prepared = await call('/v1/requests/live-demo-request/response-draft', {
    notes: 'Fictional training exercise. Coordinator verified at 14:00: Demo Shelter A at 100 Example Street has drinking water available until 18:00. No delivery or medical response has been confirmed.',
    language: 'Spanish',
  });
  assert.equal(prepared.request.classification.source, 'amazon-bedrock');
  assert.equal(prepared.draft.source, 'amazon-bedrock');
  assert.equal(prepared.draft.requiresHumanApproval, true);
  await call('/v1/requests/live-demo-request/replies', { id: 'live-demo-approved-reply', body: prepared.draft.message });
  await syncWithGateway(relay, gateway);
  const returning = new TransferReceiver(resident);
  for (const frame of await encodeTransfer(relay, { ids: ['live-demo-approved-reply'] })) await returning.accept(frame);
  assert.equal(resident.get('live-demo-approved-reply')?.replyTo, request.id);
  console.log(JSON.stringify({ success: true, region: 'us-east-1', modelId,
    extractionRequestId: prepared.request.classification.awsRequestId,
    draftRequestId: prepared.draft.awsRequestId,
    extractedNeeds: prepared.request.classification.needs,
    peopleCount: prepared.request.classification.peopleCount,
    approvedDemoReply: resident.get('live-demo-approved-reply')?.body,
    offlinePacketRoundTrip: 'passed in software; physical device camera/radio testing remains',
  }, null, 2));
} catch (caught) {
  console.error('Live Bedrock smoke test failed:', caught instanceof Error ? caught.message : 'UnknownError');
  process.exitCode = 1;
} finally { rmSync(directory, { recursive: true, force: true }); }
