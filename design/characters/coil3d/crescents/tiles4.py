"""Crescent tiling, fourth cut (to port): each disc paints the crescent its nearer neighbour's disc leaves (so within
a run every pixel is painted by the nearest disc holding it); a disc nearer than both neighbours (an apex of the
run, or a facing end) is painted whole, in strips across the tube every ~2 pt. Which neighbour is nearer is read
off a smoothed depth, so a ripple doesn't make apexes. Stops: the frontmost sphere of the tube within ±3R of arc
(the own run) at the sample point, its normal with the along-tube component removed."""
import numpy as np
from coilpaint import *
import variants as V
from tiles import smoothstep, contact_keep_smooth, fill_crescent_lingrad
from tiles2 import fill_strip_lingrad

M = 8
SS = 1 - 2 * np.arange(M) / (M - 1)

def tiles4(world, S=4, step=2.2, maxturn=0.035, ao=True, contact=True, cue=True, strip=2.2, minstep=0.3, inset=0.35,
           zwin=6, arcwin=3.0, refine=True, axwin=4, smoothaxis=True, dbg=None):
    n = N; q = catmull(world, 5); cnt = len(q); pr = q[:, :2]
    tang = unit(q[np.minimum(cnt - 1, np.arange(cnt) + 2)] - q[np.maximum(0, np.arange(cnt) - 2)])
    cuts = V.cut_slices(q, pr, tang, maxlen=step, maxturn=maxturn)
    kept = [cuts[0]]
    for c in cuts[1:-1]:
        if np.linalg.norm(pr[c] - pr[kept[-1]]) >= minstep: kept.append(c)
    if np.linalg.norm(pr[cuts[-1]] - pr[kept[-1]]) < minstep and len(kept) > 1: kept.pop()
    kept.append(cuts[-1]); cuts = kept
    Sn = len(cuts); C = pr[cuts]; Z = q[cuts, 2]; U = np.array(cuts) / (cnt - 1)
    # smoothed depth for the direction decision
    Zs = np.array([Z[max(0, k - zwin):k + zwin + 1].mean() for k in range(Sn)])
    # the gradient's axis: across the projected tangent, smoothed along the tube (orientations mod 180, weighted by how
    # side-on the tube is) so a foreshortened stretch doesn't swing it from one disc to the next
    lin = np.hypot(tang[:, 0], tang[:, 1]); th = np.arctan2(tang[:, 1], tang[:, 0])
    vv = np.stack([np.cos(2 * th), np.sin(2 * th)], 1) * (lin * lin + 0.02)[:, None]
    ker = np.exp(-0.5 * (np.arange(-3 * axwin, 3 * axwin + 1) / axwin) ** 2); ker /= ker.sum()
    vs = np.stack([np.convolve(np.pad(vv[:, i], 3 * axwin, mode='edge'), ker, mode='valid') for i in range(2)], 1)
    ax_th = np.arctan2(vs[:, 1], vs[:, 0]) / 2
    axis = np.stack([-np.sin(ax_th), np.cos(ax_th)], 1)            # perpendicular to the smoothed tangent
    far_nodes = int(np.ceil(3.5 * R / SEG))
    A = C[:-1]; B = C[1:]; Rr = np.full(Sn - 1, R); Zm = (Z[:-1] + Z[1:]) / 2; ARCs = (U[:-1] + U[1:]) / 2 * LEN
    LO = np.minimum(A, B) - (R + 9); HI = np.maximum(A, B) + (R + 9)
    segs = (A, B, Rr, Zm, ARCs, LO, HI)
    win = int(round(arcwin * R / (LEN / (cnt - 1))))

    def sample(k, p):
        lo = max(0, cuts[k] - win); hi = min(cnt - 1, cuts[k] + win)
        d2 = ((pr[lo:hi + 1] - p) ** 2).sum(1); inside = d2 <= R * R * 1.0001
        if not inside.any(): jb = cuts[k]; dzb = 0.0; best = q[jb, 2]; cxy = pr[jb]; t = tang[jb]
        else:
            dz = np.sqrt(np.clip(R * R - d2, 0, None)); zz = np.where(inside, q[lo:hi + 1, 2] + dz, -1e9)
            j = int(np.argmax(zz)); jb = lo + j; best = zz[j]; dzb = dz[j]; cxy = pr[jb]; t = tang[jb]
            # the sweep is continuous: refine where along it the surface is frontmost (a parabola through the
            # neighbours), so the normal doesn't step from sphere to sphere
            if refine and 0 < j < hi - lo and inside[j - 1] and inside[j + 1]:
                a, b, c = zz[j - 1], zz[j], zz[j + 1]; den = a - 2 * b + c
                if den < -1e-9:
                    f = np.clip(0.5 * (a - c) / den, -0.5, 0.5)
                    jn = jb + (1 if f > 0 else -1); w = abs(f)
                    cxy = pr[jb] * (1 - w) + pr[jn] * w; cz = q[jb, 2] * (1 - w) + q[jn, 2] * w
                    t = unit(tang[jb] * (1 - w) + tang[jn] * w)
                    dd = p - cxy; dzb = np.sqrt(max(0, R * R - dd @ dd)); best = cz + dzb
        Nraw = np.array([p[0] - cxy[0], p[1] - cxy[1], dzb]) / R
        if jb == 0 or jb == cnt - 1: Nv = unit(Nraw)
        else:
            Nv = Nraw - (Nraw @ t) * t; ln = np.linalg.norm(Nv)
            Nv = Nv / ln if ln > 1e-6 else unit(Nraw)
        uj = jb / (cnt - 1)
        col = shade(uj, Nv)
        a = ao_nodes(world, Nv[None], np.array([p[0], p[1], q[jb, 2] + dzb])[None], int(round(uj * (N - 1))), far_nodes)[0] if ao else 0.0
        if contact: a = 1 - (1 - a) * contact_keep_smooth(p, Z[k], U[k] * LEN, segs)
        return darken(col[None], np.array([a]), np.array([Z[k]]))[0] if cue else col * (1 - (1 - TINT) * min(a, 0.85))

    prepared = []
    nstrips = 0
    prev_n = None
    for k in range(Sn):
        zm = Zs[k - 1] if k > 0 else -np.inf; zp = Zs[k + 1] if k < Sn - 1 else -np.inf
        c = C[k]
        if zm > Zs[k] or zp > Zs[k]:
            o = k - 1 if zm > zp else k + 1
            d = C[o] - c; l = np.linalg.norm(d); v = d / l; nrm = np.array([v[1], -v[0]])
            if smoothaxis:
                nrm = axis[cuts[k]].copy()
                if prev_n is not None and nrm @ prev_n < 0: nrm = -nrm
                vp = v - nrm * (v @ nrm); lp = np.linalg.norm(vp); v = vp / lp if lp > 0.3 else v
            prev_n = nrm
            cols = np.array([sample(k, c + (R - inset) * (-np.sqrt(max(0, 1 - s * s)) * v + s * nrm)) for s in SS])
            prepared.append((Z[k], 'crescent', k, o, nrm, cols))
        else:
            nb = k + 1 if k < Sn - 1 else k - 1
            d = C[nb] - c; l = np.linalg.norm(d)
            v = d / l if l > 1e-6 else np.array([1.0, 0]); nrm = np.array([v[1], -v[0]])
            ns = max(3, int(np.ceil(2 * R / strip))); edges = np.linspace(-R, R, ns + 1)
            for i in range(ns):
                lo, hi = edges[i], edges[i + 1]; mid = (lo + hi) / 2
                half = np.sqrt(max(0, R * R - mid * mid)) / R
                cols = np.array([sample(k, c + v * mid + nrm * (s * max(0.0, R * half - inset))) for s in SS])
                prepared.append((Z[k] + i * 1e-6, 'strip', k, (v, lo, hi, max(half, 1e-3)), nrm, cols)); nstrips += 1
    prepared.sort(key=lambda x: (x[0], x[2]))
    img = np.zeros((HH * S, W * S, 3))
    yy, xx = np.mgrid[0:HH * S, 0:W * S]; X = (xx + 0.5) / S - CX; Y = (yy + 0.5) / S - CY
    for z, kind, k, g, nrm, cols in prepared:
        if kind == 'crescent': fill_crescent_lingrad(img, C[k], C[g], nrm, cols, S, X, Y)
        else: fill_strip_lingrad(img, C[k], g[0], g[1], g[2], nrm, cols, S, X, Y, half=g[3])
    if dbg is not None: dbg.update(cuts=cuts, C=C, Z=Z, tiles=prepared, nstrips=nstrips)
    return img, len(prepared)
