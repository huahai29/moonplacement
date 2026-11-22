import { defineConfig } from '@playwright/test';

const port = Number(process.env.MOONPLACEMENT_WEB_PORT || 4174);
const baseURL = `http://127.0.0.1:${port}`;

export default defineConfig({
  testDir: './tests',
  reporter: 'list',
  workers: 2,
  use: {
    baseURL,
    launchOptions: { executablePath: process.env.MOONPLACEMENT_BROWSER || undefined },
  },
  webServer: {
    command: 'node serve.mjs',
    url: baseURL,
    reuseExistingServer: false,
  },
});
