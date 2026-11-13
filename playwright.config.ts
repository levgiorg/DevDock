import { defineConfig, devices } from '@playwright/test'
export default defineConfig({
  testDir: './tests/web',
  fullyParallel: true,
  use: { baseURL: 'http://127.0.0.1:39877', trace: 'retain-on-failure' },
  webServer: {
    command: 'npm run start -- --hostname 127.0.0.1 --port 39877',
    url: 'http://127.0.0.1:39877', reuseExistingServer: false,
    env: { NEXT_TELEMETRY_DISABLED: '1' },
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['iPhone 13'], defaultBrowserType: 'chromium' } },
  ],
})
