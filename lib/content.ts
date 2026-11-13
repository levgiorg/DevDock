import fs from 'node:fs'
import path from 'node:path'
import { Marked } from 'marked'
import sanitizeHtml from 'sanitize-html'

// The site's written content lives in content/ as Markdown, so the same source
// renders the HTML pages and the .md versions that agents read (/index.md,
// /guides/<slug>.md, /llms.txt, /llms-full.txt).

export const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'
export const SITE_NAME = 'DevDock'
export const SITE_TITLE = 'DevDock: see every dev server and port on your Mac'
export const SITE_DESCRIPTION =
  'A free, open-source macOS menu bar app that shows what’s running on localhost: every dev server’s port, project, git branch, memory and the Claude Code, Codex, Conductor or Pane session that started it. Stop the ones you forgot in one click.'
export const AUTHOR = { name: 'George Levis', url: 'https://github.com/levgiorg' }
export const GITHUB_URL = 'https://github.com/levgiorg/DevDock'
export const OG_IMAGE = {
  url: '/brand/github-banner.png',
  width: 1774,
  height: 887,
  alt: 'DevDock: Ports, Processes, Containers. Midnight blue and teal identity.',
}

const CONTENT = path.join(process.cwd(), 'content')

export type Guide = {
  slug: string
  title: string
  description: string
  published: string
  updated: string
  order: number
  keywords: string[]
  markdown: string
}

// A small frontmatter block of `key: value` lines between --- fences.
function parse(file: string) {
  const source = fs.readFileSync(file, 'utf8')
  const match = source.match(/^---\n([\s\S]*?)\n---\n+([\s\S]*)$/)
  if (!match) return { data: {} as Record<string, string>, body: source }
  const data: Record<string, string> = {}
  for (const line of match[1].split('\n')) {
    const colon = line.indexOf(':')
    if (colon > 0) data[line.slice(0, colon).trim()] = line.slice(colon + 1).trim()
  }
  return { data, body: match[2] }
}

export function getGuides(): Guide[] {
  const dir = path.join(CONTENT, 'guides')
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith('.md'))
    .map((name) => {
      const { data, body } = parse(path.join(dir, name))
      return {
        slug: name.replace(/\.md$/, ''),
        title: data.title,
        description: data.description,
        published: data.published,
        updated: data.updated || data.published,
        order: Number(data.order) || 99,
        keywords: (data.keywords || '').split(',').map((k) => k.trim()).filter(Boolean),
        markdown: body.trim(),
      }
    })
    .sort((a, b) => a.order - b.order || a.title.localeCompare(b.title))
}

export function getGuide(slug: string) {
  return getGuides().find((guide) => guide.slug === slug)
}

// The product overview agents get at /index.md and at the top of /llms-full.txt.
export function getOverview() {
  return fs.readFileSync(path.join(CONTENT, 'devdock.md'), 'utf8').trim()
}

const slugify = (text: string) =>
  text
    .toLowerCase()
    .replace(/<[^>]+>|&[a-z0-9#]+;/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')

// Headings get ids so sections can be linked to directly.
const marked = new Marked({
  gfm: true,
  renderer: {
    heading({ tokens, depth }) {
      const html = this.parser.parseInline(tokens)
      return `<h${depth} id="${slugify(html)}">${html}</h${depth}>\n`
    },
  },
})

export function renderMarkdown(markdown: string) {
  return sanitizeHtml(marked.parse(markdown, { async: false }), {
    allowedTags: [...sanitizeHtml.defaults.allowedTags, 'img'],
    allowedAttributes: { ...sanitizeHtml.defaults.allowedAttributes, '*': ['id'], img: ['src', 'alt', 'width', 'height'] },
    allowedSchemes: ['https', 'http', 'mailto'],
    allowProtocolRelative: false,
  })
}

// A rough reading time, at 220 words a minute.
export function readingMinutes(markdown: string) {
  return Math.max(1, Math.round(markdown.split(/\s+/).length / 220))
}

// The article as a standalone Markdown document, with its canonical URL.
export function guideMarkdown(guide: Guide) {
  return [
    `# ${guide.title}`,
    `> ${guide.description}`,
    `Canonical: ${SITE_URL}/guides/${guide.slug} · Updated ${guide.updated}`,
    guide.markdown,
  ].join('\n\n')
}

// The app version, read from the Mac app's Info.plist by next.config.js at build time.
// The native source directory is optional when hosting the website.
export function appVersion() {
  return process.env.APP_VERSION || undefined
}
