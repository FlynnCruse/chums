#!/bin/zsh
# Rebuilds watch-noband.png from the band-less edit of the watch photo (on white, 828x1348).
#   design/mockup/noband.sh ["$HOME/Downloads/watch no band.png"]
set -e
cd "${0:A:h}"
python3 -W ignore cutout.py "${1:-$HOME/Downloads/watch no band.png}" watch-noband.png
# the edit left the outer edge of the right glass band brighter and sharper than Apple's (it read as a white line):
# no brighter than the same edge on the left
python3 -W ignore - <<'PY'
from PIL import Image
import numpy as np
im = np.asarray(Image.open('watch-noband.png').convert('RGBA')).astype(np.float64)
L = im[..., :3].mean(-1)
ys, xs = np.mgrid[0:im.shape[0], 0:im.shape[1]]
band = (xs >= 750) & (xs <= 760) & (ys >= 280) & (ys <= 1060) & (L > 78)
im[..., :3] *= np.where(band, 78 / np.maximum(L, 1), 1.0)[..., None]
Image.fromarray(im.round().astype(np.uint8), 'RGBA').save('watch-noband.png')
PY
echo watch-noband.png
