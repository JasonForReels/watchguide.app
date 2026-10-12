#!/bin/zsh
#
# finish-5.6.1-resume.sh — steps 5-9 of finish-5.6.1.sh, for when the TV screens are already captured.
# Original: the Apple TV half of the 5.6.1 release, with a progress bar:
# rebuild + capture TV screens, build the TV screenshots (en/es/zh), upload the tvOS listing
# and screenshots, archive + upload the tvOS build, re-upload the fixed iOS build, then report App Store Connect status.
# Nothing is submitted for review. Full output: archive_build/finish-5.6.1.log
#
# Usage: scripts/finish-5.6.1.sh

set -u
ROOT="${0:A:h}/.."
cd "$ROOT"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
LOG="$ROOT/archive_build/finish-5.6.1.log"; : > "$LOG"
SIM=225F4D00-CF14-4C7F-A6C2-B153E332BEE4
BUNDLE=com.JasonSmith.WatchGuide-MovieandTVtracker
CAPS="$ROOT/AppStoreScreenshots/tvOS-raw"
TOTAL=9; STEP=0; START=$(date +%s)

bar() {   # bar <sub-status>
  local pct=$(( (STEP - 1) * 100 / TOTAL )) filled el
  filled=$(( pct * 30 / 100 ))
  el=$(( $(date +%s) - START ))
  printf '\r\033[K[%s%s] %3d%%  %02d:%02d  Step %d/%d  %s' \
    "$(printf '%*s' $filled '' | tr ' ' '#')" "$(printf '%*s' $(( 30 - filled )) '' | tr ' ' '-')" \
    $pct $(( el / 60 )) $(( el % 60 )) $STEP $TOTAL "$1"
}
step() { STEP=$1; NAME=$2; bar "$NAME"; }
done_step() { printf '\r\033[K  ✓ %d/%d  %s%s\n' $STEP $TOTAL "$NAME" "${1:+  — $1}"; }
fail() { printf '\r\033[K  ✗ %d/%d  %s — %s\n     See %s\n' $STEP $TOTAL "$NAME" "$1" "$LOG"; exit 1; }

echo "WatchGuide 5.6.1 — resuming at step 5 (slides already rendered)"
echo "Log: $LOG"
echo

# 5 ─ App Store Connect: tvOS version 5.6.1, listing text, screenshots
step 5 "Uploading Apple TV listing + screenshots"
fastlane tv_media version:5.6.1 >> "$LOG" 2>&1 || fail "fastlane tv_media failed"
done_step "tvOS version is now 5.6.1"

# 6 ─ Archive the tvOS build
step 6 "Archiving Apple TV build"
TV_ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/WatchGuide tvOS 5.6.1 (11).xcarchive"
xcodebuild archive -project WatchGuide-MovieandTVtracker.xcodeproj -scheme WatchGuide-MovieandTVtracker \
  -configuration Release -destination 'generic/platform=tvOS' -archivePath "$TV_ARCHIVE" \
  -derivedDataPath archive_build/DerivedData-tvOS -allowProvisioningUpdates 2>&1 | tee -a "$LOG" | {
    c=0; while IFS= read -r line; do
      case "$line" in SwiftCompile*|CompileSwift*|Ld\ *|CodeSign*|CopySwiftLibs*|GenerateDSYMFile*) c=$((c + 1)); bar "Archiving Apple TV build (${line%% *}, $c tasks)";; esac
    done; }
grep -q '\*\* ARCHIVE SUCCEEDED \*\*' "$LOG" || fail "archive failed"
done_step "${TV_ARCHIVE:t}"

# 7 ─ Upload it
step 7 "Uploading Apple TV build"
scripts/upload.sh "$TV_ARCHIVE" >> "$LOG" 2>&1 || fail "upload failed"
done_step "Apple is processing it"

# 8 ─ Replace the iOS build: 5.6.1 (12) with the language fix
step 8 "Archiving + uploading fixed iOS build (12)"
scripts/archive.sh >> "$LOG" 2>&1 || fail "iOS archive failed"
IOS_ARCHIVE=$(ls -td ~/Library/Developer/Xcode/Archives/*/"WatchGuide 5.6.1 (12)"*.xcarchive | head -1)
bar "Archiving + uploading fixed iOS build (12) — uploading"
scripts/upload.sh "$IOS_ARCHIVE" >> "$LOG" 2>&1 || fail "iOS upload failed"
done_step "replaces build 11 (Spanish-for-everyone bug)"

# 9 ─ What App Store Connect has now
step 9 "Checking App Store Connect"
fastlane media_status version:5.6.1 >> "$LOG" 2>&1
grep -E "preview|screenshots" "$LOG" | grep -E "es-|en-|zh" | tail -12 | sed 's/^\[[0-9:]*\]: /     /'
STEP=$((TOTAL + 1)); bar "Done"; echo
done_step "nothing has been submitted for review"
echo
echo "Finished in $(( ($(date +%s) - START) / 60 )) min. Next: submit iOS + tvOS 5.6.1 for review."
