#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export NEXT_TELEMETRY_DISABLED=1
npm run verify
swift test --package-path DevDock -j 4
python3 DevDock/scripts/test-configure-updates.py
shellcheck DevDock/*.sh scripts/verify.sh
gitleaks git --redact
git diff --check
