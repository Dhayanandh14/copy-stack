#!/bin/bash
# Builds ClipStack.app from source using Command Line Tools only.
#   ./build.sh            build the .app next to this script
#   ./build.sh install    build, then move it into /Applications and launch it
set -euo pipefail
cd "$(dirname "$0")"

APP="ClipStack.app"
BIN=".build/release/ClipStack"

echo "==> Compiling (release)…"
swift build -c release

echo "==> Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipStack"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon. Regenerate from source if it is missing, so a fresh clone still
# builds a bundle that looks finished.
if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> Generating app icon…"
    ICONWORK="$(mktemp -d)"
    swiftc -O tools/make-icon.swift -o "$ICONWORK/make-icon"
    "$ICONWORK/make-icon" "$ICONWORK/AppIcon.iconset"
    iconutil -c icns "$ICONWORK/AppIcon.iconset" -o Resources/AppIcon.icns
    rm -rf "$ICONWORK"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A stable signing identity matters more than it sounds: macOS ties the
# Accessibility grant to the code signature. Ad-hoc signatures change on every
# build, so each reinstall silently revoked the permission. Signing with a
# fixed local certificate keeps the grant across rebuilds.
IDENTITY="ClipStack Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "==> Signing as '$IDENTITY'…"
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "==> WARNING: signing identity '$IDENTITY' not found; using ad-hoc."
    echo "    Accessibility permission will need re-granting after every build."
    echo "    Run ./tools/make-signing-cert.sh once to fix that."
    codesign --force --sign - "$APP"
fi

if [[ "${1:-}" == "install" ]]; then
    echo "==> Installing to /Applications…"
    osascript -e 'quit app "ClipStack"' 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP"
    cp -R "$APP" "/Applications/$APP"
    open "/Applications/$APP"
    echo "==> Running. Look for the clipboard icon in your menu bar."
else
    echo "==> Built ./${APP} — run ./build.sh install to put it in /Applications."
fi
