import { fileURLToPath, URL } from 'node:url';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@relay/core': fileURLToPath(new URL('../../packages/relay-core/src/index.ts', import.meta.url)),
    },
  },
  server: {
    fs: { allow: ['../..'] },
  },
});
