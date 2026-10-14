#!/bin/bash
#
# archive.sh — archive WatchGuide for App Store Connect with a progress bar.
#
# xcodebuild doesn't report progress, so this counts the build steps it prints
# and compares them against the step count of the last successful archive
# (saved after each run). The first run uses an estimate; later runs are close.
#
# Usage: scripts/archive.sh

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/WatchGuide-MovieandTVtracker.xcodeproj"
SCHEME="WatchGuide-MovieandTVtracker"
INFO_PLIST="$ROOT/WatchGuide-MovieandTVtracker/Info.plist"
# Build intermediates go next to the project (on the roomy Dev volume, and
# git-ignored by *_build/) instead of the nearly full system disk.
DERIVED_DATA="$ROOT/archive_build/DerivedData"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")

ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/WatchGuide $VERSION ($BUILD) $(date +%H.%M).xcarchive"
LOG_DIR="$HOME/Library/Logs/WatchGuide"
LOG="$LOG_DIR/archive-$(date +%Y%m%d-%H%M%S).log"
STEPS_FILE="$HOME/Library/Caches/WatchGuide/archive-steps"
COUNT_FILE=$(mktemp -t watchguide-archive-count)

mkdir -p "$LOG_DIR" "$(dirname "$STEPS_FILE")"

TOTAL=1000
ESTIMATED=" (estimated)"
if [ -s "$STEPS_FILE" ]; then
    TOTAL=$(cat "$STEPS_FILE")
    ESTIMATED=""
fi

BAR_WIDTH=30
START=$(date +%s)

draw() {
    local done=$1 step=$2
    local pct=$(( done * 100 / TOTAL ))
    [ "$pct" -gt 99 ] && pct=99   # 100% only once the archive has succeeded
    local filled=$(( pct * BAR_WIDTH / 100 ))
    local bar empty elapsed
    bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    empty=$(printf '%*s' $(( BAR_WIDTH - filled )) '' | tr ' ' '-')
    elapsed=$(( $(date +%s) - START ))
    printf '\r\033[K[%s%s] %3d%%  %02d:%02d  %.40s' "$bar" "$empty" "$pct" $(( elapsed / 60 )) $(( elapsed % 60 )) "$step"
}

echo "Archiving WatchGuide $VERSION ($BUILD)$ESTIMATED"
echo "Full log: $LOG"
echo

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates 2>&1 \
| tee "$LOG" \
| {
    count=0
    draw 0 "Starting…"
    while IFS= read -r line; do
        # Build steps start at column 0 with a CamelCase task name, e.g.
        # "SwiftCompile normal arm64 …" or "CodeSign /path/…".
        case "$line" in
            [A-Z]*' '*)
                task=${line%% *}
                case "$task" in
                    *[!A-Za-z]*) continue ;;
                esac
                count=$(( count + 1 ))
                target=""
                case "$line" in
                    *"(in target '"*)
                        target=${line##*"(in target '"}
                        target=${target%%"'"*}
                        ;;
                esac
                draw "$count" "$task $target"
                ;;
        esac
    done
    echo "$count" > "$COUNT_FILE"
}
STATUS=${PIPESTATUS[0]}
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
rm -f "$COUNT_FILE"
ELAPSED=$(( $(date +%s) - START ))

if [ "$STATUS" -eq 0 ] && grep -q '\*\* ARCHIVE SUCCEEDED \*\*' "$LOG"; then
    printf '\r\033[K[%s] 100%%  %02d:%02d  Done\n\n' "$(printf '%*s' "$BAR_WIDTH" '' | tr ' ' '#')" $(( ELAPSED / 60 )) $(( ELAPSED % 60 ))
    echo "$COUNT" > "$STEPS_FILE"
    echo "✅ Archived WatchGuide $VERSION ($BUILD)"
    echo "   $ARCHIVE"
    echo
    echo "To upload: open it in Xcode Organizer, then Distribute App → App Store Connect:"
    echo "   open \"$ARCHIVE\""
else
    printf '\n\n❌ Archive failed after %02d:%02d\n\n' $(( ELAPSED / 60 )) $(( ELAPSED % 60 ))
    grep -E ' error: |^error: ' "$LOG" | grep -v appintentsnltrainingprocessor | sort -u | head -20
    echo
    echo "Full log: $LOG"
    exit 1
fi
