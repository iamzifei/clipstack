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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/ClipStack "$APP/Contents/MacOS/ClipStack"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for lproj in Resources/*.lproj; do
  plutil -lint "$lproj/Localizable.strings" >/dev/null
  cp -R "$lproj" "$APP/Contents/Resources/"
done
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Bundle Sparkle.framework (auto-update). SwiftPM fetches it as a binary
# XCFramework; copy the macOS slice into the app so it resolves at runtime.
SPARKLE_FW=$(find .build -type d -name "Sparkle.framework" -path "*macos*" 2>/dev/null | head -1)
if [ -z "$SPARKLE_FW" ]; then
  echo "ERROR: Sparkle.framework not found under .build — run 'swift build' first." >&2
  exit 1
fi
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
FW="$APP/Contents/Frameworks/Sparkle.framework"

# codesign helper: hardened runtime + timestamp for Developer ID, else ad-hoc.
sign() {
  if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$1"
  else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
  fi
}

# Sign Sparkle's nested code inside-out (XPC services → helpers → framework)
# before signing the outer app; every nested Mach-O must be signed for the
# notary to accept the bundle.
for xpc in "$FW"/Versions/B/XPCServices/*.xpc; do
  [ -e "$xpc" ] && sign "$xpc"
done
[ -e "$FW/Versions/B/Updater.app" ]  && sign "$FW/Versions/B/Updater.app"
[ -e "$FW/Versions/B/Autoupdate" ]   && sign "$FW/Versions/B/Autoupdate"
sign "$FW"

if [ "$IDENTITY" = "-" ]; then
  sign "$APP"
  echo "Built $APP (ad-hoc signed, Sparkle bundled)"
else
  sign "$APP"
  codesign --verify --strict --verbose=1 "$APP"
  echo "Built $APP (signed: $IDENTITY, Sparkle bundled)"
fi

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ClipStack 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/ClipStack.app
  cp -R "$APP" /Applications/
  open /Applications/ClipStack.app
  echo "Installed and launched /Applications/ClipStack.app"
fi
