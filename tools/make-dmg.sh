#!/bin/bash
# Builds ClipStack.dmg — a drag-to-Applications installer.
#
#   ./tools/make-dmg.sh
#
# Produces ./ClipStack.dmg with the app, an Applications shortcut, and a
# background showing where to drop it.
#
# The Finder layout step needs permission to control Finder. If that is
# unavailable (sandboxed CI, or the prompt is declined) the DMG is still built
# and still works — it just opens with the default icon arrangement.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="ClipStack.app"
VOLUME="ClipStack"
DMG="ClipStack.dmg"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
trap 'rm -rf "$WORK"; hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true' EXIT

echo "==> Building the app…"
./build.sh >/dev/null

echo "==> Staging…"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"

swiftc -O tools/make-dmg-background.swift -o "$WORK/make-bg"
"$WORK/make-bg" "$STAGE/.background/background.png" >/dev/null

# Give the volume the app's own icon.
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

echo "==> Creating disk image…"
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
    -format UDRW -ov "$WORK/rw.dmg" >/dev/null

MOUNT="$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen | \
    grep -o '/Volumes/.*' | head -1)"

echo "==> Arranging the window…"
if ! osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 840, 520}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 12
        set background picture of opts to file ".background:background.png"
        set position of item "$APP" of container window to {160, 200}
        set position of item "Applications" of container window to {480, 200}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT
then
    echo "    (skipped — could not control Finder; the DMG still works)"
fi

SetFile -a C "$MOUNT" 2>/dev/null || true
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync

hdiutil detach "$MOUNT" -quiet
echo "==> Compressing…"
rm -f "$DMG"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
