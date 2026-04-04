#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NotchBar"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
VERSION="$(tr -d '\n' < "${ROOT_DIR}/VERSION")"

# Code signing configuration
# Set SIGN_IDENTITY to your Developer ID Application certificate, e.g.:
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# Leave empty or unset for ad-hoc signing (local dev only).
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

cd "${ROOT_DIR}"

if ! command -v swift >/dev/null 2>&1; then
    echo "Swift is required to build ${APP_NAME} from source."
    echo "Install Xcode Command Line Tools with: xcode-select --install"
    exit 1
fi

echo "==> Building ${APP_NAME} ${VERSION} (${BUILD_CONFIG})"
swift build -c "${BUILD_CONFIG}"

echo "==> Creating app bundle"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp ".build/${BUILD_CONFIG}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/"
cp "Sources/NotchBar/Info.plist" "${APP_DIR}/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/"
fi

RESOURCE_BUNDLE="$(find ".build/${BUILD_CONFIG}" -name '*.bundle' | head -n 1 || true)"
if [ -n "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/"
fi

# Strip extended attributes (resource forks break codesign)
xattr -cr "${APP_DIR}"

# Entitlements for hardened runtime
ENTITLEMENTS="${ROOT_DIR}/Sources/NotchBar/NotchBar.entitlements"

if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Signing with: ${SIGN_IDENTITY}"
    codesign --force --deep --options runtime \
        --sign "${SIGN_IDENTITY}" \
        --entitlements "${ENTITLEMENTS}" \
        --timestamp \
        "${APP_DIR}"
    echo "==> Verifying signature"
    codesign --verify --deep --strict "${APP_DIR}"
    spctl --assess --type execute --verbose "${APP_DIR}" 2>&1 || true
else
    echo "==> Applying ad-hoc code signature (set SIGN_IDENTITY for distribution)"
    codesign --force --deep --sign - "${APP_DIR}" >/dev/null
fi

echo "==> App bundle ready at ${APP_DIR}"
