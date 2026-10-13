#!/bin/zsh
# Renders each character's loop for the README from the current code: 3.2 s of it idle on the watch's screen (the
# faces and the clock at the top), at 20 frames a second, in the watch's case (docs/media/watch-case.png), as an
# animated WebP 300 px wide in docs/media/characters/<id>.webp (GitHub plays it; its corners are transparent).
#
#   usage: tools/readme-loops.sh [id ...]      (default: every character)
#
# Run bin/chums-sim once first: it builds the watch app for the Simulator and makes the "Chums Watch" simulator. The
# frames come from the app's offline renderer (app/ChumsWatch/OfflineRender.swift), not a screen recording, so they
# are the same on every Mac. Needs ffmpeg and img2webp (brew install webp).
set -euo pipefail
ROOT="${0:A:h:h}"
source "$ROOT/tools/common.zsh"
chums_help "$@"
: ${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}; export DEVELOPER_DIR
chums_need ffmpeg "Install it with: brew install ffmpeg"
chums_need img2webp "Install it with: brew install webp"
APP="$ROOT/app/build/sym/Debug-watchsimulator/ChumsWatch.app"
[[ -d $APP ]] || chums_die "no watch app built for the Simulator yet: run bin/chums-sim once"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
UDID=$(xcrun simctl list devices -j | python3 -c '
import json, sys
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"] == "Chums Watch" and d["isAvailable"]: print(d["udid"]); raise SystemExit')
[[ -n $UDID ]] || chums_die "no \"Chums Watch\" simulator: run bin/chums-sim once"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

ALL=(noodle stretch peeps squint ray tangle crunch nana)
IDS=("$@"); (( ${#IDS} )) || IDS=($ALL)
OUT="$ROOT/docs/media/characters"; mkdir -p "$OUT"
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
for id in $IDS; do
  # the faces at the top left: this one, then the next two
  i=${ALL[(i)$id]}; f2=${ALL[$(( i % ${#ALL} + 1 ))]}; f3=${ALL[$(( (i + 1) % ${#ALL} + 1 ))]}
  spec=$(printf '{"name":"loop-%s","character":"%s","duration":3.2,"fps":20,"scale":3,"clock":"10:09","faces":["%s","%s","%s"],"events":[{"t":0,"state":"idle"}]}' \
    $id $id $id $f2 $f3 | base64)
  # one run at a time: the last one has quit, and this one has printed "done" (once more if it didn't)
  for try in 1 2; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    out=$(xcrun simctl launch --console "$UDID" "$BUNDLE" -render "$spec" -quiet YES 2>&1 || true)
    [[ $out == *"render: loop-$id done"* ]] && break
    (( try == 2 )) && chums_die "the Simulator didn't render $id"
  done
  # the screen under the case: the case's band hides the screen's square corners
  TMP=$(mktemp -d)
  ffmpeg -v error -y -framerate 20 -pattern_type glob -i "$DATA/Documents/render/loop-$id/*.png" -i "$ROOT/docs/media/watch-case.png" \
    -filter_complex "[0]scale=581:710:flags=lanczos,format=rgba,pad=815:907:100:99:color=black@0[s];[s][1]overlay=0:0,scale=300:-1:flags=lanczos" \
    "$TMP/%04d.png"
  img2webp -loop 0 -lossy -q 75 -m 6 -d 50 "$TMP"/*.png -o "$OUT/$id.webp" >/dev/null 2>&1
  rm -rf "$TMP"
  echo "$id: $(du -h "$OUT/$id.webp" | cut -f1)"
done
xcrun simctl shutdown "$UDID" 2>/dev/null || true      # left running without a window, it plays the watch's taps as sounds
