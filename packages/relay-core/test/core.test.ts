import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createMessage, exchange, MessageStore, PRIORITY, receive, validateMessage } from '../src/index.ts';

const T0 = 1_700_000_000_000;
const HOUR = 60 * 60 * 1000;

const help = (id: string, extra: object = {}) =>
  createMessage({ id, kind: 'help_request', originDeviceId: 'phone-a', body: 'Trapped, 2 people', now: T0, ...extra });

test('createMessage applies per-kind defaults', () => {
  const m = help('m1', { location: { lat: 37.33, lon: -121.88 } });
  assert.equal(m.priority, PRIORITY.critical);
  assert.equal(m.hops, 0);
  assert.equal(m.expiresAt, T0 + 24 * HOUR);
  assert.deepEqual(m.location, { lat: 37.33, lon: -121.88 });
});

test('validateMessage rejects malformed input from peers', () => {
  assert.deepEqual(validateMessage(help('ok')), []);
  assert.ok(validateMessage(null).length > 0);
  assert.ok(validateMessage({ ...help('x'), kind: 'spam' }).includes('kind'));
  assert.ok(validateMessage({ ...help('x'), location: { lat: 200, lon: 0 } }).includes('location'));
  assert.throws(() => createMessage({ kind: 'ack', originDeviceId: 'b', body: 'on our way', now: T0 }));
});

test('store dedupes, drops expired, and prunes', () => {
  const store = new MessageStore();
  assert.equal(store.add(help('m1'), T0), 'added');
  assert.equal(store.add(help('m1'), T0), 'duplicate');
  assert.equal(store.add(help('old', { ttlMs: HOUR }), T0 + 2 * HOUR), 'expired');
  store.add(help('short', { ttlMs: HOUR }), T0);
  assert.equal(store.prune(T0 + 2 * HOUR), 1);
  assert.equal(store.size, 1);
});

test('full store evicts the least important message, never a more important one', () => {
  const store = new MessageStore({ capacity: 2 });
  const status = (id: string) => createMessage({ id, kind: 'status', originDeviceId: 'b', body: 'safe', now: T0 });
  store.add(help('h1'), T0);
  store.add(status('s1'), T0);
  assert.equal(store.add(help('h2'), T0), 'added');
  assert.ok(!store.has('s1'));
  assert.equal(store.add(status('s2'), T0), 'rejected_full');
});

test('upload queue tracks what reached AWS and survives serialisation', () => {
  const store = new MessageStore();
  store.add(help('m1'), T0);
  store.add(help('m2'), T0);
  store.markUploaded(['m1']);
  const restored = MessageStore.fromJSON(JSON.parse(JSON.stringify(store)), { now: T0 });
  assert.deepEqual(restored.pendingUpload(T0).map((m) => m.id), ['m2']);
});

test('a help request hops A -> B -> C with no network', () => {
  const [a, b, c] = [new MessageStore(), new MessageStore(), new MessageStore()];
  a.add(help('sos'), T0);

  exchange(a, b, { now: T0 });
  const { aToB } = exchange(b, c, { now: T0 });

  assert.deepEqual(aToB.added, ['sos']);
  assert.equal(c.get('sos')?.hops, 2);
  assert.equal(a.get('sos')?.hops, 0);
  // Already-held messages are not re-sent.
  assert.deepEqual(exchange(a, b, { now: T0 }).aToB.added, []);
});

test('messages stop at maxHops and after expiry', () => {
  const [a, b, c] = [new MessageStore(), new MessageStore(), new MessageStore()];
  a.add(help('near', { maxHops: 1 }), T0);
  exchange(a, b, { now: T0 });
  exchange(b, c, { now: T0 });
  assert.ok(b.has('near'));
  assert.ok(!c.has('near'));

  const d = new MessageStore();
  exchange(a, d, { now: T0 + 25 * HOUR });
  assert.equal(d.size, 0);
});

test('receive reports invalid messages instead of storing them', () => {
  const b = new MessageStore();
  // A tampered or corrupted message arriving over the link.
  const bad = { ...help('bad'), body: 'x'.repeat(5000) };
  const report = receive(b, { messages: [help('good'), bad] }, T0);
  assert.deepEqual(report.added, ['good']);
  assert.deepEqual(report.rejected, [{ id: 'bad', reason: 'invalid' }]);
  assert.ok(!b.has('bad'));
});
