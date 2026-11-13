#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export GOTELEMETRY=off
VERSION="${1:-development}"
ARCH="${2:-amd64}"
if [[ ! "${VERSION}" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ || ! "${ARCH}" =~ ^(amd64|arm64)$ ]]; then
    echo "Usage: $0 <version> <amd64|arm64>" >&2
    exit 1
fi
ROOT="$(pwd -P)"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT
NAME="DevDock-${VERSION}-linux-${ARCH}"
mkdir -p "${ROOT}/dist" "${STAGING}/${NAME}"
(
    cd linux
    CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X main.version=${VERSION}" -o "${STAGING}/${NAME}/devdock" .
)
cp LICENSE THIRD_PARTY_NOTICES.md linux/README.md "${STAGING}/${NAME}/"
tar -czf "${ROOT}/dist/${NAME}.tar.gz" -C "${STAGING}" "${NAME}"
echo "Built dist/${NAME}.tar.gz"
