"""A renderer that only does what SwiftUI Canvas can do: ~200 slices, each ONE fill of (quad + disc at its far vertex)
with ONE linear gradient of 8 stops across the width, drawn back to front (painter's sort by depth). No per-pixel
lighting: the stops are computed from the lighting model at the slice's real 3D normals. Options: perspective, depth
cue, proximity AO (per stop, against the coarse chain), contact shadow at crossings (per stop), head swell, eyes on the
dome, drawn at the head's depth."""
import numpy as np
from PIL import Image, ImageDraw
import tube3d as T
from render3d import shade_n

R = T.R
W, H = 198, 242
CENTER = (99.0, 138.0)

def unit(v): return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)

def radius_profile(u, swell=1.0, start=0.86):
    """Uniform R, then a smooth swell to swell*R at the tip (a club end, still a tube that only bends)."""
    x = np.clip((u - start) / (1 - start), 0, 1)
    return R * (1 + (swell - 1) * (x * x * (3 - 2 * x)))

def contact_cue(pt2, ptz, near, sarc, width=9.0, strength=0.65, dz=1.2 * R, excl=3.5 * R):
    """Darkening at a far surface point from nearer slices (not its own run) whose projected capsule rim is within
    `width` pt of the point."""
    A, B, Z, Rr, Sarc = near
    sel = (Z > ptz + dz) & (np.abs(Sarc - sarc) > excl)
    if not sel.any(): return 0.0
    a, b, rr = A[sel], B[sel], Rr[sel]
    ab = b - a; l2 = np.maximum((ab * ab).sum(1), 1e-9)
    tt = np.clip(((pt2 - a) * ab).sum(1) / l2, 0, 1)
    q = a + ab * tt[:, None]; d = np.linalg.norm(pt2 - q, axis=1) - rr
    x = np.clip(1 - d / width, 0, 1)
    occ = 1 - np.prod(1 - strength * x * x * (3 - 2 * x))
    return occ

def render(P, yaw=0.0, S=3, perspective=0.0, depth_cue=0.0, contact=True, ao=True, swell=1.0, eyes=True,
           stops=8, nslices=200, label='', eye_dir=None, yaw_pivot=None, fog_color=(0.02, 0.02, 0.04), spec=0.0, spec_pow=10.0, rim=0.0):
    """P: (n,3) centreline in pt (y down, z toward you), about the origin. perspective: 1/f (0 = orthographic).
    Returns a PIL image (W*2 x H*2)."""
    c, s = np.cos(yaw), np.sin(yaw)
    piv = np.zeros(3) if yaw_pivot is None else np.asarray(yaw_pivot)
    P = (P - piv) @ np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]).T + piv
    n = len(P); u = np.linspace(0, 1, n)
    ua = np.clip(u * T.L / 373.0, 0, 1)
    rad = radius_profile(u, swell)
    # slices: every k-th centreline sample
    k = max(1, n // nslices)
    idx = np.arange(0, n - 1, k); idx = np.append(idx, n - 1) if idx[-1] != n - 1 else idx
    # perspective projection: screen = xy * f/(f - z); the camera at z = f looking toward -z... z toward you, so near = larger
    def proj(p):
        if perspective <= 0: return p[..., :2].copy(), np.ones(p.shape[:-1])
        sc = 1.0 / (1.0 - p[..., 2] * perspective)
        return p[..., :2] * sc[..., None], sc
    Pp, Ps = proj(P)
    zmid = 0.5 * (P[idx[:-1], 2] + P[idx[1:], 2])
    # tangents in 3D (central difference over the slice span)
    tang = unit(P[np.minimum(idx + k, n - 1)] - P[np.maximum(idx - k, 0)])
    order = np.argsort(zmid, kind='stable')             # far first
    img = np.zeros((H * S, W * S, 3), float)
    cov = np.zeros((H * S, W * S), float)
    yy, xx = np.mgrid[0:H * S, 0:W * S]
    X = (xx + 0.5) / S - CENTER[0]; Y = (yy + 0.5) / S - CENTER[1]
    # coarse chain for AO: 64 nodes
    ci = np.linspace(0, n - 1, 64).astype(int); C = P[ci]; Cs = np.arange(64) * (T.L / 63)
    # near-slice table for contact shadows: screen segments with their depth and screen radius
    segA = Pp[idx[:-1]]; segB = Pp[idx[1:]]
    segR = 0.5 * (rad[idx[:-1]] * Ps[idx[:-1]] + rad[idx[1:]] * Ps[idx[1:]])
    sarc_all = 0.5 * (idx[:-1] + idx[1:]) / (n - 1) * T.L
    near = (segA, segB, zmid, segR, sarc_all)
    head_z = P[-1, 2]
    drew_eyes = False
    v = np.array([0, 0, 1.0])
    for q in order:
        i0, i1 = idx[q], idx[q + 1]
        a3, b3 = P[i0], P[i1]
        a2, b2 = Pp[i0], Pp[i1]
        ra, rb = rad[i0] * Ps[i0], rad[i1] * Ps[i1]
        t3 = tang[q]
        # frame: n in-screen perpendicular to the projected tangent; b = n x t (toward the viewer within the cross-section)
        tin = np.array([t3[0], t3[1], 0.0]); lin = np.linalg.norm(tin)
        if lin < 0.05:
            # pointing at the camera: use the previous slice's frame if any (continuity), else x
            nrm = np.array([0.0, -1.0, 0.0]) if q == 0 else prev_n
        else:
            nrm = np.array([t3[1], -t3[0], 0.0]) / lin
        prev_n = nrm
        bvec = np.cross(nrm, t3); bvec = unit(bvec)
        if bvec[2] < 0: bvec = -bvec; nrm = -nrm
        n2 = nrm[:2]
        # geometry of this slice in screen space: quad + disc at b (and at a for the first slice)
        d2 = b2 - a2; l2 = np.linalg.norm(d2)
        ext = (d2 / l2 * 0.35) if l2 > 1e-6 else np.zeros(2)
        quad = np.array([a2 + n2 * ra - ext, b2 + n2 * rb + ext, b2 - n2 * rb + ext, a2 - n2 * ra - ext])
        # bounding box
        lo = np.floor((np.minimum(quad.min(0), np.minimum(a2 - ra, b2 - rb)) + np.array(CENTER) - 1) * S).astype(int)
        hi = np.ceil((np.maximum(quad.max(0), np.maximum(a2 + ra, b2 + rb)) + np.array(CENTER) + 1) * S).astype(int)
        x0, y0 = max(0, lo[0]), max(0, lo[1]); x1, y1 = min(W * S, hi[0]), min(H * S, hi[1])
        if x1 <= x0 or y1 <= y0: continue
        px = X[y0:y1, x0:x1]; py = Y[y0:y1, x0:x1]
        # mask: quad (convex) OR disc(b) OR (disc(a) if first)
        m = np.ones(px.shape, bool)
        for e in range(4):
            p0, p1 = quad[e], quad[(e + 1) % 4]
            m &= ((p1[0] - p0[0]) * (py - p0[1]) - (p1[1] - p0[1]) * (px - p0[0])) <= 0
        if l2 <= 1e-6: m[:] = False
        m |= (px - b2[0]) ** 2 + (py - b2[1]) ** 2 <= rb * rb
        if q == 0 or (q > 0 and order.tolist().index(q) == 0 and False): pass
        if i0 == 0: m |= (px - a2[0]) ** 2 + (py - a2[1]) ** 2 <= ra * ra
        if not m.any(): continue
        # gradient parameter across the width: s in [-1, 1] along n2 about the slice mid
        mid = 0.5 * (a2 + b2); rm = 0.5 * (ra + rb)
        sgrad = ((px - mid[0]) * n2[0] + (py - mid[1]) * n2[1]) / rm
        # stops
        ss = np.linspace(-1, 1, stops)
        Ns = ss[:, None] * nrm[None] + np.sqrt(1 - ss * ss)[:, None] * bvec[None]
        umid = 0.5 * (ua[i0] + ua[i1])
        cols = shade_n(np.full(stops, umid), Ns)
        if spec > 0:
            Hd = unit(np.array([-0.45, -0.62, 0.65]))
            lobe = np.clip(Ns @ Hd, 0, 1) ** spec_pow
            cols = cols + spec * lobe[:, None] * np.array([1.0, 0.97, 0.92])
        if rim > 0:
            cols = cols * (1 - rim * (1 - Ns[:, 2]) ** 2)[:, None]
        if ao:
            # proximity AO at the stop's surface point against the coarse chain (same model as render3d, soft-combined)
            pm = 0.5 * (a3 + b3); rr3 = 0.5 * (rad[i0] + rad[i1])
            surf = pm[None] + Ns * rr3
            sarc = 0.5 * (i0 + i1) / (n - 1) * T.L
            far = np.abs(Cs - sarc) > 3.5 * R
            Q = C[far]
            if len(Q):
                D = Q[None] - surf[:, None]; dd = np.linalg.norm(D, axis=2)
                nd = (D * Ns[:, None]).sum(2) / np.maximum(dd, 1e-6)
                occ_i = np.clip(nd, 0, 1) * np.clip(1 - (dd - R) / (1.8 * R), 0, 1) ** 2
                occ = 1 - np.prod(1 - occ_i, axis=1)
                shade_a = np.clip(occ, 0, 1)
            else:
                shade_a = np.zeros(stops)
        else:
            shade_a = np.zeros(stops)
        if contact:
            # contact shadow from nearer slices at each stop's screen point, combined with the AO as one occlusion
            for j in range(stops):
                sp = mid + n2 * (ss[j] * rm)
                cc = contact_cue(sp, zmid[q], near, sarc_all[q])
                if cc > 0: shade_a[j] = 1 - (1 - shade_a[j]) * (1 - cc)
        # hue-preserving shadow: toward a deep magenta-purple (the reference's creases), never below 45% brightness
        tint = np.array([0.42, 0.22, 0.48])
        fac = 1 - np.clip(shade_a, 0, 0.85)[:, None] * (1 - tint)
        cols = cols * fac
        if depth_cue > 0:
            zc = zmid[q] / 60.0   # about -1..1
            f = np.clip(1 - depth_cue * (0.5 - 0.5 * zc), 0, 1)
            cols = cols * f + np.array(fog_color) * (1 - f) * 0.0
        # rasterise the gradient (what Canvas does): clamp s and interpolate the stops
        sc_ = np.clip(sgrad, -1, 1); f_ = (sc_ + 1) / 2 * (stops - 1); k0 = np.minimum(stops - 2, f_.astype(int)); w_ = f_ - k0
        col = cols[k0] * (1 - w_)[..., None] + cols[k0 + 1] * w_[..., None]
        sub = img[y0:y1, x0:x1]; sub[m] = col[m]; cov[y0:y1, x0:x1][m] = 1
        # the eyes: drawn right after the head's slices in the sort (a pseudo-slice at the head's front depth)
        if eyes and not drew_eyes and i1 == n - 1:
            drew_eyes = True
            img = draw_eyes(img, P, Pp, Ps, rad, tang[-1], S, eye_dir)
    # if the head slice was not last in the order, the eyes were drawn when it was; parts nearer were drawn after
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((W * 2, H * 2), Image.LANCZOS)
    if label: ImageDraw.Draw(im).text((8, 8), label, fill=(255, 255, 255))
    return im

def draw_eyes(img, P, Pp, Ps, rad, t_end, S, eye_dir=None):
    """Two cream eyes on the head's dome: placed on the sphere of the end cap, foreshortened by the local normal."""
    n = len(P)
    hc3 = P[-1]; rh = rad[-1]
    # the face direction: mostly toward the viewer, tilted along the end tangent and a little up
    fd = unit(np.array([0, 0, 1.0]) * 0.8 + t_end * 0.45 + np.array([0, -0.25, 0])) if eye_dir is None else unit(np.asarray(eye_dir))
    # eye basis on the dome
    up = np.array([0, -1.0, 0]); right = unit(np.cross(up, fd)); up2 = unit(np.cross(fd, right))
    sep, lift = 0.42, 0.10
    cream = np.array([0.99, 0.915, 0.83])
    yy, xx = np.mgrid[0:img.shape[0], 0:img.shape[1]]
    X = (xx + 0.5) / S - CENTER[0]; Y = (yy + 0.5) / S - CENTER[1]
    for side in (-1, 1):
        dirn = unit(fd + right * (side * sep) + up2 * lift)
        if dirn[2] < 0.12: continue      # facing away: hidden
        p3 = hc3 + dirn * rh * 1.0
        sc = 1.0 / (1.0 - p3[2] * 0.0) if True else 1
        p2 = p3[:2]; # orthographic placement is fine for the eyes relative to the projected head
        # projected head centre and scale
        hs = Ps[-1]; hc2 = Pp[-1]
        p2 = hc2 + (p3[:2] - hc3[:2]) * hs
        rx, ry = 3.4 * hs * (rh / R) ** 0.6, 4.6 * hs * (rh / R) ** 0.6
        # foreshorten along the direction the eye normal tilts in screen
        fz = max(0.25, dirn[2])
        tilt = dirn[:2]; tl = np.linalg.norm(tilt)
        if tl > 1e-6:
            ex, ey = tilt / tl
        else:
            ex, ey = 1.0, 0.0
        # ellipse: axis along tilt scaled by fz
        dx = X - p2[0]; dy = Y - p2[1]
        a_ = (dx * ex + dy * ey) / fz; b_ = (-dx * ey + dy * ex)
        # map to the eye's own ellipse (rx across, ry up): approximate by radial scale with the eye's aspect
        q = (a_ / rx) ** 2 + (b_ / ry) ** 2
        m = q <= 1
        soft = np.clip(1.6 - np.sqrt(np.maximum(q, 0)) * 1.0, 0, 1)
        img[m] = cream
    return img
