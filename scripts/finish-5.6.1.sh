#!/bin/zsh
#
# finish-5.6.1.sh — the Apple TV half of the 5.6.1 release, with a progress bar:
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

echo "WatchGuide 5.6.1 — Apple TV release"
echo "Log: $LOG"
echo

# 1 ─ TV listing text: same as iPhone, minus the iPhone-only lines; app name/subtitle left alone
step 1 "Preparing Apple TV listing text"
rm -rf fastlane/metadata-tvos; cp -R fastlane/metadata fastlane/metadata-tvos
for d in fastlane/metadata-tvos/*/; do
  rm -f "$d/name.txt" "$d/subtitle.txt" "$d/privacy_url.txt"
  python3 - "$d/description.txt" <<'EOF' >> "$LOG" 2>&1
import sys, re
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = re.sub(r"\n(UP NEXT WIDGET|WIDGET A CONTINUACIÓN)\n[^\n]*\n", "\n", s)
s = s.replace("Ad-free, on iPhone and iPad.", "Ad-free, on Apple TV, iPhone and iPad.")
s = s.replace("Sin anuncios, en iPhone y iPad.", "Sin anuncios, en Apple TV, iPhone y iPad.")
open(p, "w", encoding="utf-8").write(s)
EOF
done
done_step "$(ls -d fastlane/metadata-tvos/*/ | wc -l | tr -d ' ') languages"

# 2 ─ Rebuild the TV app (with English/Spanish language fix) for the simulator
step 2 "Building Apple TV app for screenshots"
[[ -n ${SKIP_TV_BUILD:-} ]] || xcodebuild build -project WatchGuide-MovieandTVtracker.xcodeproj -scheme WatchGuide-MovieandTVtracker -configuration Debug \
  -destination "platform=tvOS Simulator,id=$SIM" -derivedDataPath tv_build/DerivedData CODE_SIGNING_ALLOWED=NO 2>&1 | tee -a "$LOG" | {
    c=0; while IFS= read -r line; do
      case "$line" in SwiftCompile*|CompileSwift*|Ld\ *|CopySwiftLibs*) c=$((c + 1)); bar "Building Apple TV app for screenshots ($c tasks)";; esac
    done; }
[[ -n ${SKIP_TV_BUILD:-} ]] || tail -5 "$LOG" | grep -q 'BUILD SUCCEEDED' || fail "tvOS build failed"
done_step

# 3 ─ Capture the TV app's screens in English and Spanish
step 3 "Capturing Apple TV screens"
mkdir -p "$CAPS"; rm -f "$CAPS"/*.png(N)
xcrun simctl boot $SIM >> "$LOG" 2>&1
APP=$(find tv_build/DerivedData/Build/Products/Debug-appletvsimulator -maxdepth 1 -name "*.app" | head -1)
xcrun simctl install $SIM "$APP" >> "$LOG" 2>&1 || fail "install failed"
# Waits until the screen has drawn something and stopped changing, then saves it.
settle() {
  python3 - "$SIM" "$1" <<'EOF' >> "$LOG" 2>&1
import subprocess, sys, time
from PIL import Image, ImageStat, ImageChops
sim, out = sys.argv[1:]
home = Image.open("archive_build/tv-home-reference.png").convert("L").resize((96, 54))
def away_from_home(im):   # the Apple TV home screen also looks "drawn"; insist on the app
    return sum(ImageStat.Stat(ImageChops.difference(im, home)).mean) > 25
t0 = time.time()
while time.time() - t0 < 150:
    subprocess.run(["xcrun", "simctl", "io", sim, "screenshot", "/tmp/wg_tv.png"], capture_output=True)
    try: im = Image.open("/tmp/wg_tv.png").convert("L").resize((96, 54))
    except Exception: time.sleep(2); continue
    if sum(ImageStat.Stat(im).stddev) > 18 and away_from_home(im):           # the page has drawn, not just the launch gradient
        time.sleep(6)                                  # let posters and artwork finish loading
        subprocess.run(["xcrun", "simctl", "io", sim, "screenshot", "/tmp/wg_tv.png"], capture_output=True)
        Image.open("/tmp/wg_tv.png").convert("RGB").resize((1920, 1080), Image.LANCZOS).save(out); print("ok", out); sys.exit(0)
    time.sleep(2)
Image.open("/tmp/wg_tv.png").convert("RGB").resize((1920, 1080), Image.LANCZOS).save(out); print("timeout", out)
EOF
}
n=0
for L in en es; do
  for spec in browse:0 tonight:10 search:1 streamq:8 lists:3; do
    name=${spec%%:*}; tab=${spec##*:}; n=$((n + 1))
    bar "Capturing Apple TV screens ($n/10: $L $name)"
    xcrun simctl terminate $SIM $BUNDLE >> "$LOG" 2>&1
    xcrun simctl launch $SIM $BUNDLE -WGTab $tab -AppleLanguages "($L)" -AppleLocale "${L}_US" >> "$LOG" 2>&1
    settle "$CAPS/${L}_$name.png"
  done
done
done_step "10 screens"

# 4 ─ Build the screenshots
step 4 "Rendering Apple TV screenshots"
for L in en es zh; do
  bar "Rendering Apple TV screenshots ($L)"
  case $L in en) DIRS=(en-GB en-US) ;; es) DIRS=(es-ES es-MX) ;; zh) DIRS=(zh-Hans) ;; esac
  OUT="AppStoreScreenshots/tvOS/${DIRS[1]}"; mkdir -p "$OUT"
  WG_LANG=$L node AppStoreScreenshots/source/render.mjs tv "$OUT" "$CAPS" >> "$LOG" 2>&1 || fail "render $L failed"
  for extra in ${DIRS[@]:1}; do rm -rf "AppStoreScreenshots/tvOS/$extra"; cp -R "$OUT" "AppStoreScreenshots/tvOS/$extra"; done
done
done_step "5 slides × 5 languages, 1920×1080"

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
