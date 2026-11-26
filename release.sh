#!/bin/zsh
# Builds a ZyDisk release for GitHub: universal app, Developer ID signed (hardened runtime, secure timestamp),
# notarized and stapled, plus a zip and its SHA-256 in ./dist.
#   ./release.sh              build with Flutter, then sign, notarize and zip
#   ./release.sh --no-build   reuse the last `flutter build macos --release` output
# Credentials: xcrun notarytool store-credentials <profile> (once per Mac). NOTARY_PROFILE picks the profile,
# SIGN_ID the signing identity.
set -euo pipefail
cd "$(dirname "$0")"

SIGN_ID="${SIGN_ID:-Developer ID Application: CONAK SOFT LLC (LMY9XNPRWD)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-zymanager-notary}"
[[ "${1:-}" == "--no-build" ]] || flutter build macos --release

SRC="build/macos/Build/Products/Release/ZyDisk.app"
APP="dist/ZyDisk.app"
rm -rf dist && mkdir -p dist
ditto "$SRC" "$APP"

sign() { codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$@"; }

# Inside out: nested libraries and frameworks first, then the privileged helper, then the app itself.
find "$APP/Contents/Frameworks" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' f; do sign "$f"; done
find "$APP/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0 | while IFS= read -r -d '' f; do sign "$f"; done
# The helper keeps its own identifier; it only accepts connections from an app signed by the same team.
sign --identifier com.conaksoft.zydisk.daemon "$APP/Contents/MacOS/ZyDiskDaemon"
sign --entitlements macos/Runner/Release.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="dist/ZyDisk-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 "${ZIP:t}" > "${ZIP:t}.sha256")
echo "Zip: $PWD/$ZIP ($(lipo -archs "$APP/Contents/MacOS/ZyDisk"))"
cat "$ZIP.sha256"
