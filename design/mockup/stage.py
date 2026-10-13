#!/usr/bin/env python3
"""Renders watches on a stage, each playing its own screen recording, with a moving camera, as a video.

    python3 stage.py spec.json out.mp4

The spec (JSON):
  size     [w, h] of the video (default [1080, 1350])
  fps      frames a second (default 60)
  duration seconds
  bg       background colour (default "#ffffff")
  watch    the watch image (default watch-noband.png here): transparent around it and in its screen opening
  shadow   {"opacity": 0.2, "blur": 26, "dy": 34}: a soft shadow under each watch, in the watch image's pixels
  watches  each {"clip": video, "from": seconds into the clip (default 0), "keys": [{"t", "x", "y", "s", "r", "z"}]}
           or, for cuts on its screen, "cuts": [{"t": when, "clip": video, "from": seconds}] instead of clip and from
           x, y: where its centre is on the stage; s: its size (1 = the watch image's own pixels); r: its tilt in
           degrees; z: in front of the lower ones. Between two keys it eases (slow out, slow in); clips loop.
  camera   keys [{"t", "x", "y", "zoom"}]: the stage point at the centre of the frame, and how much it's enlarged.
  clock    {"clip": video, "at": seconds}: every watch shows the clock from that frame of that clip (recordings made
           minutes apart would otherwise show different times side by side)
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
spec = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
W, H = spec.get('size', [1080, 1350])
FPS = spec.get('fps', 60)
DUR = float(spec['duration'])
BG = spec.get('bg', '#ffffff')

# the watch: cropped to itself; its screen opening; the soft shadow it casts
watch = Image.open(spec.get('watch', os.path.join(HERE, 'watch-noband.png'))).convert('RGBA')
watch = watch.crop(watch.getbbox())
WW, WH = watch.size
alpha = np.asarray(watch)[..., 3]
from scipy import ndimage
lbl, n = ndimage.label(alpha < 128)
edge = set(np.unique(np.concatenate([lbl[0], lbl[-1], lbl[:, 0], lbl[:, -1]])))
sizes = ndimage.sum(np.ones_like(lbl), lbl, range(1, n + 1))
hole_id = [i + 1 for i in np.argsort(-sizes) if i + 1 not in edge][0]
ys, xs = np.nonzero(lbl == hole_id)
M = 4                                                     # the screen runs a little under the bezel all round
HX, HY, HW, HH = xs.min() - M, ys.min() - M, xs.max() - xs.min() + 1 + 2 * M, ys.max() - ys.min() + 1 + 2 * M
sh = spec.get('shadow', {'opacity': 0.2, 'blur': 26, 'dy': 34})
PAD = int(sh['blur'] * 3)
sil = np.maximum(alpha, (lbl == hole_id) * 255).astype(np.uint8)    # the whole watch, screen included
shadow = Image.new('L', (WW + 2 * PAD, WH + 2 * PAD), 0)
shadow.paste(Image.fromarray(sil), (PAD, PAD))
shadow = shadow.filter(ImageFilter.GaussianBlur(sh['blur']))
shadow = Image.merge('RGBA', [Image.new('L', shadow.size, 0)] * 3 + [shadow.point(lambda v: int(v * sh['opacity']))])


def ease(u):
    u = min(1.0, max(0.0, u))
    return u * u * u * (u * (u * 6 - 15) + 10)         # smootherstep: no jolt at either end


def bezier(x1, y1, x2, y2):
    """A CSS-style cubic-bezier timing curve: progress in time -> progress in value."""
    def f(u):
        if u <= 0: return 0.0
        if u >= 1: return 1.0
        lo, hi = 0.0, 1.0
        for _ in range(40):                                  # solve x(s) = u
            m = (lo + hi) / 2
            x = 3 * (1 - m) ** 2 * m * x1 + 3 * (1 - m) * m * m * x2 + m ** 3
            lo, hi = (m, hi) if x < u else (lo, m)
        m = (lo + hi) / 2
        return 3 * (1 - m) ** 2 * m * y1 + 3 * (1 - m) * m * m * y2 + m ** 3
    return f


def at(keys, t, names):
    """The keyed values at time t, eased between keys (a key's "ease": [x1, y1, x2, y2], a cubic bezier, shapes the
    move that arrives at it; without one, smootherstep)."""
    if t <= keys[0]['t']: k = keys[0]; return [k.get(n, d) for n, d in names]
    if t >= keys[-1]['t']: k = keys[-1]; return [k.get(n, d) for n, d in names]
    for a, b in zip(keys, keys[1:]):
        if a['t'] <= t <= b['t']:
            u = (t - a['t']) / max(1e-6, b['t'] - a['t'])
            e = bezier(*b['ease'])(u) if 'ease' in b else ease(u)
            return [a.get(n, d) + (b.get(n, d) - a.get(n, d)) * e for n, d in names]


def fitted(path, at):
    """One frame of a recording, fitted to the screen opening as the clips are."""
    vf = f'scale={HW}:{HH}:force_original_aspect_ratio=decrease:flags=lanczos,pad={HW}:{HH}:(ow-iw)/2:(oh-ih)/2:color=black'
    b = subprocess.check_output(['ffmpeg', '-loglevel', 'error', '-ss', str(at), '-i', path, '-frames:v', '1', '-vf', vf,
                                 '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'])
    return Image.frombytes('RGB', (HW, HH), b)


# the clock: its box in a 396 x 484 screen recording, in the fitted frame
CLOCK = None
if 'clock' in spec:
    k = min(HW / 396, HH / 484); ox, oy = (HW - 396 * k) / 2, (HH - 484 * k) / 2
    box = tuple(round(v) for v in (ox + 296 * k, oy + 28 * k, ox + 382 * k, oy + 64 * k))
    CLOCK = (fitted(spec['clock']['clip'], spec['clock'].get('at', 1)).crop(box), box[:2])


class Clip:
    """A screen recording read frame by frame at the video's rate, looping, fitted to the screen opening."""
    def __init__(self, path, start):
        dur = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path]))
        self.path, self.start, self.dur = path, start, dur
        self.w, self.h = HW, HH
        self._open()
    def _open(self):
        vf = f'fps={FPS},scale={self.w}:{self.h}:force_original_aspect_ratio=decrease:flags=lanczos,pad={self.w}:{self.h}:(ow-iw)/2:(oh-ih)/2:color=black'
        self.p = subprocess.Popen(['ffmpeg', '-loglevel', 'error', '-ss', str(self.start), '-i', self.path, '-vf', vf,
                                   '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], stdout=subprocess.PIPE)
    def next(self):
        b = self.p.stdout.read(self.w * self.h * 3)
        if len(b) < self.w * self.h * 3:
            self.p.kill(); self.start = 0; self._open(); b = self.p.stdout.read(self.w * self.h * 3)
        im = Image.frombytes('RGB', (self.w, self.h), b)
        if CLOCK: im.paste(*CLOCK)
        return im


class Cuts:
    """A watch's screen cutting from one recording to the next at set times (each opened when its turn comes)."""
    def __init__(self, cuts):
        self.cuts, self.i, self.clip = sorted(cuts, key=lambda c: c['t']), -1, None
    def next(self, t):
        while self.i + 1 < len(self.cuts) and t >= self.cuts[self.i + 1]['t'] - 1e-9:
            if self.clip: self.clip.p.kill()
            self.i += 1; c = self.cuts[self.i]; self.clip = Clip(c['clip'], c.get('from', 0))
        return self.clip.next()
    @property
    def p(self): return self.clip.p


watches = [dict(w, clip=Cuts(w['cuts']) if 'cuts' in w else Clip(w['clip'], w.get('from', 0))) for w in spec['watches']]
cams = spec['camera']
enc = subprocess.Popen(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS),
                        '-i', '-', '-c:v', 'libx264', '-crf', '15', '-preset', 'slow', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', OUT],
                       stdin=subprocess.PIPE)


def place(frame, img, cx, cy, S, rot):
    """Draws img (its centre at its middle) onto frame at (cx, cy), scaled S, turned rot degrees: resampled once, only
    over the area it covers; shrunk a lot, it's first reduced cleanly so it doesn't shimmer."""
    if S < 0.7:
        f = S / 0.85
        img = img.resize((max(1, round(img.width * f)), max(1, round(img.height * f))), Image.LANCZOS); S /= f
    w, h = img.size
    r = math.radians(rot); c, s = math.cos(r), math.sin(r)
    corners = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    pts = [(cx + S * (c * x - s * y), cy + S * (s * x + c * y)) for x, y in corners]
    x0, y0 = max(0, math.floor(min(p[0] for p in pts))), max(0, math.floor(min(p[1] for p in pts)))
    x1, y1 = min(W, math.ceil(max(p[0] for p in pts))), min(H, math.ceil(max(p[1] for p in pts)))
    if x1 <= x0 or y1 <= y0: return
    # output (u, v) in the box -> image pixels: centre + R(-rot)(p - (cx, cy)) / S
    a, b, d, e = c / S, s / S, -s / S, c / S
    ox, oy = x0 - cx, y0 - cy
    data = (a, b, w / 2 + a * ox + b * oy, d, e, h / 2 + d * ox + e * oy)
    patch = img.transform((x1 - x0, y1 - y0), Image.AFFINE, data, resample=Image.BICUBIC)
    frame.alpha_composite(patch, (x0, y0))


frames = int(round(DUR * FPS))
for i in range(frames):
    t = i / FPS
    camx, camy, zoom = at(cams, t, [('x', 0), ('y', 0), ('zoom', 1)])
    frame = Image.new('RGBA', (W, H), BG)
    states = []
    for w in watches:
        x, y, s, r, z = at(w['keys'], t, [('x', 0), ('y', 0), ('s', 1), ('r', 0), ('z', 0)])
        states.append((z, x, y, s, r, w))
    screens = [w['clip'].next(t) if isinstance(w['clip'], Cuts) else w['clip'].next() for w in watches]   # every clip moves on
    for (z, x, y, s, r, w), scr in sorted(zip(states, screens), key=lambda q: q[0][0]):
        cx, cy, S = W / 2 + (x - camx) * zoom, H / 2 + (y - camy) * zoom, s * zoom
        img = Image.new('RGBA', (WW, WH), (0, 0, 0, 0))
        img.paste(scr, (HX, HY))
        img.alpha_composite(watch)
        place(frame, shadow, cx + math.sin(math.radians(r)) * 0, cy + sh['dy'] * S, S, r)
        place(frame, img, cx, cy, S, r)
    enc.stdin.write(frame.convert('RGB').tobytes())
    if i % (FPS * 2) == 0: print(f'{t:.0f}s', end=' ', flush=True)
enc.stdin.close(); enc.wait()
for w in watches: w['clip'].p.kill()
print('\n' + OUT)
