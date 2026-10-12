#!/bin/zsh
# Builds WatchGuide, installs it on the iPhone and launches it, with a live
# progress bar.
#
# Progress is measured, not estimated: Xcode writes the exact list of Swift
# files every target compiles (*.SwiftFileList), and a file counts as done once
# its object file is newer than its source. Up-to-date files from earlier
# builds count as done, so incremental builds are accurate too.
#
# If a build into the same DerivedData folder is already running, the script
# follows that one instead of starting another.
#
# Usage: scripts/iphone-build.sh [device-id]

set -u
cd "${0:A:h}/.."

DEVICE="${1:-00008140-000478592EE8801C}"
SCHEME="WatchGuide-MovieandTVtracker"
BUNDLE_ID="com.JasonSmith.WatchGuide-MovieandTVtracker"
DD="$HOME/Library/Developer/Xcode/DerivedData/WatchGuide-CLI"
LOG="$DD/iphone-build.log"
APP="$DD/Build/Products/Debug-iphoneos/$SCHEME.app"
INTER="$DD/Build/Intermediates.noindex"

# Last measured file counts per target, used only until Xcode has written that
# target's own list, so the total never jumps upward mid-build.
typeset -A FALLBACK=(
  RevenueCat 570
  RevenueCatUI 341
  YouTubePlayerKit 48
  WatchGuide-MovieandTVtracker 199
  WatchGuide-MovieandTVtrackerWidgetExtension 4
)

COMPILE_SHARE=92   # compiling is 0–92%; linking, assets and signing the rest
WIDTH=40

bar() {  # bar <percent> <label>
  local pct=$1 label=$2
  local filled=$(( pct * WIDTH / 100 )) fill="" rest=""
  repeat $filled fill+="#"
  repeat $(( WIDTH - filled )) rest+="-"
  printf '\r\033[K[%s%s] %3d%%  %s' "$fill" "$rest" "$pct" "$label"
}

compile_progress() {  # prints "<done> <total>"
  local ndone=0 total=0 list target dir src obj
  typeset -A seen
  for list in "$INTER"/**/Objects-normal/arm64/*.SwiftFileList(N); do
    target="${list:t:r}"
    dir="${list:h}"
    seen[$target]=1
    while IFS= read -r src; do
      [[ -z "$src" ]] && continue
      (( total++ ))
      obj="$dir/${src:t:r}.o"
      [[ -f "$obj" && ! "$src" -nt "$obj" ]] && (( ndone++ ))
    done < "$list"
  done
  for target in ${(k)FALLBACK}; do
    [[ -z "${seen[$target]:-}" ]] && (( total += FALLBACK[$target] ))
  done
  echo "$ndone $total"
}

running_build_pid() {
  pgrep -f "xcodebuild .*-derivedDataPath $DD" | head -1
}

# ── Step 1/3: Build ───────────────────────────────────────────────────────────
mkdir -p "$DD"
echo "Step 1/3  Building $SCHEME"

PID=$(running_build_pid)
if [[ -n "$PID" ]]; then
  echo "          (following the build that's already running, pid $PID)"
  OWN_BUILD=0
else
  : > "$LOG"
  xcodebuild -scheme "$SCHEME" -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$DD" \
    -allowProvisioningUpdates build > "$LOG" 2>&1 &
  PID=$!
  OWN_BUILD=1
fi

while kill -0 "$PID" 2>/dev/null; do
  read ndone total <<< "$(compile_progress)"
  pct=$(( total > 0 ? ndone * COMPILE_SHARE / total : 0 ))
  label="Compiling $ndone/$total files"
  if (( total > 0 && ndone >= total )); then
    # Every file compiled: what's left is linking, assets and signing.
    if [[ -s "$LOG" ]] && tail -40 "$LOG" | grep -q '^CodeSign '; then
      pct=98; label="Signing"
    else
      pct=95; label="Linking"
    fi
  fi
  bar $pct "$label"
  sleep 1
done

if (( OWN_BUILD )); then
  wait "$PID"; status=$?
  if (( status != 0 )) || ! grep -q '\*\* BUILD SUCCEEDED \*\*' "$LOG"; then
    bar 0 "Build failed"; echo
    grep -E ' error:' "$LOG" | sort -u | head -20
    echo "Full log: $LOG"
    exit 1
  fi
elif [[ ! -d "$APP" ]]; then
  echo; echo "The build that was running didn't produce the app. Run this script again."
  exit 1
fi
bar 100 "Built"; echo

# ── Step 2/3: Install ─────────────────────────────────────────────────────────
echo "Step 2/3  Installing on iPhone (keep it unlocked)"
xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 |
  while IFS= read -r line; do
    if [[ "$line" =~ '([0-9]+)%' ]]; then
      bar ${match[1]} "Installing"
    elif [[ "$line" == *rror* ]]; then
      echo; echo "$line"
    fi
  done
(( ${pipestatus[1]} == 0 )) || { echo; echo "Install failed."; exit 1; }
bar 100 "Installed"; echo

# ── Step 3/3: Launch ──────────────────────────────────────────────────────────
echo "Step 3/3  Launching"
if xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" > /dev/null 2>&1; then
  bar 100 "Launched"; echo
else
  echo "Couldn't launch automatically; open WatchGuide on the phone."
fi
