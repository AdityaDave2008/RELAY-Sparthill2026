import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createMessage, encodeTransfer, MessageStore, TransferReceiver, validateMessage } from '../src/index.ts';

test('warning titles and translations survive a complete offline transfer', async () => {
  const sender = new MessageStore(), receiver = new MessageStore();
  const message = createMessage({ kind: 'warning', originDeviceId: 'demo-coordinator', body: 'Demo shelter has water.',
    title: 'Water update', translations: { es: { title: 'Actualización de agua', body: 'El refugio de demostración tiene agua.' },
      zh: { title: '饮用水信息', body: '演示避难所有饮用水。' } } });
  sender.add(message);
  const importer = new TransferReceiver(receiver);
  for (const frame of await encodeTransfer(sender)) await importer.accept(frame);
  assert.deepEqual(receiver.get(message.id)?.translations, message.translations);
  assert.equal(receiver.get(message.id)?.title, message.title);
  const reordered = { ...message, translations: { zh: message.translations!.zh, es: message.translations!.es } };
  assert.equal(receiver.add(reordered), 'duplicate');
  assert.equal(receiver.add({ ...message, translations: { es: { title: 'Altered', body: 'Altered' } } }), 'conflict');
});

test('unbounded or malformed warning translations are rejected', () => {
  const base = createMessage({ kind: 'warning', originDeviceId: 'coordinator', body: 'Demo only' });
  for (const translations of [[], null, { es: 'text' }, { es: { title: '', body: 'Text' } }, { es: { title: 'Title', body: 'x'.repeat(1001) } }]) {
    assert.ok(validateMessage({ ...base, translations }).includes('translations'));
  }
});
