#!/usr/bin/env python3
"""Puts a watch-screen video (or image) into Apple's SE 3 photo, on a background of your choice, as a video.

    python3 compose.py SCREEN OUT [--size 1080x1350] [--bg 1d1d1f | --bg-image FILE] [--height 0.86] [--y 0] [--fps 60]

SCREEN  a recording of the watch screen, any size with the screen's shape (396x484 from the Series 7 simulator,
        368x448 from the SE 3 one): it fills the screen's opening in the photo.
OUT     .mp4 (H.264), or .mov for ProRes 4444 with a transparent background (--bg none).
--size    the frame, W x H (default 1080x1350, 4:5; 1080x1080, 1920x1080 and 1080x1920 work too)
--bg      background colour (hex), or none for transparent (.mov only)
--bg-image  an image (or video) behind the watch instead, scaled to cover the frame
--height  how much of the frame the watch takes, its height or its width, whichever fills first (default 0.86)
--y       move the watch down (+) or up (-), in pixels of the frame

--watch   the watch image (default watch.png here): any PNG with a transparent background and a transparent screen
          opening; the opening is found in it, so an edited watch (other strap, a lanyard, a bigger canvas) just works.
"""
import argparse
import os
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))

p = argparse.ArgumentParser()
p.add_argument('screen'); p.add_argument('out')
p.add_argument('--size', default='1080x1350')
p.add_argument('--bg', default='1d1d1f')
p.add_argument('--bg-image')
p.add_argument('--height', type=float, default=0.86)
p.add_argument('--y', type=float, default=0)
p.add_argument('--fps', type=int, default=60)
p.add_argument('--watch', default=os.path.join(HERE, 'watch.png'))
o = p.parse_args()

# the watch itself, without the empty margin round it (--height is the watch's, however much canvas it came on)
alpha = np.asarray(Image.open(o.watch).convert('RGBA'))[..., 3]
ys, xs = np.nonzero(alpha > 8)
CX, CY = xs.min(), ys.min()
alpha = alpha[CY:ys.max() + 1, CX:xs.max() + 1]
WATCH_H, WATCH_W = alpha.shape
# the screen's opening: the biggest see-through region that doesn't touch the image's edge
lbl, n = ndimage.label(alpha < 128)
edge = set(np.unique(np.concatenate([lbl[0], lbl[-1], lbl[:, 0], lbl[:, -1]])))
sizes = ndimage.sum(np.ones_like(lbl), lbl, range(1, n + 1))
inner = [i + 1 for i in np.argsort(-sizes) if i + 1 not in edge]
if not inner:
    sys.exit(f'no screen opening found in {o.watch}: the screen has to be transparent')
ys, xs = np.nonzero(lbl == inner[0])
HOLE_X, HOLE_Y, HOLE_W, HOLE_H = xs.min(), ys.min(), xs.max() - xs.min() + 1, ys.max() - ys.min() + 1

W, H = map(int, o.size.lower().split('x'))
k = min(H * o.height / WATCH_H, W * o.height / WATCH_W)          # it fits the frame both ways
ww, wh = round(WATCH_W * k / 2) * 2, round(WATCH_H * k / 2) * 2
x0, y0 = (W - ww) // 2, round((H - wh) / 2 + o.y)
# the screen video fills the opening and runs a few pixels under the bezel all round: the opening's edge is soft
# (half see-through), and anything short of it lets the background through as a thin line
M = 4
sx, sy = x0 + int((HOLE_X - M) * k), y0 + int((HOLE_Y - M) * k)
sw, sh = int((HOLE_W + 2 * M) * k / 2 + 1) * 2, int((HOLE_H + 2 * M) * k / 2 + 1) * 2
alpha = o.bg == 'none'
if alpha and not o.out.endswith('.mov'):
    sys.exit('a transparent background needs a .mov output (ProRes 4444)')

image = o.screen.lower().endswith(('.png', '.jpg', '.jpeg'))
inputs = (['-loop', '1'] if image else []) + ['-i', o.screen, '-loop', '1', '-i', o.watch]
if o.bg_image:
    inputs += (['-loop', '1'] if o.bg_image.lower().endswith(('.png', '.jpg', '.jpeg')) else []) + ['-i', o.bg_image]
    bg = f'[2:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},fps={o.fps},format=rgba[bg]'
else:
    color = 'black@0.0' if alpha else '0x' + o.bg.lstrip('#')
    bg = f'color=c={color}:s={W}x{H}:r={o.fps},format=rgba[bg]'
graph = ';'.join([
    bg,
    f'[0:v]fps={o.fps},scale={sw}:{sh}:force_original_aspect_ratio=decrease:flags=lanczos,'
    f'pad={sw}:{sh}:(ow-iw)/2:(oh-ih)/2:color=black,format=rgba[scr]',
    f'[1:v]crop={WATCH_W}:{WATCH_H}:{CX}:{CY},scale={ww}:{wh}:flags=bicubic,format=rgba[hw]',
    f'[bg][scr]overlay={sx}:{sy}:shortest=1[b1]',
    f'[b1][hw]overlay={x0}:{y0}:shortest=1' + ('' if alpha else ',format=yuv420p') + '[v]',
])
codec = ['-c:v', 'prores_ks', '-profile:v', '4444', '-pix_fmt', 'yuva444p10le'] if alpha else \
        ['-c:v', 'libx264', '-crf', '14', '-preset', 'slow', '-pix_fmt', 'yuv420p', '-movflags', '+faststart']
duration = ['-t', '5'] if image else []
cmd = ['ffmpeg', '-loglevel', 'error', '-y', *inputs, '-filter_complex', graph, '-map', '[v]', *duration, *codec, o.out]
subprocess.run(cmd, check=True)
print(o.out)
