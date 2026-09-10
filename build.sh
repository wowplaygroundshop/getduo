#!/bin/bash
# Builds DuoBook.app. Set SIGN_ID to a Developer ID to ship; defaults to ad-hoc for local use.
set -euo pipefail
cd "$(dirname "$0")"

# Sign with your Developer ID when one is in the keychain. TCC (Screen Recording)
# keys off the signature, so an ad-hoc build has to be re-approved on every rebuild.
if [[ -z "${SIGN_ID:-}" ]]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
  SIGN_ID="${SIGN_ID:--}"
fi
APP="build/DuoBook.app"
ARCHS=(--arch arm64)
[[ "${UNIVERSAL:-0}" == "1" ]] && ARCHS=(--arch arm64 --arch x86_64)

mkdir -p build
swift build -c release "${ARCHS[@]}"
BIN=$(swift build -c release "${ARCHS[@]}" --show-bin-path)

xcrun -sdk macosx metal -O -c Sources/DuoBook/Shader.metal -o build/Shader.air
xcrun -sdk macosx metallib build/Shader.air -o build/default.metallib

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DuoBook" "$APP/Contents/MacOS/DuoBook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp build/default.metallib "$APP/Contents/Resources/default.metallib"

codesign --force --deep --options runtime --timestamp \
         --sign "$SIGN_ID" "$APP" >/dev/null
echo "built $APP  (signed: $SIGN_ID)"
