"""The sphere-sweep painter: discs at every cut, back to front, each with a linear gradient across whose stops are the
true visible surface (the frontmost sphere of the tube's own run at that screen point: its normal with the component
along the tube removed), sampled on the rim where that disc actually shows (toward its farther neighbour)."""
import numpy as np
from coilpaint import *
import variants as V

M = 8
SS = 1 - 2 * np.arange(M) / (M - 1)

def frames_nodes(world):
    """AO at the 64 nodes: for each node, the shade for the m directions of its own frame (n_i across, bn_i toward you)."""
    n = N; far = int(np.ceil(3.5 * R / SEG))
    aoN = np.zeros((n, M)); nF = np.zeros((n, 3)); bF = np.zeros((n, 3))
    for i in range(n):
        tg = unit(world[min(n - 1, i + 1)] - world[max(0, i - 1)]); lin = np.hypot(tg[0], tg[1])
        nrm = np.array([0, -1.0, 0]) if lin < 0.05 else np.array([tg[1] / lin, -tg[0] / lin, 0])
        bn = unit(np.cross(nrm, tg))
        if bn[2] < 0: bn = -bn
        Nv = SS[:, None] * nrm + np.sqrt(np.clip(1 - SS * SS, 0, None))[:, None] * bn
        aoN[i] = ao_nodes(world, Nv, world[i] + Nv * R, i, far); nF[i] = nrm; bF[i] = bn
    return aoN, nF, bF

def ao_lookup(aoN, nF, u, Nv):
    """AO for a surface normal Nv near u along the tube: the node's table by the across coordinate of Nv in its frame."""
    fn = u * (N - 1); i0 = min(N - 2, int(fn)); w = fn - i0
    out = 0.0
    for i, wi in ((i0, 1 - w), (i0 + 1, w)):
        s = np.clip(Nv @ nF[i], -1, 1)
        f = (1 - s) / 2 * (M - 1); k0 = min(M - 2, int(f)); wk = f - k0
        out += wi * (aoN[i][k0] * (1 - wk) + aoN[i][k0 + 1] * wk)
    return out

def sweep(world, S=4, step=2.2, maxturn=0.035, ao=True, contact=True, cue=True, J=12, stops=M, caps='linear', dbg=None):
    n = N; q = catmull(world, 5); cnt = len(q); pr = q[:, :2]
    tang = unit(q[np.minimum(cnt - 1, np.arange(cnt) + 2)] - q[np.maximum(0, np.arange(cnt) - 2)])
    cuts = V.cut_slices(q, pr, tang, maxlen=step, maxturn=maxturn)
    Sn = len(cuts); C = pr[cuts]; Z = q[cuts, 2]; U = np.array(cuts) / (cnt - 1)
    ss = 1 - 2 * np.arange(stops) / (stops - 1)
    if ao: aoN, nF, bF = frames_nodes(world)
    # contact table (segments between cuts)
    A = C[:-1]; B = C[1:]; Rr = np.full(Sn - 1, R); Zs = (Z[:-1] + Z[1:]) / 2; ARCs = (U[:-1] + U[1:]) / 2 * LEN
    LO = np.minimum(A, B) - (R + 9); HI = np.maximum(A, B) + (R + 9)
    segs = (A, B, Rr, Zs, ARCs, LO, HI)
    cols = np.zeros((Sn, stops, 3)); axes = np.zeros((Sn, 2))
    prevN = None
    for k in range(Sn):
        c = C[k]; zk = Z[k]
        zm = Z[k - 1] if k > 0 else -1e9; zp = Z[k + 1] if k < Sn - 1 else -1e9
        # the gradient axis: across the projected tangent (the smoothed-by-cut-span direction)
        a_ = cuts[max(0, k - 1)]; b_ = cuts[min(Sn - 1, k + 1)]
        d = pr[b_] - pr[a_]; l = np.linalg.norm(d)
        if l > 1e-3: nrm = np.array([d[1], -d[0]]) / l
        else: nrm = prevN if prevN is not None else np.array([0, -1.0])
        if prevN is not None and nrm @ prevN < 0: nrm = -nrm
        prevN = nrm
        # where this disc shows: toward its farther neighbour; at a depth maximum, its own across line
        if zm > zk or zp > zk:
            far_c = C[k - 1] if (k > 0 and (k == Sn - 1 or zm < zp)) else C[k + 1]
            v = far_c - c; lv = np.linalg.norm(v); v = v / lv if lv > 1e-6 else np.zeros(2)
            v = v - nrm * (v @ nrm); lv = np.linalg.norm(v); v = v / lv if lv > 1e-6 else np.zeros(2)
        else: v = np.zeros(2)
        axes[k] = nrm
        for i, s in enumerate(ss):
            p = c + R * (np.sqrt(max(0, 1 - s * s)) * v + s * nrm)
            # the frontmost sphere of this run at p
            lo = max(0, cuts[k] - J); hi = min(cnt - 1, cuts[k] + J)
            best = -1e9; jb = cuts[k]; dzb = 0
            for j in range(lo, hi + 1):
                dx = p - pr[j]; d2 = dx @ dx
                if d2 > R * R * 1.0001: continue
                dz = np.sqrt(max(0, R * R - d2)); zz = q[j, 2] + dz
                if zz > best: best = zz; jb = j; dzb = dz
            Nraw = np.array([p[0] - pr[jb][0], p[1] - pr[jb][1], dzb]) / R
            if jb == 0 or jb == cnt - 1: Nv = unit(Nraw)
            else:
                t = tang[jb]; Nv = Nraw - (Nraw @ t) * t; ln = np.linalg.norm(Nv)
                Nv = Nv / ln if ln > 1e-6 else unit(Nraw)
            uj = jb / (cnt - 1)
            col = shade(uj, Nv)
            a = ao_lookup(aoN, nF, uj, Nv) if ao else 0.0
            if contact: a = 1 - (1 - a) * V.contact_keep(p, zk, U[k] * LEN, segs)
            cols[k, i] = darken(col[None], np.array([a]), np.array([zk]))[0] if cue else col * (1 - (1 - TINT) * min(a, 0.85))
    order = sorted(range(Sn), key=lambda o: (Z[o], o))
    img = np.zeros((HH * S, W * S, 3))
    yy, xx = np.mgrid[0:HH * S, 0:W * S]; X = (xx + 0.5) / S - CX; Y = (yy + 0.5) / S - CY
    for o in order:
        fill_disc_lingrad(img, C[o], R, axes[o], C[o], R, cols[o], S, X, Y)
    if dbg is not None: dbg.update(cuts=cuts, cols=cols, axes=axes, C=C, Z=Z)
    return img, Sn
