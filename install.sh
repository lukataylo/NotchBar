#!/bin/bash
set -euo pipefail

APP_NAME="NotchBar"
APP_BUNDLE="${APP_NAME}.app"
BUILD_CONFIG="release"

echo ""
echo "  ${APP_NAME} Installer"
echo "  ====================="
echo ""

if ! command -v swift >/dev/null 2>&1; then
    echo "  x Swift was not found."
    echo "    Install Xcode Command Line Tools with:"
    echo "    xcode-select --install"
    exit 1
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "${MACOS_MAJOR}" -lt 13 ]; then
    echo "  x ${APP_NAME} requires macOS 13 or newer."
    echo "    Current version: $(sw_vers -productVersion)"
    exit 1
fi

echo "  -> Building ${APP_NAME} (${BUILD_CONFIG})..."
swift build -c "${BUILD_CONFIG}"
echo "  ok Build complete"

echo "  -> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp ".build/${BUILD_CONFIG}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "Sources/NotchBar/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
fi

RESOURCE_BUNDLE="$(find .build -name '*.bundle' | head -n 1 || true)"
if [ -n "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
fi

install_app() {
    local destination="$1"
    rm -rf "${destination}/${APP_BUNDLE}"
    cp -R "${APP_BUNDLE}" "${destination}/"
    echo "  ok Installed to ${destination}/${APP_BUNDLE}"
}

echo "  -> Installing..."
if [ -w /Applications ]; then
    install_app "/Applications"
elif [ -d "${HOME}/Applications" ] || mkdir -p "${HOME}/Applications" 2>/dev/null; then
    echo "  -> /Applications is not writable, using ~/Applications"
    install_app "${HOME}/Applications"
else
    echo "  -> Copying to /Applications with sudo"
    sudo rm -rf "/Applications/${APP_BUNDLE}"
    sudo cp -R "${APP_BUNDLE}" /Applications/
    echo "  ok Installed to /Applications/${APP_BUNDLE}"
fi

rm -rf "${APP_BUNDLE}"

echo ""
echo "  Note: this is an unsigned local build."
echo "  If Gatekeeper blocks first launch, open:"
echo "  System Settings -> Privacy & Security -> Open Anyway"
echo ""

INSTALLED_PATH="/Applications/${APP_BUNDLE}"
if [ -d "${HOME}/Applications/${APP_BUNDLE}" ]; then
    INSTALLED_PATH="${HOME}/Applications/${APP_BUNDLE}"
fi

echo "  -> Launching ${APP_NAME}..."
open "${INSTALLED_PATH}"

echo ""
echo "  ok ${APP_NAME} is installed."
echo "  Default shortcuts: Cmd+Shift+C toggle, Cmd+Shift+Y approve, Cmd+Shift+N reject."
echo "  On first launch, choose Claude hooks or install the Codex notchbar profile from onboarding."
echo ""
