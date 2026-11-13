#!/usr/bin/env python3
"""Repository-specific static checks; complement, never replace, external scanners."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
errors = []
for name in sorted(set(files)):
    p = root / name
    if not p.is_file() or p.suffix not in {'.swift', '.ts', '.tsx', '.json', '.md', '.mjs', '.py', '.sh', '.strings', '.go', '.yml'}:
        continue
    text = p.read_text(errors='replace')
    if re.search('[\u3400-\u9fff\uf900-\ufaff\u3040-\u30ff]', text):
        errors.append(f'{name}: non-English CJK source content')
    if name.startswith(('DevDock/Sources/', 'app/')):
        for pattern in [r'NSAppleScript', r'with administrator privileges', r'@vercel/analytics', r'@vercel/speed-insights', r'fetch\(\s*[\'"]https?://']:
            if re.search(pattern, text): errors.append(f'{name}: forbidden automatic network or privileged execution pattern {pattern}')
    if name.endswith('.sh'):
        if 'set -euo pipefail' not in text and 'set -Eeuo pipefail' not in text:
            errors.append(f'{name}: missing strict shell mode')
if errors:
    raise SystemExit('\n'.join(errors))
print('Repository policy scan passed: English source, no telemetry imports, no privileged AppleScript, strict shell scripts.')
