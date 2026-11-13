import { NextResponse, type NextRequest } from 'next/server'

// Agents can read any page as Markdown (app/md): add .md to its URL, or ask
// for text/markdown ahead of HTML in the Accept header.
function prefersMarkdown(accept: string) {
  const markdown = accept.indexOf('text/markdown')
  const html = accept.indexOf('text/html')
  return markdown >= 0 && (html < 0 || markdown < html)
}

function markdownPath(pathname: string, accept: string) {
  if (pathname.endsWith('.md')) return `/md${pathname === '/index.md' ? '/index' : pathname.slice(0, -3)}`
  if (prefersMarkdown(accept)) return `/md${pathname === '/' ? '/index' : pathname.replace(/\/$/, '')}`
  return null
}

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Routing runs before page caching, so HTML and Markdown can share a URL.
  const markdown = markdownPath(pathname, request.headers.get('accept') ?? '')
  return markdown ? NextResponse.rewrite(new URL(markdown, request.url)) : NextResponse.next()
}

export const config = { matcher: ['/', '/index.md', '/guides', '/guides.md', '/guides/:path*'] }
