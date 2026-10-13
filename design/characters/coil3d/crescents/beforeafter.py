"""Before/after close-ups: the same frames from two renders (scale 3: 594 x 726), cropped where the tube runs toward
or away from you, side by side, zoomed. Usage: beforeafter.py before-dir after-dir out.png t1,t2,... [zoom]"""
import sys, numpy as np
from PIL import Image, ImageDraw, ImageFont
bd, ad, out = sys.argv[1], sys.argv[2], sys.argv[3]
times = [float(x) for x in sys.argv[4].split(',')]
zoom = float(sys.argv[5]) if len(sys.argv) > 5 else 2.0
S = 3
def frame(d, t):
    return Image.open('%s/f%05d.png' % (d, int(round(t * 60)))).convert('RGB')
def crop_box(im):
    """A box round the character (non-black pixels, below the clock/avatar strip), square-ish."""
    a = np.asarray(im).astype(int).sum(2)
    a[:int(28 * S)] = 0                    # the clock and avatar strip
    a[int(185 * S):] = 0                   # the caption band
    ys, xs = np.nonzero(a > 60)
    if len(xs) == 0: return (0, 0, im.size[0], im.size[1])
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    return (max(0, x0 - 6), max(0, y0 - 6), min(im.size[0], x1 + 6), min(im.size[1], y1 + 6))
try: font = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', 22)
except Exception: font = ImageFont.load_default()
rows = []
for t in times:
    b, a = frame(bd, t), frame(ad, t)
    box = crop_box(b)
    bx = tuple(max(0, min(v, w)) for v, w in zip(box, (b.size[0], b.size[1], b.size[0], b.size[1])))
    bb, aa = b.crop(bx), a.crop(bx)
    w, h = bb.size; tw, th = int(w * zoom), int(h * zoom)
    rows.append((t, bb.resize((tw, th), Image.LANCZOS), aa.resize((tw, th), Image.LANCZOS)))
W = max(r[1].size[0] for r in rows) * 2 + 24
H = sum(r[1].size[1] + 40 for r in rows) + 8
sheet = Image.new('RGB', (W, H), (18, 18, 20)); dr = ImageDraw.Draw(sheet)
y = 8
for t, bb, aa in rows:
    sheet.paste(bb, (8, y + 28)); sheet.paste(aa, (16 + bb.size[0], y + 28))
    dr.text((8, y + 4), 'before  t=%.1fs' % t, fill=(200, 200, 205), font=font)
    dr.text((16 + bb.size[0], y + 4), 'after  t=%.1fs' % t, fill=(200, 200, 205), font=font)
    y += bb.size[1] + 40
sheet.save(out); print(out, sheet.size)
