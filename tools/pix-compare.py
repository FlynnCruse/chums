#!/usr/bin/env python3
"""Compare the Pix port's frames (tools/pix-render.swift) with design/pix/reference, pixel for pixel.

    python3 tools/pix-compare.py RENDERED_DIR [OUT_DIR] [--sheets all|diff|none]

Per frame: max and mean absolute difference over RGB, the number of pixels that differ at all, and the number that differ
by more than 8 (a visible step). Writes OUT_DIR/summary.txt, OUT_DIR/summary.json and, for every frame that differs,
OUT_DIR/sheets/<name>.png: reference | port | difference ×8, with the differing pixels boxed. Also OUT_DIR/index.html.
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, 'design', 'pix', 'reference')


def load(path):
    return np.asarray(Image.open(path).convert('RGBA')).astype(np.int16)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = [a for a in sys.argv[1:] if a.startswith('--')]
    rendered = args[0]
    out = args[1] if len(args) > 1 else os.path.join(ROOT, 'app', 'build', 'pix-compare')
    sheets = 'diff'
    states = None
    for o in opts:
        if o.startswith('--sheets='): sheets = o.split('=', 1)[1]
        if o.startswith('--states='): states = o.split('=', 1)[1].split(',')
    os.makedirs(os.path.join(out, 'sheets'), exist_ok=True)
    names = sorted(n[:-4] for n in os.listdir(REF) if n.endswith('.png'))
    if states: names = [n for n in names if n.split('-')[2] in states]
    rows = []
    for name in names:
        rp = os.path.join(rendered, name + '.png')
        if not os.path.exists(rp):
            rows.append(dict(name=name, missing=True)); continue
        a, b = load(os.path.join(REF, name + '.png')), load(rp)
        if a.shape != b.shape:
            rows.append(dict(name=name, shape=[list(a.shape), list(b.shape)])); continue
        d = np.abs(a[:, :, :3] - b[:, :, :3])
        dm = d.max(axis=2)
        differing = int((dm > 0).sum())
        visible = int((dm > 8).sum())
        row = dict(name=name, max=int(dm.max()), mean=float(d.mean()), differing=differing, visible=visible,
                   species=name.split('-')[1], state=name.split('-')[2], stateT=name.split('-')[3])
        rows.append(row)
        if sheets == 'all' or (sheets == 'diff' and differing):
            sheet(a, b, dm, name, os.path.join(out, 'sheets', name + '.png'))
    # summary
    lines = []
    lines.append(f'{"frame":34} {"max":>4} {"mean":>7} {"diff px":>8} {">8":>7}')
    for r in rows:
        if r.get('missing'): lines.append(f'{r["name"]:34} MISSING'); continue
        if r.get('shape'): lines.append(f'{r["name"]:34} SHAPE {r["shape"]}'); continue
        lines.append(f'{r["name"]:34} {r["max"]:4d} {r["mean"]:7.3f} {r["differing"]:8d} {r["visible"]:7d}')
    ok = [r for r in rows if 'max' in r]
    exact = sum(1 for r in ok if r['max'] == 0)
    lines.append('')
    lines.append(f'{exact} of {len(ok)} frames identical; {sum(1 for r in ok if r["max"] <= 2)} within 2; {sum(1 for r in ok if r["visible"] == 0)} with no pixel off by more than 8')
    lines.append('')
    lines.append('per state (both species, four stateT each): max | mean of means | pixels differing | pixels off by > 8')
    for st in ['idle', 'listening', 'thinking', 'compacting', 'working', 'subagents', 'speaking', 'done', 'needs', 'waiting', 'blocked', 'dizzy', 'sleep']:
        for sp in ['apple', 'banana']:
            g = [r for r in ok if r['state'] == st and r['species'] == sp]
            if not g: continue
            lines.append(f'  {st:11} {sp:7} max {max(r["max"] for r in g):3d}  mean {np.mean([r["mean"] for r in g]):6.3f}  differing {sum(r["differing"] for r in g):6d}  >8 {sum(r["visible"] for r in g):6d}')
    text = '\n'.join(lines)
    print(text)
    open(os.path.join(out, 'summary.txt'), 'w').write(text + '\n')
    json.dump(rows, open(os.path.join(out, 'summary.json'), 'w'), indent=1)
    # an index page
    html = ['<meta charset=utf-8><title>Pix port vs reference</title><body style="background:#111;color:#ddd;font:13px ui-monospace,monospace;padding:16px">',
            '<h2>Pix port vs design/pix/reference</h2><pre>', text, '</pre>']
    for r in rows:
        if r.get('differing'):
            html.append(f'<h3 id="{r["name"]}">{r["name"]}: max {r["max"]}, mean {r["mean"]:.3f}, {r["differing"]} px differ, {r["visible"]} by more than 8</h3>'
                        f'<img src="sheets/{r["name"]}.png" style="max-width:100%;image-rendering:pixelated">')
    open(os.path.join(out, 'index.html'), 'w').write('\n'.join(html))
    print(f'\nwritten to {out}')


def sheet(a, b, dm, name, path):
    h, w = dm.shape
    pad, lab = 8, 18
    im = Image.new('RGB', (3 * w + 4 * pad, h + 2 * pad + lab), (24, 24, 28))
    ref = Image.fromarray(a[:, :, :3].astype(np.uint8))
    port = Image.fromarray(b[:, :, :3].astype(np.uint8))
    diff = Image.fromarray(np.clip(np.abs(a[:, :, :3] - b[:, :, :3]) * 8, 0, 255).astype(np.uint8))
    for i, (img, t) in enumerate([(ref, 'reference (Lab, Chrome)'), (port, 'port (Pix.swift)'), (diff, 'difference x8')]):
        x = pad + i * (w + pad)
        im.paste(img, (x, pad + lab))
    dr = ImageDraw.Draw(im)
    dr.text((pad, pad), f'{name}   max {int(dm.max())}  differing {int((dm > 0).sum())} px  (>8: {int((dm > 8).sum())})', fill=(220, 220, 220))
    for i, t in enumerate(['reference (Lab)', 'port (Pix.swift)', 'difference x8']):
        dr.text((pad + i * (w + pad), pad + lab + h + 2), t, fill=(160, 160, 160))
    # box the differing regions on the difference panel
    ys, xs = np.where(dm > 0)
    if len(ys):
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        ox = pad + 2 * (w + pad)
        dr.rectangle([ox + x0 - 2, pad + lab + y0 - 2, ox + x1 + 2, pad + lab + y1 + 2], outline=(255, 80, 80))
    im.save(path)


if __name__ == '__main__':
    main()
