#!/bin/bash
# Build Perch.app (+ zip and dmg) into build/ at the repo root (bundles packs/kuro).
#
# Usage: scripts/build-app.sh [--sign] [--notarize] [--arch <arch>]... [--version X.Y.Z]
#   default arches: arm64 x86_64 (universal; falls back to native if that fails)
#   --sign      Developer ID + hardened runtime
#   --notarize  submit the dmg to Apple (implies --sign), staple it
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/app"
BUILD="$ROOT/build"
NAME="Perch"
VERSION="0.1.0"
SIGN=0; NOTARIZE=0; ARCHES=()
SIGN_IDENTITY="${PERCH_SIGN_IDENTITY:-Developer ID Application: Varie.AI LLC (DT49XDQPKV)}"   # override for your own Developer ID
NOTARY_PROFILE="${PERCH_NOTARY_PROFILE:-notary}"   # xcrun notarytool store-credentials profile

while [ $# -gt 0 ]; do
  case "$1" in
    --sign) SIGN=1 ;;
    --notarize) SIGN=1; NOTARIZE=1 ;;
    --arch) ARCHES+=("$2"); shift ;;
    --version) VERSION="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
[ ${#ARCHES[@]} -eq 0 ] && ARCHES=(arm64 x86_64)

cd "$APP_SRC"
build() {
  local args=(-c release)
  for a in "$@"; do args+=(--arch "$a"); done
  swift build "${args[@]}"
}
echo "Building (${ARCHES[*]})..."
if ! build "${ARCHES[@]}"; then
  echo "WARNING: universal build failed; falling back to native arch" >&2
  ARCHES=("$(uname -m)")
  build "${ARCHES[@]}"
fi
BIN_DIR="$(swift build -c release $(for a in "${ARCHES[@]}"; do printf -- '--arch %s ' "$a"; done) --show-bin-path)"
BIN="$BIN_DIR/Perch"
[ -f "$BIN" ] || { echo "binary not found: $BIN" >&2; exit 1; }

APP="$BUILD/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/packs"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp -R "$ROOT/packs/kuro" "$APP/Contents/Resources/packs/kuro"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.perch-avatar.app</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Perch reads text in the window your agent works in so it can point at it. Nothing leaves your Mac.</string>
</dict>
</plist>
PLIST

if [ $SIGN -eq 1 ]; then
  security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" \
    || { echo "Developer ID identity not in keychain: $SIGN_IDENTITY" >&2; exit 1; }
  echo "Signing with Developer ID + hardened runtime..."
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
  echo "  $(codesign -dvv "$APP" 2>&1 | grep 'Authority=' | head -1)"
else
  codesign --force --sign - "$APP" 2>/dev/null || true
fi

# zip (ditto keeps the signature intact)
ZIP="$BUILD/$NAME-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# dmg (plain, no Finder styling)
DMG="$BUILD/$NAME-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet || \
  echo "WARNING: dmg creation failed" >&2
rm -rf "$STAGE"
[ $SIGN -eq 1 ] && [ -f "$DMG" ] && codesign --force --sign "$SIGN_IDENTITY" "$DMG"

if [ $NOTARIZE -eq 1 ]; then
  echo "Submitting for notarization..."
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "Stapling notarization ticket..."
  xcrun stapler staple "$DMG"
fi

echo ""
echo "Build complete: $APP ($(lipo -archs "$APP/Contents/MacOS/$NAME"))"
echo "  Size: $(du -sh "$APP" | cut -f1)"
ls -lh "$ZIP" "$DMG" 2>/dev/null | awk '{print "  " $5 " " $9}'
