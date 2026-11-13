// Render newly authored SVG artwork to transparent PNG; no generated raster edits.
import { chromium } from '@playwright/test'
import { readFileSync } from 'node:fs'
const browser = await chromium.launch()
try {
  const page = await browser.newPage({ deviceScaleFactor: 2 })
  for (const name of ['devdock-logo-light','devdock-logo-dark','devdock-mark','devdock-menubar']) {
    const svg = readFileSync(`docs/brand/midnight/${name}.svg`, 'utf8')
    const match = svg.match(/viewBox="0 0 (\d+) (\d+)"/)
    const width = Number(match[1]), height = Number(match[2])
    await page.setViewportSize({width, height})
    await page.setContent(`<style>html,body{margin:0;background:transparent}svg{display:block;width:${width}px;height:${height}px}</style>${svg}`)
    await page.screenshot({path:`docs/brand/midnight/${name}.png`,omitBackground:true})
  }
} finally { await browser.close() }
