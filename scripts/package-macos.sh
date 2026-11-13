#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
VERSION="${1:-}"
BUILD="${2:-}"
MODE="${3:-development}"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ || ! "${BUILD}" =~ ^[0-9]+$ ]]; then
    echo "Usage: $0 <version> <build-number> <development|notarized>" >&2
    exit 1
fi
if [[ "${MODE}" != development && "${MODE}" != notarized ]]; then echo "Invalid signing mode" >&2; exit 1; fi
export WTP_VERSION="${VERSION%%-*}" WTP_BUILD="${BUILD}"
SUFFIX="unnotarized"
BUILD_ARGS=()
if [[ "${MODE}" == notarized ]]; then
    : "${CODE_SIGN_IDENTITY:?A Developer ID Application identity is required}"
    : "${NOTARY_API_KEY_PATH:?An Apple notarization API key file is required}"
    : "${NOTARY_API_KEY_ID:?An Apple notarization API key ID is required}"
    : "${NOTARY_API_ISSUER_ID:?An Apple notarization issuer ID is required}"
    if [[ "${CODE_SIGN_IDENTITY}" == - ]]; then echo "Ad-hoc signing cannot be notarized" >&2; exit 1; fi
    SUFFIX="notarized"
    BUILD_ARGS=(--distribution)
else
    export CODE_SIGN_IDENTITY=-
fi
./DevDock/build-app.sh ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}
APP="DevDock/.build/DevDock.app"
if [[ "${MODE}" == notarized ]]; then
    ditto -c -k --sequesterRsrc --keepParent "${APP}" DevDock/.build/notarize.zip
    xcrun notarytool submit DevDock/.build/notarize.zip --key "${NOTARY_API_KEY_PATH}" \
        --key-id "${NOTARY_API_KEY_ID}" --issuer "${NOTARY_API_ISSUER_ID}" --wait
    xcrun stapler staple "${APP}"
    xcrun stapler validate "${APP}"
    spctl --assess --type execute --verbose=2 "${APP}"
fi
mkdir -p dist
OUTPUT="dist/DevDock-${VERSION}-macos-arm64-${SUFFIX}.dmg"
./DevDock/make-dmg.sh .build/DevDock.app "../${OUTPUT}"
if [[ "${MODE}" == notarized ]]; then
    xcrun notarytool submit "${OUTPUT}" --key "${NOTARY_API_KEY_PATH}" \
        --key-id "${NOTARY_API_KEY_ID}" --issuer "${NOTARY_API_ISSUER_ID}" --wait
    xcrun stapler staple "${OUTPUT}"
    xcrun stapler validate "${OUTPUT}"
fi
hdiutil verify "${OUTPUT}"
echo "Prepared ${OUTPUT}; this script never publishes a release."
