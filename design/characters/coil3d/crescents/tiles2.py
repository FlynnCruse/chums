"""Crescent tiling, second cut: every disc paints what its NEARER neighbour's disc doesn't cover (a crescent on its far
side, sampled on that rim), so within a run each pixel is painted by the nearest disc holding it; a disc nearer than
both neighbours (a depth apex, the facing end) is painted whole, as three strips across so the colour along the tube
is sampled every ~10 pt. Stops are the true visible surface: the frontmost sphere of the contiguous chain of spheres
holding the sample point, its normal with the component along the tube removed (the end spheres: the sphere's own).
Painted back to front."""
import numpy as np
from coilpaint import *
import variants as V
from tiles import smoothstep, contact_keep_smooth, fill_crescent_lingrad

M = 8
SS = 1 - 2 * np.arange(M) / (M - 1)

def fill_strip_lingrad(img, c, v, lo, hi, n2, cols, S, X, Y, eps=0.5, half=1.0):
    """Fill the part of disc(c) with lo <= (p-c).v <= hi (chords across v), widened by eps, gradient along n2."""
    x0 = int(max(0, (c[0] + CX - R - 1) * S)); x1 = int(min(W * S, (c[0] + CX + R + 1) * S))
    y0 = int(max(0, (c[1] + CY - R - 1) * S)); y1 = int(min(HH * S, (c[1] + CY + R + 1) * S))
    if x1 <= x0 or y1 <= y0: return
    px = X[y0:y1, x0:x1]; py = Y[y0:y1, x0:x1]
    t = (px - c[0]) * v[0] + (py - c[1]) * v[1]
    m = ((px - c[0]) ** 2 + (py - c[1]) ** 2 <= R * R) & (t >= lo - eps) & (t <= hi + eps)
    if not m.any(): return
    s = ((px - c[0]) * n2[0] + (py - c[1]) * n2[1]) / (R * half)
    k = len(cols); f = (1 - np.clip(s, -1, 1)) / 2 * (k - 1); k0 = np.minimum(k - 2, f.astype(int)); w = f - k0
    col = cols[k0] * (1 - w)[..., None] + cols[k0 + 1] * w[..., None]
    sub = img[y0:y1, x0:x1]; sub[m] = col[m]

def tiles2(world, S=4, step=2.2, maxturn=0.035, ao=True, contact=True, cue=True, strips=3, dbg=None):
    n = N; q = catmull(world, 5); cnt = len(q); pr = q[:, :2]
    tang = unit(q[np.minimum(cnt - 1, np.arange(cnt) + 2)] - q[np.maximum(0, np.arange(cnt) - 2)])
    cuts = V.cut_slices(q, pr, tang, maxlen=step, maxturn=maxturn)
    Sn = len(cuts); C = pr[cuts]; Z = q[cuts, 2]; U = np.array(cuts) / (cnt - 1)
    far_nodes = int(np.ceil(3.5 * R / SEG))
    A = C[:-1]; B = C[1:]; Rr = np.full(Sn - 1, R); Zs = (Z[:-1] + Z[1:]) / 2; ARCs = (U[:-1] + U[1:]) / 2 * LEN
    LO = np.minimum(A, B) - (R + 9); HI = np.maximum(A, B) + (R + 9)
    segs = (A, B, Rr, Zs, ARCs, LO, HI)

    def sample(k, p):
        """The true visible surface of this run at screen point p near disc k: colour."""
        best = -1e9; jb = cuts[k]; dzb = 0.0
        for direction in (-1, 1):
            j = cuts[k] if direction < 0 else cuts[k] + 1
            while 0 <= j < cnt:
                dx = p - pr[j]; d2 = dx @ dx
                if d2 > R * R * 1.0001: break
                dz = np.sqrt(max(0, R * R - d2)); zz = q[j, 2] + dz
                if zz > best: best = zz; jb = j; dzb = dz
                j += direction
        Nraw = np.array([p[0] - pr[jb][0], p[1] - pr[jb][1], dzb]) / R
        if jb == 0 or jb == cnt - 1: Nv = unit(Nraw)
        else:
            t = tang[jb]; Nv = Nraw - (Nraw @ t) * t; ln = np.linalg.norm(Nv)
            Nv = Nv / ln if ln > 1e-6 else unit(Nraw)
        uj = jb / (cnt - 1)
        col = shade(uj, Nv)
        a = ao_nodes(world, Nv[None], np.array([p[0], p[1], q[jb, 2] + dzb])[None], int(round(uj * (N - 1))), far_nodes)[0] if ao else 0.0
        if contact: a = 1 - (1 - a) * contact_keep_smooth(p, Z[k], U[k] * LEN, segs)
        return darken(col[None], np.array([a]), np.array([Z[k]]))[0] if cue else col * (1 - (1 - TINT) * min(a, 0.85))

    prepared = []     # (z, kind, k, geometry, nrm, cols)
    for k in range(Sn):
        zm = Z[k - 1] if k > 0 else -np.inf; zp = Z[k + 1] if k < Sn - 1 else -np.inf
        c = C[k]
        if zm > Z[k] or zp > Z[k]:
            o = k - 1 if zm > zp else k + 1
            d = C[o] - c; l = np.linalg.norm(d)
            if l < 1e-6: continue
            v = d / l; nrm = np.array([v[1], -v[0]])
            cols = np.array([sample(k, c + R * (-np.sqrt(max(0, 1 - s * s)) * v + s * nrm)) for s in SS])
            prepared.append((Z[k], 'crescent', k, o, nrm, cols))
        else:
            # nearer than both neighbours: the whole disc, in strips along the tube
            nb = k + 1 if k < Sn - 1 else k - 1
            d = C[nb] - c; l = np.linalg.norm(d)
            v = d / l if l > 1e-6 else np.array([1.0, 0]); nrm = np.array([v[1], -v[0]])
            edges = np.linspace(-R, R, strips + 1)
            for i in range(strips):
                lo, hi = edges[i], edges[i + 1]; mid = (lo + hi) / 2
                half = np.sqrt(max(0, R * R - mid * mid)) / R
                cols = np.array([sample(k, c + v * mid + nrm * (s * R * half)) for s in SS])
                prepared.append((Z[k] + i * 1e-6, 'strip', k, (v, lo, hi), nrm, cols))
    prepared.sort(key=lambda x: (x[0], x[2]))
    img = np.zeros((HH * S, W * S, 3))
    yy, xx = np.mgrid[0:HH * S, 0:W * S]; X = (xx + 0.5) / S - CX; Y = (yy + 0.5) / S - CY
    for z, kind, k, g, nrm, cols in prepared:
        if kind == 'crescent': fill_crescent_lingrad(img, C[k], C[g], nrm, cols, S, X, Y)
        else: fill_strip_lingrad(img, C[k], g[0], g[1], g[2], nrm, cols, S, X, Y)
    if dbg is not None: dbg.update(cuts=cuts, C=C, Z=Z, tiles=prepared)
    return img, len(prepared)
