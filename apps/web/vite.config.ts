import { fileURLToPath, URL } from 'node:url';
import basicSsl from '@vitejs/plugin-basic-ssl';
import react from '@vitejs/plugin-react';
import { defineConfig, type ProxyOptions } from 'vite';

// Phones only allow the camera (QR scanning) and service workers on HTTPS.
// `npm run dev:phone` serves a self-signed HTTPS site on the local network.
const https = process.env.RELAY_HTTPS === '1';
const proxy: Record<string, ProxyOptions> = {
  '/api': {
    target: process.env.RELAY_API_TARGET ?? 'http://127.0.0.1:8787',
    changeOrigin: true,
    rewrite: path => path.replace(/^\/api/, ''),
    configure: server => server.on('proxyReq', request => {
      // Browser CORS terminates at this same-origin gateway. The backend's
      // bearer-token checks still apply; AWS credentials stay on the backend.
      request.removeHeader('origin');
    }),
  },
};

export default defineConfig({
  plugins: [react(), ...(https ? [basicSsl()] : [])],
  resolve: {
    alias: {
      '@relay/core': fileURLToPath(new URL('../../packages/relay-core/src/index.ts', import.meta.url)),
    },
  },
  server: {
    proxy,
    fs: { allow: ['../..'] },
  },
  preview: { proxy },
});
