"""Builds watch.png: Apple's SE 3 (midnight) photo cut out with Apple's own mask, the screen left see-through.

The photo was shot on white, so the soft pixels along the outside of the watch carry some of that white; they are
un-mixed from it here, so the watch sits cleanly on any background. Around the screen the photo's own black is kept.
Source: apple.com/apple-watch-se-3 ("So much to love"): love_hw (828x1348) and love_hw_mask; on the page the screen
image (584x708) sits under the hardware at (120, 320) in these 2x pixels and shows through the mask's screen hole.
"""
from PIL import Image
import numpy as np
from scipy import ndimage

hw = np.asarray(Image.open('apple-se3-midnight-hw.jpg').convert('RGB')).astype(np.float64)
a = np.asarray(Image.open('apple-se3-midnight-mask.png').convert('RGBA'))[..., 3].astype(np.float64) / 255

# the screen hole: the see-through region around the middle (and a few pixels round it, where the photo is black glass)
lbl, _ = ndimage.label(a < 0.5)
hole = ndimage.binary_dilation(lbl == lbl[674, 414], iterations=4)

# un-mix the white the outer edge was shot on: C = a*F + (1-a)*255  ->  F = (C - (1-a)*255) / a
safe = np.maximum(a, 1e-3)[..., None]
fg = np.clip((hw - (1 - a[..., None]) * 255) / safe, 0, 255)
fg = np.where(hole[..., None], hw, fg)
fg = np.where((a < 0.01)[..., None], 0, fg)

Image.fromarray(np.dstack([fg, a * 255]).round().astype(np.uint8), 'RGBA').save('watch.png')
print('watch.png', fg.shape[1], 'x', fg.shape[0])
