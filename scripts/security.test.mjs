import assert from 'node:assert/strict'
import { test } from 'node:test'
import { readFileSync, readdirSync } from 'node:fs'
import { APP_LANGUAGES, localizer } from '../app/components/languages.ts'
import { renderMarkdown } from '../lib/content.ts'

test('interface has only English and preserves Unicode project names', () => {
  assert.deepEqual(APP_LANGUAGES.map(x => x.code), ['en'])
  assert.deepEqual(readdirSync('DevDock/Sources/DevDock/Resources').filter(x => x.endsWith('.lproj')), ['en.lproj'])
  const l = localizer('en')
  assert.equal(l.text('Settings'), 'Settings')
  assert.equal(l.text('\u4e2d\u6587/café'), '\u4e2d\u6587/café')
  assert.equal(l.format('Stop %d %@', 2, 'servers'), 'Stop 2 servers')
})

test('Markdown sanitization blocks scripts, handlers, external schemes and SVG', () => {
  const html = renderMarkdown('# Hello\n<script>alert(1)</script><img src=x onerror="alert(1)"><a href="javascript:alert(1)">x</a><svg onload=alert(1)></svg>')
  assert.match(html, /<h1 id="hello">Hello<\/h1>/)
  assert.doesNotMatch(html, /<script|onerror|javascript:|<svg|onload/i)
  assert.match(renderMarkdown('[Safe](https://example.com)\n![Local](/screenshot.png)'), /href="https:\/\/example.com"/)
  assert.match(renderMarkdown('![Local](/screenshot.png)'), /src="\/screenshot.png"/)
})

test('telemetry dependencies and native update defaults stay disabled', () => {
  const pkg = JSON.parse(readFileSync('package.json', 'utf8'))
  assert(!Object.keys(pkg.dependencies).some(x => /analytics|speed-insights/.test(x)))
  const usage = readFileSync('DevDock/Sources/DevDock/Engine/Usage.swift', 'utf8')
  assert.doesNotMatch(usage, /URLSession|https:\/\//)
  const plist = readFileSync('DevDock/Info.plist', 'utf8')
  for (const key of ['SUEnableAutomaticChecks', 'SUAutomaticallyUpdate']) {
    assert.match(plist, new RegExp(`<key>${key}</key>\\s*<false/>`))
  }
})
