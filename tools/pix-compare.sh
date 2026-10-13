#!/bin/sh
# Build the Pix port on the Mac, render the 104 reference frames and compare them with design/pix/reference.
# Output: app/build/pix-compare (summary.txt, index.html, sheets/*.png). Extra arguments go to pix-render (e.g. --time).
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
OUT=app/build/pix-compare
mkdir -p "$OUT/frames"
xcrun swiftc -O -target "$(uname -m)-apple-macosx14.0" app/ChumsWatch/Rig/Pix.swift tools/pix-render.swift -o "$OUT/pix-render"
"$OUT/pix-render" "$OUT/frames" "$@"
python3 tools/pix-compare.py "$OUT/frames" "$OUT"
