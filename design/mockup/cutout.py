#!/usr/bin/env python3
"""Cuts a watch image shot (or painted) on white out of its white: the background and the screen become transparent.

    python3 cutout.py IN OUT.png [--white 238]

Anything darker than --white (0-255, default 238) is the object, small light spots inside it (glints on the glass and
the case) are kept; the screen, the big white opening inside the case, becomes see-through like the background. Along
every edge the pixels mixing object and white are given their share of transparency and their white taken out, so the
cut-out sits cleanly on any background. Faint marks in the white (left over from an edit) are dropped.
For a light-coloured object (a white lanyard) on white this can't tell the two apart: shoot or paint it on another
colour, or keep it on its own layer and cut it out by hand.
"""
import argparse

import numpy as np
from PIL import Image
from scipy import ndimage

p = argparse.ArgumentParser()
p.add_argument('src'); p.add_argument('out')
p.add_argument('--white', type=float, default=238)
o = p.parse_args()

C = np.asarray(Image.open(o.src).convert('RGB')).astype(np.float64)
L = C.mean(axis=2)
W = np.array([255.0, 255.0, 255.0])

# the object: darker than the white, with its small light spots filled in (not the screen: it's far too big)
solid = L < o.white
lbl, n = ndimage.label(~solid)
sizes = ndimage.sum(np.ones_like(lbl), lbl, range(1, n + 1))
small = np.isin(lbl, [i + 1 for i, s in enumerate(sizes) if s < 4000])
solid |= small
# keep the main object only (drop specks)
lbl, n = ndimage.label(solid)
sizes = ndimage.sum(np.ones_like(lbl), lbl, range(1, n + 1))
solid = lbl == (np.argmax(sizes) + 1)

# along the edges: the object's own colour there (averaged from solid pixels nearby), and how much of each pixel is it
core = ndimage.binary_erosion(solid, iterations=2)
w = ndimage.uniform_filter(core.astype(float), 9)
F = np.stack([ndimage.uniform_filter(C[..., c] * core, 9) for c in range(3)], -1) / np.maximum(w, 1e-6)[..., None]
d = W - F
alpha_soft = np.clip(((W - C) * d).sum(-1) / np.maximum((d * d).sum(-1), 1e-6), 0, 1)
near = ndimage.binary_dilation(solid, iterations=3) & ~core
alpha = np.where(core, 1.0, np.where(near, alpha_soft, 0.0))
alpha[alpha < 0.06] = 0

# the edge pixels take the object's own colour there (un-mixing the white from a nearly clear pixel only amplifies
# its noise into a grey seam)
fg = np.where(core[..., None], C, np.clip(F, 0, 255))
fg[alpha == 0] = 0

Image.fromarray(np.dstack([fg, alpha * 255]).round().astype(np.uint8), 'RGBA').save(o.out)
print(o.out, C.shape[1], 'x', C.shape[0])
