#!/bin/zsh
#
# release-5.6.2.sh — archive and upload WatchGuide 5.6.2 for iOS (build 13) and Apple TV
# (build 12). The listings, screenshots and previews are already on App Store Connect.
# Nothing is submitted here; once both builds finish processing, run:
#   fastlane submit version:5.6.2 build:13
#   fastlane submit version:5.6.2 build:12 platform:appletvos
# Full output: archive_build/release-5.6.2.log

set -u
ROOT="${0:A:h}/.."; cd "$ROOT"
LOG="$ROOT/archive_build/release-5.6.2.log"; mkdir -p "${LOG:h}"; : > "$LOG"
START=$(date +%s)
step() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
fail() { step "❌ $*  (see $LOG)"; exit 1; }

# 1 ─ iOS archive + upload
step "1/4 Archiving iOS 5.6.2 (13)"
scripts/archive.sh >> "$LOG" 2>&1 || fail "iOS archive failed"
IOS_ARCHIVE=$(ls -td ~/Library/Developer/Xcode/Archives/*/"WatchGuide 5.6.2 (13)"*.xcarchive | head -1)
step "2/4 Uploading ${IOS_ARCHIVE:t}"
scripts/upload.sh "$IOS_ARCHIVE" >> "$LOG" 2>&1 || fail "iOS upload failed"

# 2 ─ Apple TV archive + upload
step "3/4 Archiving Apple TV 5.6.2 (12)"
TV_ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/WatchGuide tvOS 5.6.2 (12).xcarchive"
xcodebuild archive -project WatchGuide-MovieandTVtracker.xcodeproj -scheme WatchGuide-MovieandTVtracker \
  -configuration Release -destination 'generic/platform=tvOS' -archivePath "$TV_ARCHIVE" \
  -derivedDataPath archive_build/DerivedData-tvOS -allowProvisioningUpdates >> "$LOG" 2>&1
grep -q '\*\* ARCHIVE SUCCEEDED \*\*' "$LOG" && [[ -d "$TV_ARCHIVE" ]] || fail "Apple TV archive failed"
step "4/4 Uploading ${TV_ARCHIVE:t}"
scripts/upload.sh "$TV_ARCHIVE" >> "$LOG" 2>&1 || fail "Apple TV upload failed"

step "✅ Both builds uploaded in $(( ($(date +%s) - START) / 60 )) min. Apple processes them for 10–30 min before they can be submitted."
