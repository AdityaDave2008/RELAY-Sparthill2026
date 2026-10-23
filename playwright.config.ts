import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  timeout: 240_000,
  expect: { timeout: 35_000 },
  workers: 1,
  retries: 0,
  use: {
    baseURL: process.env.RELAY_TEST_URL ?? 'http://127.0.0.1:5174',
    channel: 'chrome',
    headless: true,
    actionTimeout: 15_000,
    navigationTimeout: 15_000,
    viewport: { width: 1440, height: 1000 },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
});
