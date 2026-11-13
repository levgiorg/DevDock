#!/bin/bash
set -Eeuo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_OS:-}" != Linux ]]; then
    echo "Install Gitleaks with your local package manager outside GitHub Linux CI." >&2
    exit 1
fi
VERSION=8.30.1
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT
ARCH=linux_x64
if [[ "$(uname -m)" == aarch64 ]]; then ARCH=linux_arm64; fi
ASSET="gitleaks_${VERSION}_${ARCH}.tar.gz"
BASE="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "${BASE}/${ASSET}" -o "${STAGING}/${ASSET}"
EXPECTED=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
if [[ "${ARCH}" == linux_arm64 ]]; then EXPECTED=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080; fi
(cd "${STAGING}" && printf '%s  %s\n' "${EXPECTED}" "${ASSET}" | sha256sum --check --strict)
tar -xzf "${STAGING}/${ASSET}" -C "${STAGING}" gitleaks
mkdir -p "${RUNNER_TEMP}/devdock-tools"
install -m 0755 "${STAGING}/gitleaks" "${RUNNER_TEMP}/devdock-tools/gitleaks"
echo "${RUNNER_TEMP}/devdock-tools" >> "${GITHUB_PATH}"
