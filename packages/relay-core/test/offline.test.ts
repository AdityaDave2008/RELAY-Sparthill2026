import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createMessage, encodeTransfer, localStoragePersistence, MessageStore, syncWithGateway, TransferReceiver, validateMessage } from '../src/index.ts';

const NOW = 1_790_000_000_000;
const help = (id = 'request-1', body = 'Four people need water') => createMessage({ id, kind: 'help_request', originDeviceId: 'resident', body, now: NOW });
const memoryStorage = () => {
  const values = new Map<string, string>();
  return { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value); } };
};

test('requests and upload receipts survive reopening the persistent store', () => {
  const persistence = localStoragePersistence(memoryStorage(), 'device-a');
  const first = MessageStore.open(persistence, { now: NOW });
  first.add(help(), NOW);
  first.markUploaded(['request-1']);
  const reopened = MessageStore.open(persistence, { now: NOW });
  assert.equal(reopened.get('request-1')?.body, 'Four people need water');
  assert.deepEqual(reopened.pendingUpload(NOW), []);
});

test('failed disk/quota writes do not pretend a message or receipt was saved', () => {
  let snapshot: string | null = null, fail = false;
  const store = MessageStore.open({ read: () => snapshot, write: value => {
    if (fail) throw new Error('quota exceeded'); snapshot = value;
  } }, { now: NOW });
  store.add(help(), NOW);
  fail = true;
  assert.throws(() => store.add(help('request-2'), NOW), /quota/);
  assert.equal(store.has('request-2'), false);
  assert.throws(() => store.markUploaded(['request-1']), /quota/);
  assert.equal(store.pendingUpload(NOW).length, 1);
  assert.equal(JSON.parse(snapshot!).messages.length, 1);
});

test('corrupt snapshots remain untouched for recovery', () => {
  let writes = 0;
  assert.throws(() => MessageStore.open({ read: () => '{broken', write: () => { writes++; } }));
  assert.throws(() => MessageStore.fromJSON({ messages: [null], uploaded: [] }));
  assert.equal(writes, 0);
  for (const capacity of [0, -1, 1.5, Infinity]) assert.throws(() => new MessageStore({ capacity }));
});

test('duplicate content is immutable even when a different route has different hops', () => {
  const store = new MessageStore();
  store.add(help(), NOW);
  assert.equal(store.add({ ...help(), hops: 1 }, NOW), 'duplicate');
  assert.equal(store.add({ ...help(), body: 'Altered message' }, NOW), 'conflict');
  store.get('request-1')!.body = 'Changed through getter';
  store.list()[0].body = 'Changed through list';
  assert.equal(store.get('request-1')?.body, help().body);
});

test('reject invalid location accuracy, empty acknowledgments and excessive hops', () => {
  for (const changed of [
    { location: { lat: 1, lon: 2, accuracyM: Infinity } },
    { body: '   ' }, { createdAt: NaN }, { maxHops: 65 }, { hops: 9 },
    { kind: 'ack', replyTo: '' }, { recipientDeviceId: '' },
  ]) assert.ok(validateMessage({ ...help(), ...changed }).length > 0);
  assert.throws(() => createMessage({ kind: 'ack', originDeviceId: 'c', body: 'Seen', replyTo: '', now: NOW }));
});

test('Unicode frames can arrive out of order and repeated; incomplete transfers save nothing', async () => {
  const sender = new MessageStore(), receiver = new MessageStore();
  const body = 'Necesitamos agua 水が必要です 💧 '.repeat(25);
  sender.add(help('multilingual', body), NOW);
  const frames = await encodeTransfer(sender, { now: NOW });
  assert.ok(frames.length > 1);
  assert.ok(frames.every(frame => new TextEncoder().encode(frame).length < 1600));
  const incoming = new TransferReceiver(receiver, { now: () => NOW });
  await incoming.accept(frames.at(-1)!);
  await incoming.accept(frames.at(-1)!);
  assert.equal(receiver.size, 0);
  let result;
  for (const frame of frames.slice(0, -1).reverse()) result = await incoming.accept(frame);
  assert.equal(result?.complete, true);
  assert.equal(receiver.get('multilingual')?.body, body);
  assert.equal(receiver.get('multilingual')?.hops, 1);
  assert.equal(sender.get('multilingual')?.hops, 0);
});

test('tampered transfer fails checksum without storing its messages', async () => {
  const sender = new MessageStore(), receiver = new MessageStore();
  sender.add(help(), NOW);
  const [frame] = await encodeTransfer(sender, { now: NOW });
  const tampered = JSON.parse(frame);
  tampered.data = btoa(atob(tampered.data).replace('water', 'sugar'));
  await assert.rejects(new TransferReceiver(receiver, { now: () => NOW }).accept(JSON.stringify(tampered)), /checksum/);
  assert.equal(receiver.size, 0);
});

test('malformed and oversized transfers are bounded and rejected', async () => {
  const receiver = new TransferReceiver(new MessageStore(), { now: () => NOW });
  for (const frame of ['null', '{}', 'not JSON', 'x'.repeat(1601), JSON.stringify({ protocol: 'relay', version: 1, total: 999_999 })]) {
    await assert.rejects(receiver.accept(frame));
  }
  const sender = new MessageStore();
  sender.add({ ...help(), maxHops: 0 }, NOW);
  assert.deepEqual(await encodeTransfer(sender, { now: NOW }), []);
});

test('failed gateway calls and invalid receipts preserve the offline outbox', async () => {
  const store = new MessageStore(); store.add(help(), NOW);
  await assert.rejects(syncWithGateway(store, { baseUrl: 'http://local/', deviceId: 'relay', now: NOW,
    fetch: async () => Response.json({}, { status: 503 }) }));
  assert.equal(store.pendingUpload(NOW).length, 1);
  await assert.rejects(syncWithGateway(store, { baseUrl: 'http://local/', deviceId: 'relay', now: NOW,
    fetch: async () => Response.json({ acceptedIds: ['not-uploaded'], rejected: [] }) }), /receipt/);
  assert.equal(store.pendingUpload(NOW).length, 1);
});

test('gateway clears only accepted uploads and follows empty filtered pages for resident replies', async () => {
  const store = new MessageStore(); store.add(help(), NOW); store.add(help('request-2'), NOW);
  const ack = createMessage({ id: 'response', kind: 'ack', originDeviceId: 'coordinator',
    recipientDeviceId: 'resident', replyTo: 'request-1', body: 'Your request was received', now: NOW });
  let pageRequests = 0;
  const result = await syncWithGateway(store, { baseUrl: 'http://local/', deviceId: 'relay', now: NOW,
    fetch: async (input, init) => {
      const url = new URL(String(input));
      if (init?.method === 'POST') return Response.json({ acceptedIds: ['request-1'], rejected: [{ id: 'request-2', reason: 'retry' }] });
      pageRequests++;
      if (url.searchParams.get('deviceId') !== 'resident') return Response.json({ messages: [], nextCursor: null });
      return url.searchParams.has('cursor') ? Response.json({ messages: [ack], nextCursor: null }) : Response.json({ messages: [], nextCursor: 'next' });
    },
  });
  assert.deepEqual(result.uploadedIds, ['request-1']);
  assert.deepEqual(result.receivedIds, ['response']);
  assert.deepEqual(store.pendingUpload(NOW).map(m => m.id), ['request-2']);
  assert.equal(pageRequests, 3);
});
