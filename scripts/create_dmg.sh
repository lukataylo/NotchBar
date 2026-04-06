#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NotchBar"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
VERSION="$(tr -d '\n' < "${ROOT_DIR}/VERSION")"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STAGING_DIR="${DIST_DIR}/dmg-staging"
README_PATH="${STAGING_DIR}/Install NotchBar.txt"

# Code signing + notarization config
# Override with env vars, or set SIGN_IDENTITY="" for unsigned builds.
# Uses SHA-1 hash to avoid ambiguity when multiple certs exist.
SIGN_IDENTITY="${SIGN_IDENTITY:-4D77EE9729D712C71A67E3E3657C9A17EC6F6122}"
APPLE_ID="${APPLE_ID:-luka.taylor@gmail.com}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-5QC5886P5V}"
NOTARIZE="${NOTARIZE:-}"

cd "${ROOT_DIR}"

cleanup() {
    rm -rf "${STAGING_DIR}"
}

trap cleanup EXIT

# Build the app (passes SIGN_IDENTITY through)
"${ROOT_DIR}/scripts/build_app.sh"

mkdir -p "${STAGING_DIR}"
rm -rf "${STAGING_DIR:?}/"*

cp -R "${APP_DIR}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

cat > "${README_PATH}" <<'EOF'
NotchBar install steps
======================

1. Drag NotchBar.app into Applications.
2. Open NotchBar from Applications.
3. If macOS warns because this is an unsigned build:
   - right-click the app and choose Open, or
   - go to System Settings -> Privacy & Security -> Open Anyway
4. On first launch, complete onboarding for Claude or Codex.

Optional permissions
--------------------

- Accessibility: required to send input back to Terminal/iTerm
- Automation: required to control Terminal/iTerm for resume/send-input flows
EOF

rm -f "${DMG_PATH}"

hdiutil create \
    -volname "NotchBar Installer" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

echo "==> DMG ready at ${DMG_PATH}"

# Sign the DMG itself
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Signing DMG"
    codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${DMG_PATH}"
fi

# Notarize if requested
if [ "${NOTARIZE}" = "1" ] && [ -n "${SIGN_IDENTITY}" ]; then
    if [ -z "${APPLE_ID}" ] || [ -z "${APPLE_TEAM_ID}" ]; then
        echo "ERROR: APPLE_ID and APPLE_TEAM_ID are required for notarization."
        echo "  export APPLE_ID=\"your@email.com\""
        echo "  export APPLE_TEAM_ID=\"YOURTEAMID\""
        exit 1
    fi

    echo "==> Submitting for notarization (this may take a few minutes)..."
    xcrun notarytool submit "${DMG_PATH}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --keychain-profile "notchbar-notarize" \
        --wait

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "${DMG_PATH}"

    echo "==> Verifying notarization"
    spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}" 2>&1 || true

    echo "==> Notarized DMG ready at ${DMG_PATH}"
else
    if [ -n "${SIGN_IDENTITY}" ]; then
        echo ""
        echo "TIP: To notarize, first store credentials:"
        echo "  xcrun notarytool store-credentials notchbar-notarize \\"
        echo "    --apple-id YOUR_EMAIL --team-id YOUR_TEAM_ID"
        echo "Then run: NOTARIZE=1 $0"
    fi
fi
