#!/bin/bash
set -uo pipefail

APP_NAME="NotchBar"
APP_BUNDLE="${APP_NAME}.app"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_APP="${ROOT_DIR}/dist/${APP_BUNDLE}"
LOCAL_APP="${ROOT_DIR}/${APP_BUNDLE}"
INSTALL_PATH=""

header() {
    echo ""
    echo "  ${APP_NAME} Installer"
    echo "  ====================="
    echo ""
}

info() {
    echo "  -> $1"
}

ok() {
    echo "  ok $1"
}

warn() {
    echo "  ! $1"
}

fail() {
    echo "  x $1"
    echo ""
    echo "  Press Enter to close."
    read -r _
    exit 1
}

build_app_if_needed() {
    if [ -d "${DIST_APP}" ]; then
        ok "Using prebuilt app bundle from dist/"
        return
    fi

    if [ -d "${LOCAL_APP}" ]; then
        ok "Using local app bundle in repository root"
        return
    fi

    if ! command -v swift >/dev/null 2>&1; then
        fail "Swift was not found. For a no-build install, download the release DMG from GitHub Releases, or install Xcode Command Line Tools with: xcode-select --install"
    fi

    local macos_major
    macos_major="$(sw_vers -productVersion | cut -d. -f1)"
    if [ "${macos_major}" -lt 13 ]; then
        fail "${APP_NAME} requires macOS 13 or newer. Current version: $(sw_vers -productVersion)"
    fi

    info "No prebuilt app found. Building ${APP_NAME} from source..."
    if ! "${ROOT_DIR}/scripts/build_app.sh"; then
        fail "Build failed. If you only want to install the app, use the packaged DMG from Releases instead of building from source."
    fi
}

source_app_path() {
    if [ -d "${DIST_APP}" ]; then
        echo "${DIST_APP}"
        return
    fi
    if [ -d "${LOCAL_APP}" ]; then
        echo "${LOCAL_APP}"
        return
    fi
    echo "${DIST_APP}"
}

install_app() {
    local app_source="$1"
    local destination="$2"

    mkdir -p "${destination}" || return 1
    rm -rf "${destination:?}/${APP_BUNDLE}" || return 1
    cp -R "${app_source}" "${destination}/" || return 1
    INSTALL_PATH="${destination}/${APP_BUNDLE}"
}

launch_app() {
    info "Launching ${APP_NAME}..."
    if ! open "${INSTALL_PATH}"; then
        warn "Launch command failed. You can still open ${INSTALL_PATH} manually."
    fi
}

print_next_steps() {
    echo ""
    ok "${APP_NAME} is installed at ${INSTALL_PATH}"
    echo ""
    echo "  First launch notes:"
    echo "  - If macOS blocks the app because it is unsigned, right-click it and choose Open."
    echo "  - If that still fails, go to System Settings -> Privacy & Security -> Open Anyway."
    echo "  - During onboarding, choose Claude hooks or the Codex notchbar profile."
    echo "  - Accessibility and Automation are only needed for send-input / resume features."
    echo ""
}

header

if [ ! -x "${ROOT_DIR}/scripts/build_app.sh" ]; then
    fail "scripts/build_app.sh is missing or not executable."
fi

build_app_if_needed
APP_SOURCE="$(source_app_path)"

if [ ! -d "${APP_SOURCE}" ]; then
    fail "Could not find a built app bundle to install."
fi

info "Installing ${APP_NAME}..."
if [ -w /Applications ]; then
    install_app "${APP_SOURCE}" "/Applications" || fail "Failed to copy the app into /Applications."
elif mkdir -p "${HOME}/Applications" 2>/dev/null; then
    warn "/Applications is not writable. Installing to ~/Applications instead."
    install_app "${APP_SOURCE}" "${HOME}/Applications" || fail "Failed to copy the app into ~/Applications."
else
    fail "Could not find a writable Applications folder."
fi

launch_app
print_next_steps
