import { test, expect } from '@playwright/test'

test('English pages render without third-party requests or console errors', async ({ page }, testInfo) => {
  const errors: string[] = [], external: string[] = []
  page.on('pageerror', error => errors.push(error.message))
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()) })
  page.on('request', request => { if (!request.url().startsWith('http://127.0.0.1:39877')) external.push(request.url()) })
  const response = await page.goto('/')
  expect(response?.headers()['x-content-type-options']).toBe('nosniff')
  expect(response?.headers()['x-powered-by']).toBeUndefined()
  await expect(page.locator('html')).toHaveAttribute('lang', 'en')
  await expect(page.locator('footer')).toContainText('George Levis')
  await expect(page.locator('footer a[href="https://github.com/levgiorg/DevDock"]')).toBeAttached()
  await page.getByRole('heading', { name: 'Clear, consistent English.' }).scrollIntoViewIfNeeded()
  await expect(page.getByRole('heading', { name: 'Clear, consistent English.' })).toBeVisible()
  await expect(page.locator('body')).not.toContainText(/Simplified Chinese|Your language\./)
  await page.screenshot({ path: `.context/web-${testInfo.project.name}-english.png`, fullPage: false })
  await page.goto('/guides/change-app-language')
  await expect(page.getByRole('heading', { name: 'English interface in DevDock' })).toBeVisible()
  expect(errors).toEqual([])
  expect(external).toEqual([])
})

test('demo requires confirmation and keeps stopped containers startable', async ({ page }, testInfo) => {
  await page.goto('/guides')
  await page.getByRole('button', { name: 'Try DevDock' }).click()
  const panel = page.getByRole('dialog', { name: 'DevDock demo' })
  await expect(panel).toBeVisible()
  const container = panel.locator('[role=button]').filter({ hasText: '5432' }).first()
  await page.mouse.move(0, 0)
  const relativeMemoryBounds = () => container.evaluate(row => {
    const bounds = row.getBoundingClientRect()
    const memory = row.querySelector('[class*="rowMemory"]')!.getBoundingClientRect()
    return { x: (memory.x - bounds.x) / bounds.width, width: memory.width / bounds.width }
  })
  const beforeHover = await relativeMemoryBounds()
  await container.hover()
  const duringHover = await relativeMemoryBounds()
  expect(duringHover.x).toBeCloseTo(beforeHover.x, 3)
  expect(duringHover.width).toBeCloseTo(beforeHover.width, 3)
  page.once('dialog', dialog => dialog.accept())
  await container.getByRole('button', { name: 'Stop', exact: true }).click()
  await expect(panel).toContainText('Stopped')
  await container.hover()
  page.once('dialog', dialog => dialog.accept())
  await container.getByRole('button', { name: 'Start container', exact: true }).click()
  await expect(panel).not.toContainText('Stopped')
  await page.screenshot({ path: `.context/web-${testInfo.project.name}-demo.png`, fullPage: false })
})

test('Markdown routes and removed telemetry endpoint have safe behavior', async ({ request }) => {
  const markdown = await request.get('/index.md')
  expect(markdown.status()).toBe(200)
  expect(markdown.headers()['content-type']).toContain('text/markdown')
  expect(await markdown.text()).toContain('Telemetry is disabled')
  expect((await request.get('/usage/stop')).status()).toBe(404)
  expect((await request.get('/md/../../etc/passwd')).status()).toBe(404)
})

// A source-only CI preview has no artifact; a local packaged preview serves DevDock itself.
test('download serves only the local DevDock artifact', async ({ request }) => {
  const response = await request.head('/DevDock.dmg', { maxRedirects: 0 })
  expect([200, 404]).toContain(response.status())
  expect(response.headers().location).toBeUndefined()
})
