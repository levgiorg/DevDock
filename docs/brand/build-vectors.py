#!/usr/bin/env python3
"""Author deterministic mark assets from the approved vector contours.
Run with: uv run --with fonttools python docs/brand/build-vectors.py
No generated raster image is edited by this script.
"""
from pathlib import Path
import json
from fontTools.pens.recordingPen import RecordingPen
from fontTools.svgLib.path import parse_path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/brand/midnight'
OUT.mkdir(exist_ok=True)
PATHS = [
    'M48 4H75C91 4 98 13 98 28H49C32 28 24 36 24 52V76C24 92 32 100 49 100H65C63 109 67 118 75 124H47C17 124 0 108 0 78V50C0 20 17 4 48 4Z',
    'M98 4H116C146 4 164 20 164 50V78C164 108 146 124 116 124H89C73 124 66 115 66 100H115C132 100 140 92 140 76V52C140 36 132 28 115 28H109C111 19 107 10 98 4Z',
]
def svg(body, w, h):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" role="img" aria-label="DevDock">{body}</svg>\n'

def mark(colors):
    return ''.join(f'<path fill="{color}" d="{path}"/>' for color,path in zip(colors,PATHS))

# The existing wordmarks are frozen, outlined artwork and contain no font software.
(OUT / 'devdock-mark.svg').write_text(svg(mark(['#4B8DFF', '#5AE0CA']), 164, 128))
(OUT / 'devdock-menubar.svg').write_text(svg(mark(['#000000', '#000000']), 164, 128))
(OUT / 'mark-paths.json').write_text(json.dumps(PATHS, indent=2)+'\n')
# The same paths drive the AppKit template icon at native small sizes.
lines=['import AppKit', '', '/// DevDock vector master; shared with docs/brand/midnight/devdock-mark.svg.', 'enum DevDockMark {', '    static func paths() -> [NSBezierPath] {', '        var paths: [NSBezierPath] = []']
for path in PATHS:
    pen=RecordingPen(); parse_path(path,pen)
    lines.append('        do {\n            let path = NSBezierPath()')
    for op, pts in pen.value:
        def point(p): return f'NSPoint(x: {p[0]:g}, y: {p[1]:g})'
        if op=='moveTo': lines.append('            path.move(to: '+point(pts[0])+')')
        elif op=='lineTo': lines.append('            path.line(to: '+point(pts[0])+')')
        elif op=='curveTo': lines.append('            path.curve(to: '+point(pts[2])+', controlPoint1: '+point(pts[0])+', controlPoint2: '+point(pts[1])+')')
        elif op in ('closePath','endPath'): lines.append('            path.close()')
        else: raise ValueError(op)
    lines.append('            paths.append(path)\n        }')
lines.extend(['        return paths', '    }', '', '    static func draw(in rect: CGRect) {', '        let transform = AffineTransform(m11: rect.width / 164, m12: 0, m21: 0, m22: rect.height / 128, tX: rect.minX, tY: rect.minY)', '        for path in paths() { path.transform(using: transform); path.fill() }', '    }', '}'])
(ROOT/'DevDock/Sources/DevDock/UI/DevDockMark.swift').write_text('\n'.join(lines)+'\n')
# A code-native website icon keeps exactly the same contours.
component='''import type { CSSProperties } from 'react'
export function DevDockLogo({ size = 28, color }: { size?: number; color?: string }) {
  return <svg width={size} height={size * 128 / 164} viewBox="0 0 164 128" aria-hidden="true" style={{ flexShrink: 0 } as CSSProperties}>
'''
for path,color in zip(PATHS,['#4B8DFF','#5AE0CA']): component+=f'    <path d="{path}" fill={{color ?? "{color}"}} />\n'
component+='  </svg>\n}\n'
(ROOT/'app/components/DevDockLogo.tsx').write_text(component)
print('Authored SVG outlines, AppKit paths and matching website mark.')
