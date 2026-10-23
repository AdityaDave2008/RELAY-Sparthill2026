import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { createMessage } from '@relay/core';
import { createApi } from '../src/app.ts';
import { FileRepository } from '../src/repository.ts';
import { startServer } from '../src/server.ts';

test('HTTP server accepts requests and serves the persisted coordinator inbox', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'relay-http-test-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const api = createApi({ repository: new FileRepository(join(directory, 'data.json')), allowUnauthenticated: true });
  const server = await startServer({ api, port: 0, host: '127.0.0.1' });
  t.after(() => new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())));
  const address = server.address();
  assert.ok(address && typeof address === 'object');
  const base = 'http://127.0.0.1:' + address.port;
  assert.equal((await (await fetch(base + '/v1/health')).json()).mode, 'simulation');
  const message = createMessage({ id: 'http-request', kind: 'help_request', originDeviceId: 'resident', body: 'Water needed' });
  const uploaded = await fetch(base + '/v1/messages/batch', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: 'resident', messages: [message] }) });
  assert.deepEqual((await uploaded.json()).acceptedIds, ['http-request']);
  assert.equal((await (await fetch(base + '/v1/requests')).json()).requests[0].message.id, 'http-request');
});
