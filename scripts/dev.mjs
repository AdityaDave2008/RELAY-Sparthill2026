import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const preview = process.argv.includes('--preview');
const port = process.env.RELAY_WEB_PORT ?? '5173';
const env = { ...process.env, RELAY_API_TARGET: process.env.RELAY_API_TARGET ?? `http://127.0.0.1:${process.env.RELAY_PORT ?? '8787'}` };
const children = [
  spawn(process.execPath, ['--env-file-if-exists=.env', 'src/server.ts'], { cwd: root + '/services/api', stdio: 'inherit' }),
  spawn(process.execPath, [root + '/node_modules/vite/bin/vite.js', ...(preview ? ['preview'] : []),
    '--host', '127.0.0.1', '--port', port, '--strictPort'], { cwd: root + '/apps/web', env, stdio: 'inherit' }),
];
let stopping = false;
const stop = code => {
  if (stopping) return;
  stopping = true;
  for (const child of children) child.kill('SIGTERM');
  process.exitCode = code;
};
for (const child of children) {
  child.once('error', () => stop(1));
  child.once('exit', code => stop(code ?? 0));
}
process.once('SIGINT', () => stop(0));
process.once('SIGTERM', () => stop(0));
