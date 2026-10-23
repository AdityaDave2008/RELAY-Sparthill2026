import { fileURLToPath, URL } from 'node:url';
import basicSsl from '@vitejs/plugin-basic-ssl';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// Phones only allow the camera (QR scanning) and service workers on HTTPS.
// `npm run dev:phone` serves a self-signed HTTPS site on the local network.
const https = process.env.RELAY_HTTPS === '1';

export default defineConfig({
  plugins: [react(), ...(https ? [basicSsl()] : [])],
  resolve: {
    alias: {
      '@relay/core': fileURLToPath(new URL('../../packages/relay-core/src/index.ts', import.meta.url)),
    },
  },
  server: {
    fs: { allow: ['../..'] },
  },
});
