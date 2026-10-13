#!/bin/zsh
# Noodle for the watch: each clip's rendered frames (design/noodle/renders/anim, from animate.py) become one HEIC image
# sequence in app/ChumsWatch/Noodle/<clip>.heics (frames share data, so a 144-frame clip is ~120 KB), plus noodle.json
# with each clip's frame count, role, state, events and per-frame anchors (hair, face, glass contact).
# watchOS has no way to read frames out of a video (no AVAssetReader or video outputs), so the app decodes these with
# ImageIO a frame at a time (Rig/StretchFrames.swift).
set -e
ROOT="${0:A:h:h}"; R="$ROOT/design/noodle/renders"; OUT="$ROOT/app/ChumsWatch/Noodle"; mkdir -p "$OUT"
TOOL=$(mktemp -d)/heics
swiftc -O -o "$TOOL" "$ROOT/tools/heics.swift"
for c in $(python3 -c "import json;print(' '.join(json.load(open('$R/clips.json'))['clips']))"); do "$TOOL" "$R/anim" "$c" "$OUT/$c.heics" 0.65 >/dev/null; done
python3 - "$R/clips.json" "$OUT/noodle.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
keep = {k: {kk: v[kk] for kk in ('n', 'loop', 'role', 'state', 'events', 'frames', 'scrub') if kk in v} for k, v in m['clips'].items()}
json.dump({'fps': m.get('fps', 24), 'w': m.get('w', 396), 'h': m.get('h', 484), 'beat_chance': m.get('beat_chance', {}), 'clips': keep}, open(sys.argv[2], 'w'), separators=(',', ':'))
PY
du -sh "$OUT"
