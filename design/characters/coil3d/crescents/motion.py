"""Motion measurements from a COIL_DUMP (t + 64 points per frame at 60 fps): per-frame peak point speed, peak
acceleration (jerkiness), the tightest bend (R·k), the self-clearance, and where they spike along the 60 s timeline."""
import sys, numpy as np
from coilpaint import load_dump, R, SEG, N

def stats(path, label=''):
    T, Wd = load_dump(path)
    n = len(T); dt = 1 / 60
    V = np.diff(Wd, axis=0) / dt                     # pt/s per point
    speed = np.linalg.norm(V, axis=2)                # (n-1, 64)
    A = np.diff(V, axis=0) / dt
    acc = np.linalg.norm(A, axis=2)                  # (n-2, 64)
    # bend: joint turn angles -> R*k = theta / seg * R
    d = np.diff(Wd, axis=1); d /= np.linalg.norm(d, axis=2, keepdims=True)
    th = np.arccos(np.clip((d[:, :-1] * d[:, 1:]).sum(2), -1, 1))
    rk = th.max(1) / SEG * R
    # clearance: min distance between non-adjacent points / 2R
    idx = np.arange(N); far = np.abs(idx[:, None] - idx[None]) > int(np.ceil(4.5 * R / SEG))
    clear = np.empty(n)
    for f in range(n):
        D = np.linalg.norm(Wd[f][:, None] - Wd[f][None], axis=2)
        clear[f] = D[far].min() / (2 * R)
    print('%s frames %d' % (label, n))
    print('  speed  (pt/s, max over points): p50 %.0f p90 %.0f p99 %.0f max %.0f' % tuple(np.percentile(speed.max(1), [50, 90, 99, 100])))
    print('  accel  (pt/s², max over points): p50 %.0f p90 %.0f p99 %.0f max %.0f' % tuple(np.percentile(acc.max(1), [50, 90, 99, 100])))
    print('  R·k    (tightest bend): p50 %.2f p90 %.2f p99 %.2f max %.2f' % tuple(np.percentile(rk, [50, 90, 99, 100])))
    print('  clear  (min gap / 2R): p50 %.2f p10 %.2f p1 %.2f min %.2f' % tuple(np.percentile(clear, [50, 10, 1, 0])))
    return T, speed.max(1), acc.max(1), rk, clear

def timeline(T, sp, ac, rk, cl, events=None):
    print('  per second: peak speed / peak accel / max R·k / min clearance')
    for s in range(int(T[-1])):
        a = s * 60; b = min(len(ac), a + 60)
        print('  %2ds  %5.0f  %6.0f  %.2f  %.2f' % (s, sp[a:min(len(sp), a + 60)].max(), ac[a:b].max(), rk[a:a + 60].max(), cl[a:a + 60].min()))

if __name__ == '__main__':
    r = stats(sys.argv[1], sys.argv[1])
    if len(sys.argv) > 2 and sys.argv[2] == 'timeline': timeline(*r)
