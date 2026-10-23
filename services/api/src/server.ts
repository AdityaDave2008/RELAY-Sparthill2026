import { createServer, type Server } from 'node:http';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { MAX_REQUEST_BYTES } from './app.ts';
import { configuredApi } from './config.ts';

export function startServer(options: { api?: (request: Request) => Promise<Response>; port?: number; host?: string } = {}): Promise<Server> {
  const port = options.port ?? Number(process.env.RELAY_PORT ?? 8787);
  const host = options.host ?? process.env.RELAY_HOST ?? '127.0.0.1';
  const api = options.api ?? configuredApi({ ...process.env, RELAY_HOST: host });
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('Invalid RELAY_PORT');
  const server = createServer(async (incoming, outgoing) => {
    try {
      const chunks: Buffer[] = [];
      let size = 0;
      for await (const chunk of incoming) {
        size += chunk.length;
        if (size <= MAX_REQUEST_BYTES) chunks.push(Buffer.from(chunk));
      }
      if (size > MAX_REQUEST_BYTES) {
        outgoing.writeHead(413, { 'Content-Type': 'application/json' });
        outgoing.end(JSON.stringify({ error: { code: 'body_too_large', message: 'Request body exceeds 256 KiB' } }));
        return;
      }
      const headers = new Headers();
      for (const [name, value] of Object.entries(incoming.headers)) {
        if (Array.isArray(value)) for (const item of value) headers.append(name, item);
        else if (value !== undefined) headers.set(name, value);
      }
      const method = incoming.method ?? 'GET';
      const request = new Request(new URL(incoming.url ?? '/', 'http://127.0.0.1'), { method, headers,
        ...(!['GET', 'HEAD'].includes(method) ? { body: Buffer.concat(chunks).toString('utf8') } : {}),
      });
      const response = await api(request);
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      outgoing.end(await response.text());
    } catch {
      if (!outgoing.headersSent) outgoing.writeHead(500, { 'Content-Type': 'application/json' });
      outgoing.end(JSON.stringify({ error: { code: 'transport_error', message: 'Request could not be processed' } }));
    }
  });
  server.requestTimeout = 20_000;
  server.headersTimeout = 10_000;
  server.maxHeadersCount = 64;
  server.once('close', () => (api as typeof api & { close?(): void }).close?.());
  return new Promise((resolveServer, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => { server.off('error', reject); resolveServer(server); });
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  startServer().then(server => {
    const address = server.address();
    console.log(`RELAY simulation API listening on ${typeof address === 'object' && address ? address.address + ':' + address.port : address}`);
    const stop = () => server.close(() => process.exit(0));
    process.once('SIGINT', stop); process.once('SIGTERM', stop);
  }).catch(error => { console.error(error instanceof Error ? error.message : 'API startup failed'); process.exitCode = 1; });
}
