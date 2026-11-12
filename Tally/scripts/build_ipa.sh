#!/usr/bin/env bash
# Archive Tally and export a signed .ipa on a Mac with Xcode 16+.
#
#   ./scripts/build_ipa.sh <TEAM_ID> [development|release-testing|app-store-connect] [bundle-id]
#
# Examples
#   ./scripts/build_ipa.sh ABCDE12345                       # development IPA for registered devices
#   ./scripts/build_ipa.sh ABCDE12345 release-testing       # Ad Hoc IPA
#   ./scripts/build_ipa.sh ABCDE12345 development com.you.tally
#
# Uses automatic signing: Xcode must be signed in to the Apple ID of that team
# (Xcode > Settings > Accounts). Output: build/export/Tally.ipa
set -euo pipefail

TEAM_ID="${1:?Usage: build_ipa.sh <TEAM_ID> [method] [bundle-id]}"
METHOD="${2:-development}"
BUNDLE_ID="${3:-com.ganhoo.tally}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/Tally.xcarchive"
EXPORT="$BUILD/export"
OPTIONS="$BUILD/ExportOptions.plist"

rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p "$BUILD"

echo "▸ Archiving (Release) for team $TEAM_ID, bundle id $BUNDLE_ID"
xcodebuild archive \
  -project "$ROOT/Tally.xcodeproj" \
  -scheme Tally \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic

sed -e "s/YOUR_TEAM_ID/$TEAM_ID/" "$ROOT/ExportOptions/$METHOD.plist" > "$OPTIONS"

echo "▸ Exporting ($METHOD)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates

echo "✓ $(ls "$EXPORT"/*.ipa)"
