import { notFound } from 'next/navigation'
import { markdownDocs, markdownResponse } from '@/lib/markdown-docs'

// Markdown copies of each page. proxy.ts rewrites /index.md, /guides.md and
// /guides/<slug>.md here, and so do requests that ask for text/markdown.

export const dynamicParams = false

export function generateStaticParams() {
  return Array.from(markdownDocs().keys()).map((key) => ({ path: key.split('/') }))
}

export async function GET(_request: Request, { params }: { params: Promise<{ path: string[] }> }) {
  const doc = markdownDocs().get((await params).path.join('/'))
  if (!doc) notFound()
  return markdownResponse(doc.markdown + '\n', doc.canonical)
}
