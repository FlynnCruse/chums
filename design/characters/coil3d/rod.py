"""Discrete rod representation of the tube's centreline (Bergou-style): per-segment length (constant), per-vertex
material curvature (kappa1, kappa2) in a twist-free (Bishop / rotation-minimising) frame. Shapes are blended in this
space, then rebuilt by forward kinematics from the foot, so a blend is always exactly length L and C1 smooth.
Also: the soft, low-passed self-collision projection used after the kinematic blend."""
import numpy as np

def unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)

def rmf(P):
    """Rotation-minimising frames along polyline P: tangents t (per segment) and normals m1, m2, via Wang et al.'s
    double reflection."""
    t = unit(np.diff(P, axis=0))
    n = len(t)
    m1 = np.zeros_like(t); m2 = np.zeros_like(t)
    # first normal: anything perpendicular to t0
    a = np.array([0.0, 0.0, 1.0]) if abs(t[0, 2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    m1[0] = unit(a - t[0] * (a @ t[0])); m2[0] = np.cross(t[0], m1[0])
    for i in range(n - 1):
        v1 = P[i + 2] - P[i + 1] if False else (P[i + 1] - P[i])  # not used; keep classic form below
        # double reflection
        x0, x1 = P[i], P[i + 1]
        v1 = x1 - x0; c1 = v1 @ v1
        rL = m1[i] - (2 / c1) * (v1 @ m1[i]) * v1
        tL = t[i] - (2 / c1) * (v1 @ t[i]) * v1
        v2 = t[i + 1] - tL; c2 = v2 @ v2
        m1[i + 1] = unit(rL - (2 / max(c2, 1e-18)) * (v2 @ rL) * v2) if c2 > 1e-18 else rL
        m2[i + 1] = np.cross(t[i + 1], m1[i + 1])
    return t, m1, m2

def to_rod(P):
    """P (n,3) equal-arc polyline -> (root, kappa) with root = (p0, t0, m1_0) and kappa (n-2, 2) material
    curvature binormal components in the frame of the previous segment (|kb| = 2 tan(theta/2))."""
    t, m1, m2 = rmf(P)
    kb = 2 * np.cross(t[:-1], t[1:]) / (1 + np.einsum('ij,ij->i', t[:-1], t[1:]))[:, None]
    kappa = np.stack([np.einsum('ij,ij->i', kb, m1[:-1]), np.einsum('ij,ij->i', kb, m2[:-1])], 1)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1).mean()
    return dict(p0=P[0].copy(), t0=t[0].copy(), m0=m1[0].copy(), kappa=kappa, seg=seg)

def rot_axis(v, axis, ang):
    """Rodrigues rotation of v (3,) about unit axis by ang."""
    c, s = np.cos(ang), np.sin(ang)
    return v * c + np.cross(axis, v) * s + axis * (axis @ v) * (1 - c)

def from_rod(rod, n=None):
    """Rebuild the polyline from a rod (exact inverse of to_rod up to float error)."""
    kappa, seg = rod['kappa'], rod['seg']
    m = len(kappa) + 2
    P = np.zeros((m, 3)); P[0] = rod['p0']
    t, m1 = unit(rod['t0']), unit(rod['m0'])
    m1 = unit(m1 - t * (t @ m1)); m2 = np.cross(t, m1)
    P[1] = P[0] + t * seg
    for i in range(m - 2):
        kb = kappa[i, 0] * m1 + kappa[i, 1] * m2
        k = np.linalg.norm(kb)
        if k > 1e-12:
            axis = kb / k; th = 2 * np.arctan(k / 2)
            t = rot_axis(t, axis, th); m1 = rot_axis(m1, axis, th)
            # keep m1 twist-free w.r.t. t (it is by construction, renormalise for drift)
            m1 = unit(m1 - t * (t @ m1)); m2 = np.cross(t, m1)
        P[i + 2] = P[i + 1] + t * seg
    return P

def slerp(a, b, w):
    a, b = unit(a), unit(b)
    d = np.clip(a @ b, -1, 1); th = np.arccos(d)
    if th < 1e-6: return unit(a * (1 - w) + b * w)
    return (np.sin((1 - w) * th) * a + np.sin(w * th) * b) / np.sin(th)

def blend_rods(A, B, w):
    """Blend two rods with per-vertex weight w (scalar or (n-2,) array). Root frame slerped with w at the foot."""
    w = np.broadcast_to(np.asarray(w, float), (len(A['kappa']),))
    w0 = float(w[0])
    t0 = slerp(A['t0'], B['t0'], w0)
    m0 = slerp(A['m0'], B['m0'], w0); m0 = unit(m0 - t0 * (t0 @ m0))
    return dict(p0=A['p0'] * (1 - w0) + B['p0'] * w0, t0=t0, m0=m0,
                kappa=A['kappa'] * (1 - w[:, None]) + B['kappa'] * w[:, None], seg=A['seg'] * (1 - w0) + B['seg'] * w0)

def front_weights(n, f, width=0.25, from_foot=True):
    """A travelling-front weight profile: 0..1 along the rod, the front at progress f in [0,1] (f<0 or >1 pads)."""
    u = np.linspace(0, 1, n)
    x = (f * (1 + width) - width) if from_foot else None
    if from_foot:
        return np.clip((f * (1 + width) - u) / width, 0, 1) ** 2 * (3 - 2 * np.clip((f * (1 + width) - u) / width, 0, 1))
    else:
        v = 1 - u
        q = np.clip((f * (1 + width) - v) / width, 0, 1)
        return q * q * (3 - 2 * q)

def smoothstep(x):
    x = np.clip(x, 0, 1); return x * x * (3 - 2 * x)

# ---------------- self-collision (soft, spatially and temporally smoothed) ----------------

class Collider:
    """Keeps a persistent per-node offset delta that is low-passed toward the separation the kinematic curve needs.
    radii: per-node tube radius (so a swollen head collides correctly). excl: arc separation (pt) under which pairs are
    skipped (adjacent tube)."""
    def __init__(self, n, excl, margin=0.3, rate=12.0, blur=2):
        self.n, self.excl, self.margin, self.rate, self.blur = n, excl, margin, rate, blur
        self.delta = np.zeros((n, 3))

    def target(self, P, radii, iters=3, pin_weight=None):
        n = self.n
        Q = P + self.delta
        s = np.arange(n) * (np.linalg.norm(np.diff(P, axis=0), axis=1).mean())
        far = np.abs(s[:, None] - s[None]) > self.excl
        iu = np.triu_indices(n, 1)
        mask = far[iu]
        I, J = iu[0][mask], iu[1][mask]
        rr = radii[I] + radii[J]
        # weights: the foot side moves less (pin at the foot), the head side more
        wgt = np.linspace(0.15, 1.0, n) if pin_weight is None else pin_weight
        for _ in range(iters):
            d = Q[J] - Q[I]; dist = np.linalg.norm(d, axis=1)
            lim = rr * (1 + self.margin)
            hit = dist < lim
            if not hit.any(): break
            # soft: the push ramps from 0 at lim to full at rr (C1 in distance)
            pen = np.zeros_like(dist)
            x = np.clip((lim[hit] - dist[hit]) / (lim[hit] - rr[hit]), 0, 1)
            pen[hit] = (x * x * (3 - 2 * x)) * (lim[hit] - dist[hit])
            dirn = d / np.maximum(dist, 1e-9)[:, None]
            push = dirn * pen[:, None]
            wi, wj = wgt[I], wgt[J]; ws = wi + wj
            corr = np.zeros((n, 3)); cnt = np.zeros(n)
            np.add.at(corr, I, -push * (wi / ws)[:, None]); np.add.at(corr, J, push * (wj / ws)[:, None])
            np.add.at(cnt, I, hit.astype(float)); np.add.at(cnt, J, hit.astype(float))
            corr /= np.maximum(cnt, 1)[:, None]
            # spatial blur along the chain so a correction is a smooth bump, never a kink
            for _b in range(self.blur):
                c2 = corr.copy(); c2[1:-1] = 0.25 * corr[:-2] + 0.5 * corr[1:-1] + 0.25 * corr[2:]; corr = c2
            Q = Q + corr
        return Q - P

    def step(self, P, radii, dt):
        tgt = self.target(P, radii)
        k = min(1.0, dt * self.rate)
        self.delta += (tgt - self.delta) * k
        return P + self.delta

def min_sep(P, radii, excl):
    n = len(P)
    s = np.arange(n) * np.linalg.norm(np.diff(P, axis=0), axis=1).mean()
    D = np.linalg.norm(P[:, None] - P[None], axis=2)
    rr = radii[:, None] + radii[None]
    far = np.abs(s[:, None] - s[None]) > excl
    return (np.where(far, D / rr, 9)).min()

# ---------------- placement: rod-space shape, positional-space placement ----------------

def place(P, target, ground=None):
    """Rigidly move P (the rod-space blend) so its centroid and yaw match `target` (the positional lerp of the two
    poses): translation + the closed-form best yaw about the vertical axis. Then sit it on `ground` if given."""
    c0, c1 = P.mean(0), target.mean(0)
    A = P - c0; B = target - c1
    # best rotation about y: maximise sum of (A rotated) . B in the xz plane
    num = (A[:, 2] * B[:, 0] - A[:, 0] * B[:, 2]).sum(); den = (A[:, 0] * B[:, 0] + A[:, 2] * B[:, 2]).sum()
    a = np.arctan2(num, den)
    c, s = np.cos(a), np.sin(a)
    Rm = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    Q = A @ Rm.T + c1
    if ground is not None:
        Q[:, 1] += ground - Q[:, 1].max()
    return Q
