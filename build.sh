#!/bin/bash
# Build ClipStack.app from the SwiftPM package.
#   ./build.sh            → build/ClipStack.app
#   ./build.sh --install  → also copy to /Applications and launch
#
# Signing: set CODESIGN_IDENTITY to a "Developer ID Application: …" identity
# for distribution (adds hardened runtime + secure timestamp). Defaults to
# ad-hoc, which is enough for a locally built, locally run app.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c release

APP="build/ClipStack.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClipStack "$APP/Contents/MacOS/ClipStack"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.tiff "$APP/Contents/Resources/MenuBarIcon.tiff"
for lproj in Resources/*.lproj; do
  plutil -lint "$lproj/Localizable.strings" >/dev/null
  cp -R "$lproj" "$APP/Contents/Resources/"
done
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
  echo "Built $APP (ad-hoc signed)"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=1 "$APP"
  echo "Built $APP (signed: $IDENTITY)"
fi

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ClipStack 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/ClipStack.app
  cp -R "$APP" /Applications/
  open /Applications/ClipStack.app
  echo "Installed and launched /Applications/ClipStack.app"
fi
