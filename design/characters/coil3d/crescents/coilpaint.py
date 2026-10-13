"""Experiments for Coil's slice renderer: a per-pixel sphere-sweep truth (what the surface really looks like under the
Swift colour model) against painter's-algorithm variants built only from what Canvas can fill (convex polygons and
discs with linear gradients), rasterised in numpy. Frames come from the Swift app's COIL_DUMP (t + 64 x 3 floats)."""
import numpy as np, re, sys
from PIL import Image

import os  # the colour model is in the app (Coil is Noodle since the October 2026 rename)
SWIFT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../../app/ChumsWatch/Rig/NoodleRest.swift')
src = open(SWIFT).read()
def arr3(name):
    body = src.split('static let %s:' % name)[1].split('\n')[0]
    return np.array([[float(a), float(b), float(c)] for a, b, c in re.findall(r'SIMD3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)', body)])
def arrf(name):
    body = src.split('static let %s:' % name)[1].split('\n')[0]
    return np.array([float(v) for v in re.findall(r'-?\d+\.\d+', body.split('=')[1])])
ALB = arr3('albedo'); LIGHT = arrf('light'); SHEEN = arrf('sheen')
LEN = float(re.search(r'length = ([\d.]+)', src).group(1)); R = float(re.search(r'radius = ([\d.]+)', src).group(1))
N = 64; SEG = LEN / (N - 1)
H = np.array([-0.45, -0.62, 0.65]); H /= np.linalg.norm(H)
TINT = np.array([0.42, 0.22, 0.48])
W, HH = 198, 242; CX, CY = 99.0, 138.0

def ease(x):
    x = np.clip(x, 0, 1); return x * x * (3 - 2 * x)
def shs(c, Nv):
    x, y, z = Nv[..., 0], Nv[..., 1], Nv[..., 2]
    return c[0] + c[1] * x + c[2] * y + c[3] * z + c[4] * x * y + c[5] * x * z + c[6] * y * z + c[7] * (x * x - y * y) + c[8] * (3 * z * z - 1)
def shade(u, Nv):
    """The Swift NoodleStage.shade: u along the tube (0 tail, 1 head), Nv unit normals (..., 3)."""
    u = np.asarray(u, float); kn = len(ALB)
    ua = np.minimum(1, u * LEN / 373); f = ua * (kn - 1); k0 = np.minimum(kn - 2, f.astype(int)); w = (f - k0)[..., None]
    alb = ALB[k0] * (1 - w) + ALB[k0 + 1] * w
    hk = (ease((u - 0.86) / 0.14) * 0.85)[..., None]
    alb = alb * (1 - hk) + np.array([1.0, 0.70, 0.13]) * hk
    lit = shs(LIGHT, Nv)[..., None]; sheen = shs(SHEEN, Nv)[..., None]
    spec = (0.2 * np.clip((Nv @ H), 0, None) ** 10)[..., None]
    return alb * lit + sheen + np.array([1, 0.97, 0.92]) * spec
def darken(col, a, z):
    sh = np.minimum(a, 0.85)[..., None]
    zc = np.clip(z / 60, -1, 1); cue = (1 - 0.25 * (0.5 - 0.5 * zc))[..., None]
    return col * (1 - (1 - TINT) * sh) * cue

def load_dump(path):
    raw = np.fromfile(path, np.float32).reshape(-1, 1 + N * 3)
    return raw[:, 0], raw[:, 1:].reshape(-1, N, 3).astype(float)

def catmull(world, sub=5):
    """The Swift's curve: Catmull-Rom through the 64 points, `sub` samples a link."""
    n = len(world); cnt = (n - 1) * sub + 1
    q = np.zeros((cnt, 3))
    for i in range(cnt):
        f = i / sub; j = min(n - 2, int(f)); w = f - j
        p0, p1, p2, p3 = world[max(0, j - 1)], world[j], world[j + 1], world[min(n - 1, j + 2)]
        q[i] = 0.5 * (2 * p1 + (p2 - p0) * w + (2 * p0 - 5 * p1 + 4 * p2 - p3) * w * w + (3 * p1 - p0 - 3 * p2 + p3) * w ** 3)
    return q

def unit(v): return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)

def ao_nodes(world, Nv, surf, i, far):
    """The Swift's 3D proximity shade at surface point(s) with normal(s), against the 64 nodes other than near i."""
    keep = np.ones(surf.shape[:-1])
    for j in range(N):
        if abs(i - j) <= far: continue
        D = world[j] - surf; dd = np.linalg.norm(D, axis=-1)
        nd = (D * Nv).sum(-1) / np.maximum(dd, 1e-6)
        f = np.clip(1 - (dd - R) / (1.8 * R), 0, 1)
        keep *= 1 - np.where((dd <= 2.8 * R) & (nd > 0), nd * f * f, 0)
    return 1 - keep

def truth(world, S=4, sub=20, ao=True, cue=True):
    """Per-pixel sphere sweep: at each pixel the nearest sphere's surface, the tube's normal there (the sphere's normal
    with its component along the tube removed), shaded by the Swift model; AO sampled at the pixel's surface point."""
    q = catmull(world, sub); cnt = len(q); u = np.arange(cnt) / (cnt - 1)
    T = unit(np.roll(q, -1, 0) - np.roll(q, 1, 0)); T[0] = unit(q[1] - q[0]); T[-1] = unit(q[-1] - q[-2])
    img = np.zeros((HH * S, W * S, 3)); zb = np.full((HH * S, W * S), -1e9)
    nid = np.full((HH * S, W * S), -1); nrm = np.zeros((HH * S, W * S, 3))
    yy, xx = np.mgrid[0:HH * S, 0:W * S]; X = (xx + 0.5) / S - CX; Y = (yy + 0.5) / S - CY
    for i in range(cnt):
        p = q[i]
        x0 = int(max(0, (p[0] + CX - R - 1) * S)); x1 = int(min(W * S, (p[0] + CX + R + 1) * S))
        y0 = int(max(0, (p[1] + CY - R - 1) * S)); y1 = int(min(HH * S, (p[1] + CY + R + 1) * S))
        if x1 <= x0 or y1 <= y0: continue
        dx = X[y0:y1, x0:x1] - p[0]; dy = Y[y0:y1, x0:x1] - p[1]
        d2 = dx * dx + dy * dy; m = d2 < R * R
        if not m.any(): continue
        dz = np.sqrt(np.clip(R * R - d2, 0, None)); z = p[2] + dz
        Nraw = np.stack([dx, dy, dz], -1) / R
        t = T[i]
        Nt = Nraw - (Nraw @ t)[..., None] * t
        if i == 0 or i == cnt - 1: Nt = Nraw
        Nt = unit(Nt)
        win = m & (z > zb[y0:y1, x0:x1])
        if not win.any(): continue
        zb[y0:y1, x0:x1][win] = z[win]; nid[y0:y1, x0:x1][win] = i; nrm[y0:y1, x0:x1][win] = Nt[win]
    hit = nid >= 0
    ids = nid[hit]; uu = ids / (cnt - 1); Nv = nrm[hit]
    col = shade(uu, Nv)
    a = np.zeros(len(ids))
    if ao:
        far = int(np.ceil(3.5 * R / SEG))
        # surface points
        surf = np.stack([X[hit], Y[hit], zb[hit]], 1)
        node = np.rint(uu * (N - 1)).astype(int)
        keep = np.ones(len(ids))
        for j in range(N):
            sel = np.abs(node - j) > far
            if not sel.any(): continue
            D = world[j] - surf[sel]; dd = np.linalg.norm(D, axis=1)
            nd = (D * Nv[sel]).sum(1) / np.maximum(dd, 1e-6)
            f = np.clip(1 - (dd - R) / (1.8 * R), 0, 1)
            k = np.ones(len(dd)); ok = (dd <= 2.8 * R) & (nd > 0); k[ok] = 1 - (nd * f * f)[ok]
            keep[sel] *= k
        a = 1 - keep
    zmid = zb[hit] - 0  # depth of the surface; the Swift uses the slice's centre depth: use the sphere centre
    zc = zb[hit] - np.sqrt(np.clip(R * R - 0, 0, None)) * 0
    if cue: col = darken(col, a, q[ids, 2])
    else: col = col * (1 - (1 - TINT) * np.minimum(a, 0.85)[:, None])
    img[hit] = col
    return img

def to_img(img, S, down=2):
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    return im.resize((W * down, HH * down), Image.LANCZOS)

# ---------------------------------------------------------------- painter's variants (numpy rasteriser of fills)
def fill_disc_lingrad(img, c, r, n2, mid, rm, cols, S, X, Y):
    """Fill a disc at c (radius r) with a linear gradient along n2 about `mid` (as Canvas would)."""
    x0 = int(max(0, (c[0] + CX - r - 1) * S)); x1 = int(min(W * S, (c[0] + CX + r + 1) * S))
    y0 = int(max(0, (c[1] + CY - r - 1) * S)); y1 = int(min(HH * S, (c[1] + CY + r + 1) * S))
    if x1 <= x0 or y1 <= y0: return
    px = X[y0:y1, x0:x1]; py = Y[y0:y1, x0:x1]
    m = (px - c[0]) ** 2 + (py - c[1]) ** 2 <= r * r
    if not m.any(): return
    s = ((px - mid[0]) * n2[0] + (py - mid[1]) * n2[1]) / rm
    k = len(cols); f = (1 - np.clip(s, -1, 1)) / 2 * (k - 1); k0 = np.minimum(k - 2, f.astype(int)); w = f - k0
    col = cols[k0] * (1 - w)[..., None] + cols[k0 + 1] * w[..., None]
    sub = img[y0:y1, x0:x1]; sub[m] = col[m]

def fill_poly_lingrad(img, poly, n2, mid, rm, cols, S, X, Y):
    poly = np.asarray(poly)
    lo = poly.min(0); hi = poly.max(0)
    x0 = int(max(0, (lo[0] + CX - 1) * S)); x1 = int(min(W * S, (hi[0] + CX + 1) * S))
    y0 = int(max(0, (lo[1] + CY - 1) * S)); y1 = int(min(HH * S, (hi[1] + CY + 1) * S))
    if x1 <= x0 or y1 <= y0: return
    px = X[y0:y1, x0:x1]; py = Y[y0:y1, x0:x1]
    m = np.ones(px.shape, bool)
    # orientation
    area = 0
    for e in range(len(poly)):
        p, p1 = poly[e], poly[(e + 1) % len(poly)]; area += p[0] * p1[1] - p1[0] * p[1]
    sgn = 1 if area > 0 else -1
    for e in range(len(poly)):
        p0, p1 = poly[e], poly[(e + 1) % len(poly)]
        m &= sgn * ((p1[0] - p0[0]) * (py - p0[1]) - (p1[1] - p0[1]) * (px - p0[0])) >= 0
    if not m.any(): return
    s = ((px - mid[0]) * n2[0] + (py - mid[1]) * n2[1]) / rm
    k = len(cols); f = (1 - np.clip(s, -1, 1)) / 2 * (k - 1); k0 = np.minimum(k - 2, f.astype(int)); w = f - k0
    col = cols[k0] * (1 - w)[..., None] + cols[k0 + 1] * w[..., None]
    sub = img[y0:y1, x0:x1]; sub[m] = col[m]
