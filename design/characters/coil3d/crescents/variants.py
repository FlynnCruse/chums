"""Painter's variants for Coil, rasterised like Canvas would (fills of convex polygons / discs with linear gradients)."""
import numpy as np
from coilpaint import *

M = 8
SS = 1 - 2 * np.arange(M) / (M - 1)          # the stops' across coordinate, +1 .. -1 (the Swift's k order)

def cut_slices(q, pr, tang, maxlen=2.2, maxturn=0.035):
    cnt = len(q); cuts = [0]; run = 0.0; turned = 0.0
    for i in range(1, cnt):
        run += np.linalg.norm(pr[i] - pr[i - 1]); turned += np.arccos(np.clip(tang[i - 1] @ tang[i], -1, 1))
        if run >= maxlen or turned >= maxturn or i == cnt - 1: cuts.append(i); run = 0; turned = 0
    return cuts

def contact_keep(sp, me_z, me_arc, segs):
    A, B, Rr, Z, ARC, LO, HI = segs
    sel = (Z > me_z + 1.2 * R) & (np.abs(ARC - me_arc) >= 3.5 * R)
    sel &= (sp[0] >= LO[:, 0]) & (sp[0] <= HI[:, 0]) & (sp[1] >= LO[:, 1]) & (sp[1] <= HI[:, 1])
    if not sel.any(): return 1.0
    a, b, rr = A[sel], B[sel], Rr[sel]
    ab = b - a; l = np.maximum((ab * ab).sum(1), 1e-9)
    tt = np.clip(((sp - a) * ab).sum(1) / l, 0, 1)
    dist = np.linalg.norm(sp - (a + ab * tt[:, None]), axis=1) - rr
    x = np.clip(1 - dist / 9, 0, 1)
    return np.prod(1 - 0.65 * x * x * (3 - 2 * x))

def current(world, S=4, contact=True, ao=True, smooth=2, disc_lin=0.6):
    """A port of the Swift draw as of the hand-over: quads between joint bisectors, a near-end disc where the slice is
    foreshortened (lin < 0.6), AO from the 64 nodes' own frames, a contact darkening, colours smoothed by stop index."""
    n = N; q = catmull(world, 5); cnt = len(q)
    pr = q[:, :2]
    tang = unit(q[np.minimum(cnt - 1, np.arange(cnt) + 2)] - q[np.maximum(0, np.arange(cnt) - 2)])
    cuts = cut_slices(q, pr, tang)
    slices = []; prevN = np.array([0, -1.0, 0])
    for s in range(len(cuts) - 1):
        a, b = cuts[s], cuts[s + 1]
        t3 = unit(q[b] - q[a] + tang[a] * 0.001); lin = np.hypot(t3[0], t3[1])
        nrm = prevN if lin < 0.05 else np.array([t3[1] / lin, -t3[0] / lin, 0])
        bn = unit(np.cross(nrm, t3))
        if bn[2] < 0: bn = -bn
        prevN = nrm
        slices.append(dict(a=a, b=b, z=(q[a, 2] + q[b, 2]) / 2, n=nrm, bn=bn, u=(a + b) / 2 / (cnt - 1), t3=t3, lin=lin))
    Sn = len(slices)
    # AO at the nodes, in the nodes' own frames
    far = int(np.ceil(3.5 * R / SEG))
    aoNode = np.zeros((n, M))
    for i in range(n):
        tg = unit(world[min(n - 1, i + 1)] - world[max(0, i - 1)]); lin = np.hypot(tg[0], tg[1])
        nrm = np.array([0, -1.0, 0]) if lin < 0.05 else np.array([tg[1] / lin, -tg[0] / lin, 0])
        bn = unit(np.cross(nrm, tg));
        if bn[2] < 0: bn = -bn
        Nv = SS[:, None] * nrm + np.sqrt(np.clip(1 - SS * SS, 0, None))[:, None] * bn
        aoNode[i] = ao_nodes(world, Nv, world[i] + Nv * R, i, far)
    segs = []
    A = np.array([pr[s['a']] for s in slices]); B = np.array([pr[s['b']] for s in slices])
    Rr = np.full(Sn, R); Z = np.array([s['z'] for s in slices]); ARC = np.array([s['u'] * LEN for s in slices])
    LO = np.minimum(A, B) - (R + 9); HI = np.maximum(A, B) + (R + 9)
    segs = (A, B, Rr, Z, ARC, LO, HI)
    cols = np.zeros((Sn, M, 3))
    for o, sl in enumerate(slices):
        n2 = sl['n'][:2]; mid = (A[o] + B[o]) / 2
        fn = sl['u'] * (n - 1); i0 = min(n - 2, int(fn)); wn = fn - i0
        Nv = SS[:, None] * sl['n'] + np.sqrt(np.clip(1 - SS * SS, 0, None))[:, None] * sl['bn']
        c = shade(np.full(M, sl['u']), Nv)
        a = aoNode[i0] * (1 - wn) + aoNode[i0 + 1] * wn if ao else np.zeros(M)
        if contact:
            for k in range(M):
                sp = mid + n2 * (SS[k] * R)
                keep = contact_keep(sp, sl['z'], ARC[o], segs)
                a[k] = 1 - (1 - a[k]) * keep
        cols[o] = darken(c, a, np.full(M, sl['z']))
    for _ in range(smooth):
        c0 = cols.copy()
        cols[1:-1] = c0[:-2] * 0.25 + c0[1:-1] * 0.5 + c0[2:] * 0.25
    # joints
    J = np.zeros((Sn + 1, 2))
    for k in range(Sn + 1):
        a_ = slices[k - 1]['n'][:2] if k > 0 else slices[0]['n'][:2]
        b_ = slices[k]['n'][:2] if k < Sn else a_
        m2 = a_ + b_; l = np.linalg.norm(m2); J[k] = m2 / l if l > 1e-6 else a_
    cP = np.ones(Sn); cM = np.ones(Sn)
    for k in range(Sn):
        dn = J[k] - J[k + 1]; den = dn @ dn
        if den <= 1e-10: continue
        tt = ((B[k] - A[k]) @ dn) / den
        lim = np.clip(0.97 * abs(tt) / R, 0, 1)
        if tt > 0: cP[k] = lim
        else: cM[k] = lim
    offP = np.ones(Sn + 1); offM = np.ones(Sn + 1)
    for k in range(Sn + 1):
        offP[k] = min(cP[k - 1] if k > 0 else 1, cP[k] if k < Sn else 1)
        offM[k] = min(cM[k - 1] if k > 0 else 1, cM[k] if k < Sn else 1)
    order = sorted(range(Sn), key=lambda o: (Z[o], o))
    img = np.zeros((HH * S, W * S, 3))
    yy, xx = np.mgrid[0:HH * S, 0:W * S]; X = (xx + 0.5) / S - CX; Y = (yy + 0.5) / S - CY
    for o in order:
        sl = slices[o]; n2 = sl['n'][:2]
        d2 = B[o] - A[o]; l2 = np.linalg.norm(d2); ext = d2 / l2 * 0.6 if l2 > 1e-6 else np.zeros(2)
        mid = (A[o] + B[o]) / 2
        ja, jb = J[o], J[o + 1]
        quad = [A[o] + ja * (R * offP[o]) - ext, B[o] + jb * (R * offP[o + 1]) + ext, B[o] - jb * (R * offM[o + 1]) + ext, A[o] - ja * (R * offM[o]) - ext]
        if l2 > 1e-6: fill_poly_lingrad(img, quad, n2, mid, R, cols[o], S, X, Y)
        if o == 0: fill_disc_lingrad(img, A[o], R, n2, mid, R, cols[o], S, X, Y)
        if o == Sn - 1: fill_disc_lingrad(img, B[o], R, n2, mid, R, cols[o], S, X, Y)
        if sl['lin'] < disc_lin and o != 0 and o != Sn - 1:
            fill_disc_lingrad(img, B[o] if sl['t3'][2] > 0 else A[o], R, n2, mid, R, cols[o], S, X, Y)
    return img

def smooth_dirs(d2, lin, win):
    """Smooth 2D line orientations (mod 180) along the tube, weighted by how side-on the tube is: doubled angles."""
    th = np.arctan2(d2[:, 1], d2[:, 0])
    v = np.stack([np.cos(2 * th), np.sin(2 * th)], 1) * np.maximum(lin, 0.02)[:, None]
    k = np.exp(-0.5 * (np.arange(-3 * win, 3 * win + 1) / win) ** 2); k /= k.sum()
    vs = np.stack([np.convolve(np.pad(v[:, i], 3 * win, mode='edge'), k, mode='valid') for i in range(2)], 1)
    th2 = np.arctan2(vs[:, 1], vs[:, 0]) / 2
    return np.stack([np.cos(th2), np.sin(th2)], 1)

def discs(world, S=4, step=2.0, maxturn=0.035, contact=True, ao=True, smooth=0, dirwin=0, pure=False):
    """A sphere sweep painted back to front: at every cut a disc of radius R, filled with a linear gradient across the
    tube (perpendicular to the projected tangent) whose stops are the Swift shading at the cross-section's normals.
    No quads, no joints. `dirwin` smooths the across direction along the tube (in fine samples)."""
    n = N; q = catmull(world, 5); cnt = len(q)
    pr = q[:, :2]
    tang = unit(q[np.minimum(cnt - 1, np.arange(cnt) + 2)] - q[np.maximum(0, np.arange(cnt) - 2)])
    lin_all = np.hypot(tang[:, 0], tang[:, 1])
    if dirwin > 0: dirs = smooth_dirs(tang[:, :2], lin_all, dirwin)
    cuts = cut_slices(q, pr, tang, maxlen=step, maxturn=maxturn)
    centres = cuts
    Sn = len(centres)
    fr = []
    prevN = np.array([0, -1.0, 0])
    for c in centres:
        t3 = tang[c]; lin = lin_all[c]
        if dirwin > 0:
            d = dirs[c]; nrm = np.array([-d[1], d[0], 0.0])    # perpendicular to the smoothed direction
            if nrm @ prevN < 0: nrm = -nrm
        else:
            nrm = prevN if lin < 0.05 else np.array([t3[1] / lin, -t3[0] / lin, 0])
            if nrm @ prevN < 0: nrm = -nrm
        bn = unit(np.cross(nrm, t3))
        if bn[2] < 0: bn = -bn
        prevN = nrm
        fr.append((nrm, bn, t3, lin))
    far = int(np.ceil(3.5 * R / SEG))
    Z = q[centres, 2]; U = np.array(centres) / (cnt - 1); ARC = U * LEN; P2 = pr[centres]
    # contact table: short segments between consecutive centres
    A = P2[:-1]; B = P2[1:]; Rr = np.full(Sn - 1, R); Zs = (Z[:-1] + Z[1:]) / 2; ARCs = (ARC[:-1] + ARC[1:]) / 2
    LO = np.minimum(A, B) - (R + 9); HI = np.maximum(A, B) + (R + 9)
    segs = (A, B, Rr, Zs, ARCs, LO, HI)
    cols = np.zeros((Sn, M, 3))
    for o in range(Sn):
        nrm, bn, t3, lin = fr[o]
        Nv = SS[:, None] * nrm + np.sqrt(np.clip(1 - SS * SS, 0, None))[:, None] * bn
        c = shade(np.full(M, U[o]), Nv)
        a = np.zeros(M)
        if ao:
            i = int(round(U[o] * (n - 1)))
            a = ao_nodes(world, Nv, q[centres[o]] + Nv * R, i, far)
        if contact:
            for k in range(M):
                sp = P2[o] + nrm[:2] * (SS[k] * R)
                a[k] = 1 - (1 - a[k]) * contact_keep(sp, Z[o], ARC[o], segs)
        cols[o] = darken(c, a, np.full(M, Z[o]))
    for _ in range(smooth):
        c0 = cols.copy(); cols[1:-1] = c0[:-2] * 0.25 + c0[1:-1] * 0.5 + c0[2:] * 0.25
    order = sorted(range(Sn), key=lambda o: (Z[o], o))
    img = np.zeros((HH * S, W * S, 3))
    yy, xx = np.mgrid[0:HH * S, 0:W * S]; X = (xx + 0.5) / S - CX; Y = (yy + 0.5) / S - CY
    for o in order:
        nrm = fr[o][0]
        fill_disc_lingrad(img, P2[o], R, nrm[:2], P2[o], R, cols[o], S, X, Y)
    return img, Sn
