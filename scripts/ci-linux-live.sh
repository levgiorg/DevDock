#!/bin/bash
# GitHub's disposable Linux runner only; never mount a developer's Docker socket.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_OS:-}" != Linux ]]; then
    echo "This harness is restricted to disposable GitHub Linux runners." >&2
    exit 1
fi
NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')"
TARGET=""
SENTINEL=""
cleanup() {
    local id label
    for id in "${TARGET}" "${SENTINEL}"; do
        if [[ -n "${id}" ]]; then
            label="$(docker inspect -f '{{ index .Config.Labels "com.devdock.ci" }}' "${id}" 2>/dev/null || true)"
            if [[ "${label}" == "${NONCE}" ]]; then docker rm -f "${id}" >/dev/null; fi
        fi
    done
}
trap cleanup EXIT
IMAGE="busybox@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec"
docker pull "${IMAGE}" >/dev/null
ARGS=(--detach --label "com.devdock.ci=${NONCE}" --read-only --cap-drop=ALL
      --security-opt=no-new-privileges --user 65534:65534 --memory 32m --cpus 0.25
      --publish 127.0.0.1::8080 "${IMAGE}" httpd -f -p 8080)
TARGET="$(docker run "${ARGS[@]}")"
SENTINEL="$(docker run "${ARGS[@]}")"
export DEVDOCK_TEST_CONTAINER="${TARGET}" DEVDOCK_TEST_SENTINEL="${SENTINEL}"
(cd linux && go test -race -count=1 -v -run TestDockerActualLifecycle .)
