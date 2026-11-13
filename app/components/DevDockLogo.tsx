import type { CSSProperties } from 'react'
export function DevDockLogo({ size = 28, color }: { size?: number; color?: string }) {
  return <svg width={size} height={size * 128 / 164} viewBox="0 0 164 128" aria-hidden="true" style={{ flexShrink: 0 } as CSSProperties}>
    <path d="M48 4H75C91 4 98 13 98 28H49C32 28 24 36 24 52V76C24 92 32 100 49 100H65C63 109 67 118 75 124H47C17 124 0 108 0 78V50C0 20 17 4 48 4Z" fill={color ?? "#4B8DFF"} />
    <path d="M98 4H116C146 4 164 20 164 50V78C164 108 146 124 116 124H89C73 124 66 115 66 100H115C132 100 140 92 140 76V52C140 36 132 28 115 28H109C111 19 107 10 98 4Z" fill={color ?? "#5AE0CA"} />
  </svg>
}
