import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test, type TestContext } from 'node:test';
import { createMessage } from '@relay/core';
import { createApi } from '../src/app.ts';
import { RequestProcessor } from '../src/processing.ts';
import { FileRepository, type Classification } from '../src/repository.ts';
import { createStreamHandler } from '../src/worker.ts';

const NOW = 1_790_000_000_000;
const classification: Classification = { needs: ['water'], peopleCount: 4, locationDescription: null,
  summary: 'Four people need water.', requiresHumanReview: true, source: 'amazon-bedrock', modelId: 'unit-test-double' };
const message = () => createMessage({ id: 'job-1', kind: 'help_request', originDeviceId: 'resident', body: 'Four people need water', now: NOW });
function repository(t: TestContext) {
  const directory = mkdtempSync(join(tmpdir(), 'relay-processor-test-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return new FileRepository(join(directory, 'data.json'));
}

test('upload is acknowledged durably before automatic Bedrock analysis completes', { timeout: 3000 }, async t => {
  const repo = repository(t);
  let finish!: (value: Classification) => void;
  const deferred = new Promise<Classification>(resolve => { finish = resolve; });
  const classifier = { classify: async () => deferred };
  const processor = new RequestProcessor(repo, classifier, () => NOW);
  t.after(() => { processor.stop(); finish(classification); });
  const api = createApi({ repository: repo, processor, classifier, allowUnauthenticated: true, now: () => NOW });
  const response = await api(new Request('http://local/v1/messages/batch', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: 'relay', messages: [message()] }) }));
  assert.deepEqual((await response.json()).acceptedIds, ['job-1']);
  assert.ok(await repo.get('job-1'));
  const running = processor.drain();
  assert.equal((await repo.get('job-1'))?.classification, undefined);
  finish(classification); await running;
  assert.deepEqual((await repo.get('job-1'))?.classification, classification);
});

test('recovery finds unclassified requests and overlapping analysis shares one invocation', async t => {
  const repo = repository(t);
  await repo.putIfAbsent({ message: message(), receivedAt: NOW });
  let calls = 0;
  const processor = new RequestProcessor(repo, { classify: async () => { calls++; return classification; } }, () => NOW);
  t.after(() => processor.stop());
  await processor.recover();
  await Promise.all([processor.drain(), processor.classify('job-1'), processor.classify('job-1')]);
  assert.equal(calls, 1);
  assert.deepEqual((await repo.get('job-1'))?.classification, classification);
});

test('automatic failure retries are bounded while manual retry remains available', async t => {
  const repo = repository(t);
  await repo.putIfAbsent({ message: message(), receivedAt: NOW });
  let time = NOW, calls = 0, failing = true;
  const processor = new RequestProcessor(repo, { classify: async () => {
    calls++; if (failing) throw new Error('temporary provider failure'); return classification;
  } }, () => time);
  t.after(() => processor.stop());
  for (let pass = 0; pass < 5; pass++) { await processor.recover(); await processor.drain(); time += 150_000; }
  assert.equal(calls, 3);
  assert.equal((await repo.get('job-1'))?.message.body, message().body);
  failing = false;
  assert.deepEqual((await processor.classify('job-1'))?.classification, classification);
});

test('DynamoDB stream retries only failed sequence numbers and ignores updates', async () => {
  const calls: string[] = [];
  const handler = createStreamHandler({ classify: async id => {
    calls.push(id); if (id === 'failed') throw new Error('provider failure'); return undefined;
  } });
  const record = (id: string, sequence: string, eventName = 'INSERT') => ({ eventName,
    dynamodb: { Keys: { sk: { S: id } }, SequenceNumber: sequence } });
  const result = await handler({ Records: [record('ok', '1'), record('failed', '2'), record('update', '3', 'MODIFY')] });
  assert.deepEqual(calls, ['ok', 'failed']);
  assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: '2' }] });
});
