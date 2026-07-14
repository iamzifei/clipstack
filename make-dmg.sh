#!/bin/bash
# Package ClipStack.app into a distributable drag-to-Applications DMG.
#   ./make-dmg.sh   → dist/ClipStack-<version>.dmg
#
# Signing: set CODESIGN_IDENTITY to sign the DMG itself (the app inside
# should already be built with the same identity via build.sh).
# Notarization: set NOTARY_PROFILE (a `notarytool store-credentials` profile)
# to submit + staple after signing.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY="${NOTARY_PROFILE:-}"

[ -d build/ClipStack.app ] || ./build.sh
VERSION=$(defaults read "$PWD/build/ClipStack.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")

STAGE=$(mktemp -d)
RW_DMG=$(mktemp -u).dmg
trap 'rm -rf "$STAGE" "$RW_DMG"' EXIT

cp -R build/ClipStack.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# Build read-write first so the volume's custom-icon flag can be set,
# then compress to the final read-only UDZO image.
hdiutil create -volname "ClipStack" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null
MOUNT_DIR=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen | grep -o "/Volumes/.*" | head -1)
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNT_DIR" || true   # show .VolumeIcon.icns as the volume icon
fi
hdiutil detach "$MOUNT_DIR" >/dev/null

mkdir -p dist
DMG="dist/ClipStack-$VERSION.dmg"
rm -f "$DMG"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG" >/dev/null

if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  codesign --verify --verbose=1 "$DMG"
  echo "Signed DMG with: $IDENTITY"
fi

if [ -n "$NOTARY" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY" --wait
  xcrun stapler staple "$DMG"
  echo "Notarized and stapled."
fi

echo "Created $DMG"
if [ -z "$IDENTITY" ]; then
  echo "Note: unsigned DMG with ad-hoc-signed app — fine for personal use."
  echo "For public distribution set CODESIGN_IDENTITY (+ NOTARY_PROFILE to notarize)."
elif [ -z "$NOTARY" ]; then
  echo "Note: signed but NOT notarized — downloaders must right-click → Open on first launch."
fi
