#!/bin/zsh
#
# upload.sh — upload the newest WatchGuide archive to App Store Connect.
#
# Run scripts/archive.sh first. Authenticates with the App Store Connect API key
# in fastlane/.env, so no Xcode sign-in is needed.
#
# Usage: scripts/upload.sh [path/to/archive.xcarchive]

set -eu
ROOT="${0:A:h}/.."
set -a; source "$ROOT/fastlane/.env"; set +a

ARCHIVE="${1:-$(ls -td ~/Library/Developer/Xcode/Archives/*/WatchGuide*.xcarchive | head -1)}"
EXPORT_DIR=$(mktemp -d -t watchguide-export)

echo "Uploading ${ARCHIVE:t}"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$ROOT/scripts/ExportOptions-AppStore.plist" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "${~ASC_KEY_PATH}" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
rm -rf "$EXPORT_DIR"
echo "✅ Uploaded. App Store Connect processes the build for 10–30 minutes before it appears in TestFlight."
