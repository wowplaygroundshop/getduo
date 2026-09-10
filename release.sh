#!/bin/bash
# Signs, notarizes and staples a distributable DMG.
# One-time setup:
#   xcrun notarytool store-credentials fold-notary \
#     --apple-id you@example.com --team-id <YOUR_TEAM_ID> --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-fold-notary}"
DMG="build/DuoBook.dmg"

UNIVERSAL=1 ./build.sh

rm -f "$DMG"
rm -rf build/dmg && mkdir -p build/dmg
cp -R build/DuoBook.app build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname DuoBook -srcfolder build/dmg -ov -format ULFO "$DMG" >/dev/null

codesign --force --sign "$(security find-identity -v -p codesigning \
    | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/')" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "shipped $DMG"
