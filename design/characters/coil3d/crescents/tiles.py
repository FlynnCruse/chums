"""The crescent tiling: the sphere sweep's footprint is tiled by crescents T_k = disc_k \\ disc_{k+1} (disjoint, their
union the whole sweep but the last disc, which the backward crescents T'_k = disc_k \\ disc_{k-1} of the last few
discs cover). Each tile is a thin band (as wide as the step) along its disc's rim, filled with a linear gradient
across the tube whose stops are the true visible surface sampled on that rim (the frontmost sphere of the tube's own
run there). Painted back to front, so nearer runs cover farther ones; within a run the order doesn't matter."""
import numpy as np
from coilpaint import *
import variants as V
import sweep as SW

M = 8
SS = 1 - 2 * np.arange(M) / (M - 1)

def smoothstep(x):
    x = np.clip(x, 0, 1); return x * x * (3 - 2 * x)

def contact_keep_smooth(sp, me_z, me_arc, segs):
    A, B, Rr, Z, ARC, LO, HI = segs
    wz = smoothstep((Z - me_z - 0.8 * R) / (0.8 * R)); wa = smoothstep((np.abs(ARC - me_arc) - 6 * R) / (1.5 * R))
    sel = (wz > 0) & (wa > 0) & (sp[0] >= LO[:, 0]) & (sp[0] <= HI[:, 0]) & (sp[1] >= LO[:, 1]) & (sp[1] <= HI[:, 1])
    if not sel.any(): return 1.0
    a, b, rr = A[sel], B[sel], Rr[sel]
    ab = b - a; l = np.maximum((ab * ab).sum(1), 1e-9)
    tt = np.clip(((sp - a) * ab).sum(1) / l, 0, 1)
    dist = np.linalg.norm(sp - (a + ab * tt[:, None]), axis=1) - rr
    x = smoothstep(1 - dist / 9)
    return np.prod(1 - 0.65 * x * wz[sel] * wa[sel])

def fill_crescent_lingrad(img, c0, c1, n2, cols, S, X, Y, eps=0.5):
    """Fill the crescent of disc(c0) beyond disc(c1): inside disc(c0), outside disc(c1) shrunk by eps, and on the far
    side of the chord through the two rims' crossing points (so a tiny step gives a hair-thin crescent, never a ring)."""
    lo = np.minimum(c0, c1) - R - 1; hi = np.maximum(c0, c1) + R + 1
    x0 = int(max(0, (lo[0] + CX) * S)); x1 = int(min(W * S, (hi[0] + CX) * S))
    y0 = int(max(0, (lo[1] + CY) * S)); y1 = int(min(HH * S, (hi[1] + CY) * S))
    if x1 <= x0 or y1 <= y0: return
    px = X[y0:y1, x0:x1]; py = Y[y0:y1, x0:x1]
    d = c1 - c0; l = np.linalg.norm(d); v = d / max(l, 1e-9)
    along = (px - c0[0]) * v[0] + (py - c0[1]) * v[1]
    m = ((px - c0[0]) ** 2 + (py - c0[1]) ** 2 <= R * R) & ((px - c1[0]) ** 2 + (py - c1[1]) ** 2 > (R - eps) ** 2) & (along <= l / 2 + eps)
    if not m.any(): return
    s = ((px - c0[0]) * n2[0] + (py - c0[1]) * n2[1]) / R
    k = len(cols); f = (1 - np.clip(s, -1, 1)) / 2 * (k - 1); k0 = np.minimum(k - 2, f.astype(int)); w = f - k0
    col = cols[k0] * (1 - w)[..., None] + cols[k0 + 1] * w[..., None]
    sub = img[y0:y1, x0:x1]; sub[m] = col[m]

def tiles(world, S=4, step=2.2, maxturn=0.035, ao=True, contact=True, cue=True, J=12, qback=None, caps=True, dbg=None):
    n = N; q = catmull(world, 5); cnt = len(q); pr = q[:, :2]
    tang = unit(q[np.minimum(cnt - 1, np.arange(cnt) + 2)] - q[np.maximum(0, np.arange(cnt) - 2)])
    cuts = V.cut_slices(q, pr, tang, maxlen=step, maxturn=maxturn)
    Sn = len(cuts); C = pr[cuts]; Z = q[cuts, 2]; U = np.array(cuts) / (cnt - 1)
    far_nodes = int(np.ceil(3.5 * R / SEG))
    A = C[:-1]; B = C[1:]; Rr = np.full(Sn - 1, R); Zs = (Z[:-1] + Z[1:]) / 2; ARCs = (U[:-1] + U[1:]) / 2 * LEN
    LO = np.minimum(A, B) - (R + 9); HI = np.maximum(A, B) + (R + 9)
    segs = (A, B, Rr, Zs, ARCs, LO, HI)
    if qback is None: qback = int(np.ceil(2 * R / step)) + 2
    # tiles: (k, other, z) -- disc k minus disc `other`
    T = [(k, k + 1) for k in range(Sn - 1)] + [(k, k - 1) for k in range(Sn - 1, max(0, Sn - 1 - qback), -1)]
    def stops_for(k, other):
        c = C[k]; nb = other if other is not None else (k - 1 if k > 0 else k + 1)
        d = C[nb] - c; l = np.linalg.norm(d)
        if l < 1e-6: return None
        v = d / l; nrm = np.array([v[1], -v[0]])
        if other is None: v = np.zeros(2)
        cols = np.zeros((M, 3))
        for i, s in enumerate(SS):
            p = c + R * (-np.sqrt(max(0, 1 - s * s)) * v + s * nrm)
            # the frontmost sphere of the contiguous chain of spheres whose discs hold p (a part of the tube looping
            # back over p is another chain: its own tiles paint there)
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
            a = ao_nodes(world, Nv[None], (np.array([p[0], p[1], q[jb, 2] + dzb]))[None], int(round(uj * (N - 1))), far_nodes)[0] if ao else 0.0
            if contact: a = 1 - (1 - a) * contact_keep_smooth(p, Z[k], U[k] * LEN, segs)
            cols[i] = darken(col[None], np.array([a]), np.array([Z[k]]))[0] if cue else col * (1 - (1 - TINT) * min(a, 0.85))
        return nrm, cols
    prepared = []
    for k, o in T:
        r = stops_for(k, o)
        if r is None: continue
        prepared.append((Z[k], k, o, r[0], r[1]))
    if caps:
        for k in (0, Sn - 1):
            r = stops_for(k, None)
            if r is not None: prepared.append((Z[k] - 1e-3, k, None, r[0], r[1]))
            # the ball: the end sphere's own normals along a ray from the highlight through the centre to the far rim
            e = 0 if k == 0 else cnt - 1; te = tang[e]; face = max(0.0, te[2] if k == Sn - 1 else -te[2])
            if face > 0.05:
                hl = np.array([H[0], H[1]]); hl = hl / np.linalg.norm(hl) * (0.55 * R)
                hc = C[k] + hl; ray = -hl / np.linalg.norm(hl); span = R + np.linalg.norm(hl)
                cols = np.zeros((M, 3))
                for i in range(M):
                    rho = i / (M - 1) * span; pt = hc + ray * rho; dd = pt - C[k]; r2 = dd @ dd
                    Nv = np.array([dd[0], dd[1], np.sqrt(max(0, R * R - r2))]) / R; Nv = unit(Nv)
                    col = shade(e / (cnt - 1), Nv)
                    a = ao_nodes(world, Nv[None], np.array([pt[0], pt[1], q[e, 2] + Nv[2] * R])[None], int(round(e / (cnt - 1) * (N - 1))), far_nodes)[0] if ao else 0.0
                    cols[i] = darken(col[None], np.array([a]), np.array([Z[k]]))[0] if cue else col * (1 - (1 - TINT) * min(a, 0.85))
                prepared.append((Z[k] - 0.5e-3, k, 'ball', (hc, span, face), cols))
    prepared.sort(key=lambda x: (x[0], x[1]))
    img = np.zeros((HH * S, W * S, 3))
    yy, xx = np.mgrid[0:HH * S, 0:W * S]; X = (xx + 0.5) / S - CX; Y = (yy + 0.5) / S - CY
    for z, k, o, nrm, cols in prepared:
        if o is None: fill_disc_lingrad(img, C[k], R, nrm, C[k], R, cols, S, X, Y)
        elif o == 'ball': fill_disc_radial(img, C[k], R, nrm[0], nrm[1], nrm[2], cols, S, X, Y)
        else: fill_crescent_lingrad(img, C[k], C[o], nrm, cols, S, X, Y)
    if dbg is not None: dbg.update(cuts=cuts, C=C, Z=Z, tiles=prepared)
    return img, len(prepared)
