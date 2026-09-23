#!/bin/bash
# Builds SimParcel, signs it with Developer ID, notarizes it and packages a zip and a DMG.
#
# Needs a "Developer ID Application" certificate for the team in ExportOptions.plist and
# notarization credentials saved in the keychain once:
#
#   xcrun notarytool store-credentials "SimParcel" --apple-id "<Apple ID>" --team-id "D83JQSBRML"
#
# Usage: scripts/release.sh            (uses the "SimParcel" keychain profile)
#        NOTARY_PROFILE=Other scripts/release.sh

set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-SimParcel}"
BUILD="build/release"
APP_NAME="SimParcel"

step() {
    printf '\n\033[1m▸ %s\033[0m\n' "$1"
}

VERSION=$(xcodebuild -project SimParcel.xcodeproj -scheme SimParcel -configuration Release -showBuildSettings 2>/dev/null \
    | awk '$1 == "MARKETING_VERSION" { print $3; exit }')

if [[ $(security find-identity -v -p codesigning) != *"Developer ID Application"* ]]; then
    echo "No \"Developer ID Application\" certificate found. Create one in Xcode → Settings → Accounts → Manage Certificates." >&2
    exit 1
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"

step "Archiving $APP_NAME $VERSION"
xcodebuild archive \
    -project SimParcel.xcodeproj \
    -scheme SimParcel \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$BUILD/$APP_NAME.xcarchive" \
    -quiet

step "Exporting with Developer ID"
xcodebuild -exportArchive \
    -archivePath "$BUILD/$APP_NAME.xcarchive" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$BUILD/export" \
    -quiet

APP="$BUILD/export/$APP_NAME.app"
codesign --verify --strict --deep "$APP"
# Read the signature into a variable: piping into `grep -q` would fail under pipefail when grep exits early.
SIGNATURE=$(codesign -dv --verbose=2 "$APP" 2>&1)
IDENTITY=$(awk -F= '/^Authority=Developer ID Application/ { print $2; exit }' <<< "$SIGNATURE")
if [[ -z "$IDENTITY" ]]; then
    echo "The exported app isn't signed with Developer ID." >&2
    exit 1
fi

step "Notarizing the app"
ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
xcrun notarytool submit "$BUILD/notarize.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$BUILD/notarize.zip"

step "Packaging"
ZIP="$BUILD/$APP_NAME-$VERSION.zip"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGING="$BUILD/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

codesign --sign "$IDENTITY" --timestamp "$DMG"

step "Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

step "Checking Gatekeeper"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose "$APP"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

step "Done"
shasum -a 256 "$ZIP" "$DMG"
