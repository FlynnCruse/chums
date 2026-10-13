"""Noodle's animation: every clip the Lab and the watch play.

Headless (recommended; renders in the background):
    Blender -b design/noodle/noodle.blend -P design/noodle/animate.py -- [clip ...] [--step N] [--out DIR] [--samples N]
From Blender's Python console:
    import sys; sys.argv = ['x', '--', 'idle']; exec(open('design/noodle/animate.py').read())

Each clip is keyed acting: a list of poses at times (seconds) with an ease per segment, on top of which run
  breathing, blinks, a hair spring that lags behind the head (follow-through on every move), and a hair
  "jiggle" spring on vertical moves. 24 fps, rendered at the watch's 396 x 484 at 128 samples.
Each state is a pool: a calm rest loop and several beats that start and end on the same rest pose, held at both ends
  so the hair settles. The player chains them at random, so a long state never repeats visibly.
Writes renders/anim/<clip>_NNN.png and renders/clips.json: per frame, where the hair top, the face and the glass
  contact are on the watch screen (198 x 242 pt), plus named events (a card lands, a knock, the apex of a jump),
  so the Lab can put UI on its head, fog the glass where it presses, and land tool calls on it in sync.
Then: tools/noodle-watch.sh makes the watch's clips from them.
"""
import bpy, math, json, os, sys, time
from bpy_extras.object_utils import world_to_camera_view

FPS = 24
D = bpy.data
sc = bpy.context.scene
sc.camera = D.objects['Cam']

# headless Blender doesn't always pick up the GPU from preferences: ask for Metal (or CUDA/OptiX) explicitly
try:
    cp = bpy.context.preferences.addons['cycles'].preferences
    for kind in ('METAL', 'OPTIX', 'CUDA', 'HIP'):
        try:
            cp.compute_device_type = kind; cp.get_devices()
            if any(d.type != 'CPU' for d in cp.devices): break
        except TypeError: continue
    for d in cp.devices: d.use = d.type != 'CPU'
    sc.cycles.device = 'GPU'
    print('cycles devices:', [(d.name, d.use) for d in cp.devices], flush=True)
except Exception as e:
    print('GPU setup failed, rendering on CPU:', e, flush=True)

# ---------- the rig (noodle_rig.py, stored in the .blend) ----------
G = {'__name__': 'noodle_rig'}
exec(compile(D.texts['noodle_rig.py'].as_string(), 'noodle_rig.py', 'exec'), G)
pose, shot = G['pose'], G['shot']
arm = D.objects['Rig']
HELPERS = [D.objects[f'Helper{i}'] for i in range(3)]
CORES = [D.objects.get(f'CoreH{i}') for i in range(3)]
for o in HELPERS + CORES:
    if o and 'base_z' not in o: o['base_z'] = o.location.z
HELP_ROT = [o.rotation_euler.z for o in HELPERS]

# ---------- channels ----------
V3 = ['base', 'mid', 'neck', 'head', 'hairtilt']
V2 = ['lidsL', 'lidsR', 'gazeL', 'gazeR']
V1 = ['stretch', 'rise', 'turn', 'toward', 'pupilL', 'pupilR', 'poof', 'shiftx', 'h0', 'h1', 'h2']
NEUTRAL = dict(base=(0, 0, 0), mid=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), hairtilt=(0, 0, 0), lidsL=(-10, 80), lidsR=(-6, 80),
               gazeL=(6, -4), gazeR=(6, -4), stretch=1.0, rise=0.0, turn=0.0, toward=0.0, pupilL=19, pupilR=19, poof=1.0, shiftx=0.0,
               h0=-3.0, h1=-3.0, h2=-3.0)
CLOSED = (14, 6)


def expand(d):
    """shorthands: lids, gaze, pupil set both sides."""
    d = dict(d)
    if 'lids' in d: v = d.pop('lids'); d.setdefault('lidsL', v); d.setdefault('lidsR', v)
    if 'gaze' in d: v = d.pop('gaze'); d.setdefault('gazeL', v); d.setdefault('gazeR', v)
    if 'pupil' in d: v = d.pop('pupil'); d.setdefault('pupilL', v); d.setdefault('pupilR', v)
    return d


# ---------- poses the clips are built from ----------
DEAD = expand(dict(mid=(2, -3, 0), neck=(3, -2, 0), head=(0, 0, 0), lidsL=(-10, 80), lidsR=(-6, 80), gaze=(6, -4), pupil=19))
LISTEN = expand(dict(mid=(6, 0, 0), neck=(8, 0, 0), head=(4, 0, 0), stretch=1.1, toward=.8, lids=(-85, 85), gaze=(0, 0), pupil=24, poof=1.06))
THINK = expand(dict(mid=(0, 8, 0), neck=(-4, 12, 0), head=(-6, 10, 0), lidsL=(-55, 80), lidsR=(-2, 80), gaze=(22, 24), pupil=17))
# working sits lower, so the tool calls that land on its head stay clear of the watch's clock and status row
WORK = expand(dict(rise=-.55, mid=(6, 0, 0), neck=(10, 0, 0), head=(8, 0, 0), lids=(-22, 40), gaze=(-8, -26), pupil=17))
RUN = expand(dict(rise=-.55, mid=(4, 0, 0), neck=(6, 0, 0), head=(4, 0, 0), toward=.5, lids=(-60, 70), gaze=(0, -24), pupil=16))
SEARCH = expand(dict(rise=-.55, mid=(2, 0, 0), neck=(4, 0, 0), head=(0, 0, 0), lids=(-50, 75), gaze=(0, -6), pupil=18))
SPEAK = expand(dict(mid=(0, -4, 0), neck=(-2, -4, 0), head=(0, 6, 0), stretch=.98, toward=.3, lidsL=(-34, 80), lidsR=(-30, 80), gaze=(0, 2), pupil=21))
DONE = expand(dict(stretch=1.16, mid=(-4, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), lids=(-80, 22), gaze=(0, 10), poof=1.18))
NEEDS = expand(dict(toward=3.0, rise=-1.0, mid=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), lids=(-88, 88), gaze=(0, 4), pupil=7))
APPR = expand(dict(rise=-1.25, mid=(-2, 0, 0), neck=(-4, 0, 0), head=(-6, 0, 0), lids=(-80, 85), gaze=(0, 34), pupil=18))
BLOCK = expand(dict(mid=(8, 0, 6), neck=(12, 6, 6), head=(6, 8, 0), lidsL=(6, 80), lidsR=(12, 80), gazeL=(4, -34), gazeR=(0, -34), poof=.95))
SQUASH = expand(dict(stretch=.74, rise=-.12, poof=.82, mid=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), lids=(-88, 88), gaze=(0, 0), pupil=9))
WAIT = expand(dict(mid=(2, -3, 0), neck=(3, -2, 0), head=(0, 0, 0), lids=(0, 70), gaze=(4, -6), pupil=18))
SLEEP = expand(dict(rise=-2.7, mid=(4, 0, 0), neck=(4, 0, 0), lids=CLOSED, pupil=19))
SUBS = expand(dict(shiftx=.25, toward=-.8, rise=.15, mid=(2, -3, 0), neck=(3, -2, 0), lids=(-20, 72), gaze=(-26, -10), pupil=19))


# ---------- easing ----------
def ease(name, k):
    k = max(0.0, min(1.0, k))
    if name == 'lin': return k
    if name == 'in': return k * k
    if name == 'in3': return k * k * k
    if name == 'out': return 1 - (1 - k) ** 2
    if name == 'snap': return 1 - (1 - k) ** 4                      # saccades and flinches
    if name == 'back': c = 1.9; return 1 + (c + 1) * (k - 1) ** 3 + c * (k - 1) ** 2   # overshoot, then settle
    if name == 'hold': return 0.0 if k < 1 else 1.0
    return k * k * k * (k * (6 * k - 15) + 10)                      # 'io': minimum-jerk in-out


class K:
    """A key: a pose at time t, reached with an ease. base= fills every channel (so the key is a full pose);
    without base, only the channels given are keyed. K(t) alone holds every channel at its last value."""
    def __init__(self, t, ease='io', base=None, **pose):
        self.t, self.ease = t, ease
        full = {k: v for k, v in NEUTRAL.items() if k not in ('h0', 'h1', 'h2')} if base is not None else {}
        full.update(base or {}); full.update(expand(pose))
        self.pose, self.hold = full, base is None and not pose


class Clip:
    """keys: list of K, interpolated per channel (like animation curves).
    role: 'rest' (a calm loop), 'beat' (a one-shot that starts and ends on the state's rest pose), 'enter', 'react',
      'once', 'scrub'. The player chains rest and beats at random, so a long state never visibly repeats.
    breath: (amplitude, period), sway: (roll, turn, period); periods are fitted to divide the duration, so every
      segment of a state starts and ends at the same phase. blinks: times. events: name -> time or [times].
    scrub: render n frames from a parameter 0..1 (fn(k) -> pose)."""
    def __init__(self, name, dur, keys=None, loop=False, breath=(.012, 4.0), blinks=(), events=None, sway=None,
                 helpers=False, scrub=None, n=None, hair=1.0, extra=None, role='once', state=None):
        self.name, self.dur, self.loop, self.blinks = name, dur, loop, list(blinks)
        fit = lambda per: dur / max(1, round(dur / per)) if dur else per
        self.breath = (breath[0], fit(breath[1])) if breath and breath[0] else (0, 1)
        self.sway = (sway[0], sway[1], fit(sway[2])) if sway else None
        self.events, self.helpers, self.scrub, self.hair, self.extra = events or {}, helpers, scrub, hair, extra
        self.role, self.state = role, state
        self.n = n if n else max(1, round(dur * FPS))
        self.chan = {c: [] for c in NEUTRAL}
        for k in sorted(keys or [], key=lambda k: k.t):
            if k.hold:
                for c, ks in self.chan.items():
                    if ks: ks.append((k.t, ks[-1][1], 'io'))
            else:
                for c, v in k.pose.items(): self.chan[c].append((k.t, v, k.ease))

    def primary(self, t):
        out = {}
        for c, ks in self.chan.items():
            if not ks: out[c] = NEUTRAL[c]; continue
            if t <= ks[0][0]: out[c] = ks[0][1]; continue
            if t >= ks[-1][0]: out[c] = ks[-1][1]; continue
            for (t0, a, _), (t1, b, e) in zip(ks, ks[1:]):
                if t0 <= t <= t1:
                    k = ease(e, (t - t0) / (t1 - t0) if t1 > t0 else 1)
                    out[c] = tuple(x + (y - x) * k for x, y in zip(a, b)) if isinstance(a, tuple) else a + (b - a) * k
                    break
        return out


def blink_amount(t, times):
    a = 0.0
    for b in times:
        d = t - b
        if 0 <= d < .05: a = max(a, d / .05)
        elif .05 <= d < .09: a = 1.0
        elif .09 <= d < .2: a = max(a, 1 - (d - .09) / .11)
    return a


def overlay(clip, t, p):
    p = dict(p)
    amp, per = clip.breath
    if amp:
        w = math.sin(2 * math.pi * t / per)
        p['stretch'] *= 1 + amp * w
        p['poof'] *= 1 + amp * .6 * math.sin(2 * math.pi * t / per)
    if clip.sway:
        roll, turn, per2 = clip.sway
        s = math.sin(2 * math.pi * t / per2)
        p['mid'] = (p['mid'][0], p['mid'][1] + roll * s, p['mid'][2])
        p['turn'] += turn * .5 * math.sin(4 * math.pi * t / per2)
    b = blink_amount(t, clip.blinks)
    if b:
        for side in ('lidsL', 'lidsR'):
            u, l = p[side]
            p[side] = (u + (CLOSED[0] - u) * b, l + (CLOSED[1] - l) * b)
    if clip.extra: p = clip.extra(t, p)
    return p


# ---------- secondary motion: the hair lags behind the head, and jiggles on vertical moves ----------
def head_signal(p):
    pitch = p['mid'][0] + p['neck'][0] + p['head'][0]
    roll = p['mid'][1] + p['neck'][1] + p['head'][1]
    yaw = p['turn'] + p['mid'][2] + p['neck'][2] + p['head'][2]
    vert = p['rise'] * 1.0 + (p['stretch'] - 1) * 3.2
    return [pitch, roll, yaw, vert]


def springs(clip, poses):
    """poses: primary+overlay pose per frame. Returns the same poses with hair follow-through added."""
    n = len(poses)
    if n < 2 or clip.scrub: return poses
    sig = [head_signal(p) for p in poses]
    W = [11.0, 11.0, 9.0, 13.0]; Z = [.32, .32, .4, .28]          # ω, ζ per axis: bouncy hair
    x = list(sig[0]); v = [0.0] * 4
    sub = 8; dt = 1 / FPS / sub
    passes = 3 if clip.loop else 1
    out = None
    for ps in range(passes):
        rec = []
        for i in range(n):
            j = (i + 1) % n if clip.loop else min(i + 1, n - 1)
            for s in range(sub):
                k = s / sub
                tgt = [a + (b - a) * k for a, b in zip(sig[i], sig[j])]
                for a in range(4):
                    v[a] += (W[a] ** 2 * (tgt[a] - x[a]) - 2 * Z[a] * W[a] * v[a]) * dt
                    x[a] += v[a] * dt
            rec.append(list(x))
        out = rec
    res = []
    g = clip.hair
    for i, p in enumerate(poses):
        lag = [h - s for h, s in zip(out[i], sig[i])]
        q = dict(p)
        ht = q['hairtilt']
        q['hairtilt'] = (ht[0] + lag[0] * 1.3 * g + lag[3] * -6 * g, ht[1] + lag[1] * 1.3 * g, ht[2] + lag[2] * .9 * g)
        q['poof'] = q['poof'] * (1 + max(-.12, min(.12, lag[3] * .35 * g)))
        res.append(q)
    return res


# ---------- applying a pose, and where things land on screen ----------
def apply(p, helpers):
    pose(base=p['base'], mid=p['mid'], neck=p['neck'], head=p['head'], stretch=p['stretch'], rise=p['rise'], turn=p['turn'],
         toward=p['toward'], lidsL=p['lidsL'], lidsR=p['lidsR'], gazeL=p['gazeL'], gazeR=p['gazeR'],
         pupilL=p['pupilL'], pupilR=p['pupilR'], poof=p['poof'], hairtilt=p['hairtilt'])
    arm.location.x += p['shiftx']
    for i, (h, c) in enumerate(zip(HELPERS, CORES)):
        z = p[f'h{i}']
        vis = helpers and z > -2.9
        h.hide_render = not vis; h.location.z = h['base_z'] + z
        h.rotation_euler.z = HELP_ROT[i] + p.get(f'r{i}', 0)
        if c: c.hide_render = not vis; c.location.z = c['base_z'] + z
    bpy.context.view_layer.update()


def scr(co):
    v = world_to_camera_view(sc, sc.camera, co)
    return round(v.x * 198, 1), round((1 - v.y) * 242, 1)


def anchors(p):
    dg = bpy.context.evaluated_depsgraph_get()
    hc = D.objects['HairCloud'].evaluated_get(dg)
    me = hc.to_mesh(); mw = hc.matrix_world
    pts = [scr(mw @ v.co) for v in me.vertices]
    hc.to_mesh_clear()
    ymin = min(y for _, y in pts)
    xs = [x for x, y in pts if y < ymin + 4]
    hx, hy = sum(xs) / len(xs), ymin - 4                         # the fur reaches about 4 pt past the cloud
    (lx, ly), (rx, ry) = scr(D.objects['EyeL'].matrix_world.translation), scr(D.objects['EyeR'].matrix_world.translation)
    roll = math.degrees(math.atan2(ly - ry, lx - rx))
    return [round(hx, 1), round(hy, 1), round((lx + rx) / 2, 1), round((ly + ry) / 2, 1), round(roll, 1),
            round(p['toward'] / 3, 2), round(p['rise'], 2)]


# ---------- the clips ----------
LISTEN = expand(dict(mid=(4, 0, 0), neck=(7, 0, 0), head=(4, 0, 0), stretch=1.05, toward=.25, lids=(-82, 85), gaze=(0, 0), pupil=23, poof=1.04))
SPEAK = expand(dict(mid=(0, -4, 0), neck=(-2, -4, 0), head=(0, 6, 0), stretch=.99, toward=.1, lidsL=(-34, 80), lidsR=(-30, 80), gaze=(0, 2), pupil=21))
# working sits lower, so the tool calls that land on its head stay clear of the watch's clock and status row
WORK = expand(dict(rise=-.45, mid=(6, 0, 0), neck=(10, 0, 0), head=(8, 0, 0), lids=(-22, 40), gaze=(-8, -26), pupil=17))
NEEDS = expand(dict(toward=3.2, rise=-1.0, mid=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), lids=(-88, 88), gaze=(0, 4), pupil=7))

# how much each state breathes, and how often it plays a beat instead of its rest loop (the player reads this)
BREATH = dict(idle=.016, listening=.012, thinking=.012, working=.008, subagents=.01, speaking=0, done=.012, needs=.006,
              approval=.01, blocked=.012, compacting=0, waiting=.012, sleep=.03)
BEAT_CHANCE = dict(idle=.45, listening=.5, thinking=.6, working=.35, subagents=.45, speaking=.85, done=.5, needs=.35,
                   approval=.3, blocked=.35, waiting=.4, sleep=.15)


def build():
    C = {}
    def add(c): C[c.name] = c

    def seg(name, state, role, dur, R, keys=(), hold_in=.4, hold_out=.6, **kw):
        """a rest loop or a beat: held on the rest pose R at both ends, so any segment can follow any other"""
        ks = [K(0, base=R), K(hold_in, base=R), *keys, K(dur - hold_out, base=R), K(dur, base=R)]
        kw.setdefault('breath', (BREATH.get(state, .012), 4.0))
        add(Clip(name, dur, ks, loop=(role == 'rest'), role=role, state=state, **kw))

    def enter(name, state, dur, keys, **kw):
        kw.setdefault('breath', (0, 1))
        add(Clip(name, dur, keys, role='enter', state=state, **kw))

    # ======================= idle =======================
    seg('idle_rest', 'idle', 'rest', 6.0, DEAD, [
        K(1.3, gaze=(12, -6), neck=(3, -5, 0), head=(0, -3, 0)), K(2.6, gaze=(12, -6)), K(2.75, 'snap', gaze=(-14, -3)),
        K(4.0, gaze=(-14, -3), mid=(2, 1, 0), neck=(3, 3, 0), head=(0, 2, 0)), K(4.15, 'snap', gaze=(6, -4))],
        blinks=[.9, 3.4], sway=(2.5, 3, 6.0))
    seg('idle_look', 'idle', 'beat', 4.0, DEAD, [
        K(.55, 'snap', gaze=(-32, -2)), K(1.1, 'back', turn=-24, mid=(2, -8, 0), neck=(3, -8, 0), lids=(-50, 84), stretch=1.04),
        K(1.9, gaze=(-32, 0)), K(2.05, 'snap', gaze=(0, 0)), K(2.5, turn=-8, lidsL=(2, 78), lidsR=(6, 78), stretch=1.0, toward=.4), K(2.9)],
        blinks=[3.0])
    shake = [K(.55, stretch=.9, lids=(10, 40), mid=(2, 0, 0), neck=(3, 0, 0))]
    for i, a in enumerate([18, -18, 16, -15, 11, -7, 3, 0]):
        shake.append(K(.65 + i * .12, 'io', neck=(3, a, 0), head=(0, a * .8, 0), mid=(2, a * .5, 0), turn=a * .5, lids=(8, 30)))
    shake += [K(1.75, 'back', stretch=1.08, lids=(-62, 85), poof=1.12), K(2.3)]
    seg('idle_shake', 'idle', 'beat', 3.2, DEAD, shake, blinks=[2.4], hair=1.7)
    seg('idle_sideeye', 'idle', 'beat', 3.6, DEAD, [
        K(1.1, 'io', turn=16, mid=(2, 5, 0), neck=(3, 6, 0), gaze=(-24, -2), lidsL=(10, 66), lidsR=(14, 66)),
        K(2.2, turn=16, gaze=(-24, -2)), K(2.35, 'snap', gaze=(-26, -2)), K(2.7)], blinks=[1.85])
    seg('idle_yawn', 'idle', 'beat', 3.6, DEAD, [
        K(.85, stretch=.92, mid=(4, 0, 0)), K(1.55, stretch=1.24, rise=.18, lids=(10, 12), head=(-14, 0, 0), neck=(-6, 0, 0), gaze=(0, 20), poof=1.14),
        K(2.0), K(2.45, 'back', stretch=.95, rise=0, poof=.98, lids=(-4, 70), head=(2, 0, 0), neck=(4, 0, 0))], breath=(0, 1))
    seg('idle_hum', 'idle', 'beat', 3.6, DEAD, [
        K(.8, mid=(2, 8, 0), neck=(3, 7, 0), lids=(-30, 55), gaze=(0, 0)), K(1.3, mid=(2, -8, 0), neck=(3, -7, 0)),
        K(1.8, mid=(2, 8, 0), neck=(3, 7, 0)), K(2.3, mid=(2, -6, 0), neck=(3, -5, 0)), K(2.7, mid=(2, -3, 0), neck=(3, -2, 0))], hair=1.3)
    seg('idle_peek', 'idle', 'beat', 3.6, DEAD, [
        K(1.0, gaze=(0, -36), head=(12, 0, 0), neck=(10, 0, 0), lids=(-40, 70), toward=.3), K(1.9, gaze=(8, -36)),
        K(2.2, 'snap', gaze=(0, 0), lids=(-70, 82), head=(0, 0, 0), neck=(3, -2, 0), toward=0), K(2.8)])

    # ======================= listening: attentive, leaning a little toward you =======================
    enter('listening_in', 'listening', .8, [K(0, base=DEAD), K(.22, stretch=.92, mid=(4, 0, 0), lids=(0, 60)),
          K(.52, 'back', base=LISTEN, stretch=1.09, poof=1.08), K(.8, base=LISTEN)], hair=1.3)
    seg('listening_rest', 'listening', 'rest', 4.8, LISTEN, [
        K(1.5, neck=(11, 0, 0), head=(6, 0, 0)), K(2.1, neck=(7, 0, 0), head=(4, 0, 0)), K(2.8, gaze=(3, 1)), K(3.7, gaze=(0, 0))],
        blinks=[1.15, 3.95])
    seg('listen_nod', 'listening', 'beat', 2.4, LISTEN, [
        K(.75, 'out', neck=(17, 0, 0), head=(10, 0, 0), stretch=1.02), K(1.05, neck=(7, 0, 0), head=(4, 0, 0), stretch=1.05),
        K(1.35, 'out', neck=(15, 0, 0), head=(9, 0, 0)), K(1.7, neck=(7, 0, 0), head=(4, 0, 0))])
    seg('listen_tilt_l', 'listening', 'beat', 3.0, LISTEN, [
        K(1.0, mid=(4, -8, 0), neck=(7, -12, 0), head=(4, -10, 0), gaze=(-6, 4), pupil=26, lids=(-86, 86)), K(2.0)], blinks=[1.6])
    seg('listen_tilt_r', 'listening', 'beat', 3.0, LISTEN, [
        K(1.0, mid=(4, 8, 0), neck=(7, 12, 0), head=(4, 10, 0), gaze=(6, 4), pupil=26, lids=(-86, 86)), K(2.0)])
    seg('listen_lean', 'listening', 'beat', 3.2, LISTEN, [
        K(1.1, toward=.9, lids=(-40, 70), pupil=19, neck=(11, 0, 0)), K(2.2)], blinks=[1.7])
    seg('listen_oh', 'listening', 'beat', 2.6, LISTEN, [
        K(.65, 'snap', lids=(-88, 88), pupil=28, stretch=1.1, poof=1.12, head=(-4, 0, 0)), K(1.4)], hair=1.3)
    seg('listen_mhm', 'listening', 'beat', 2.8, LISTEN, [
        K(1.05, neck=(19, 0, 0), head=(12, 0, 0), lids=(-26, 58), stretch=1.0), K(1.6), K(2.0, neck=(7, 0, 0), head=(4, 0, 0), lids=(-82, 85))])
    seg('listen_blink', 'listening', 'beat', 1.6, LISTEN, [], blinks=[.55, .8])

    # ======================= thinking: most of the time; a lot of small, different acting =======================
    enter('thinking_in', 'thinking', 1.0, [K(0, base=DEAD), K(.45, gaze=(10, 18), lidsL=(-35, 80), mid=(0, 4, 0)), K(1.0, base=THINK)])
    seg('thinking_rest', 'thinking', 'rest', 5.0, THINK, [
        K(1.4, gaze=(14, 28)), K(2.4, gaze=(18, 21), head=(-6, 12, 0)), K(3.4, gaze=(25, 26), head=(-6, 10, 0)), K(4.0)], blinks=[2.9])
    seg('think_swap', 'thinking', 'beat', 3.8, THINK, [
        K(1.0, gaze=(-24, 26), mid=(0, -10, 0), neck=(-4, -14, 0), head=(-8, -10, 0), lidsL=(-2, 80), lidsR=(-55, 80)), K(2.4)], blinks=[1.9], hair=1.2)
    seg('think_squint', 'thinking', 'beat', 3.4, THINK, [
        K(.95, gaze=(0, -14), lids=(-24, 50), mid=(6, 0, 0), neck=(10, 0, 0), head=(8, 0, 0), toward=.35, stretch=.95), K(2.1),
        K(2.3, gaze=(4, -14))])
    seg('think_hm', 'thinking', 'beat', 2.8, THINK, [
        K(.75, stretch=.95), K(1.0, 'back', gaze=(22, 26), lidsR=(-82, 84), lidsL=(-35, 80), stretch=1.08, poof=1.07, head=(-10, 10, 0)), K(1.6)], hair=1.3)
    count = [K(.6, gaze=(18, 30))]
    for i, t in enumerate([.8, 1.15, 1.5, 1.85]):
        count += [K(t, 'out', neck=(-4 + 12, 12, 0), head=(-6 + 9, 10, 0), stretch=.98), K(t + .17, neck=(-4, 12, 0), head=(-6, 10, 0), stretch=1.0)]
    count += [K(2.4, gaze=(22, 24))]
    seg('think_count', 'thinking', 'beat', 3.4, THINK, count)
    seg('think_sigh', 'thinking', 'beat', 3.4, THINK, [
        K(1.15, stretch=1.08, poof=1.06, head=(-8, 10, 0), lids=(-40, 80)), K(2.05, stretch=.9, poof=.95, lids=(-8, 70), mid=(6, 6, 0), gaze=(10, 6)),
        K(2.5)], hair=1.2)
    roll = [K(.6, gaze=(-10, 30)), K(1.0, gaze=(-26, 14)), K(1.4, gaze=(-20, -10)), K(1.8, gaze=(0, -18)), K(2.2, gaze=(20, -8)), K(2.6, gaze=(26, 14))]
    seg('think_roll', 'thinking', 'beat', 3.6, THINK, roll + [K(2.75, lidsL=(-20, 80), lidsR=(-20, 80))])
    seg('think_down', 'thinking', 'beat', 3.4, THINK, [
        K(1.0, gaze=(0, -34), head=(12, 0, 0), neck=(10, 0, 0), mid=(4, 0, 0), lids=(-30, 60)), K(1.4, gaze=(10, -34)), K(1.8, gaze=(-8, -34)),
        K(2.3, gaze=(4, -34))])

    # ======================= working: a calm loop per kind of tool call, plus beats =======================
    enter('working_in', 'working', .8, [K(0, base=DEAD), K(.25, stretch=.92, lids=(-30, 50)), K(.8, 'back', base=WORK)], hair=1.2)
    read = []
    for i in range(3):
        t0 = .55 + i * 1.5
        read += [K(t0, 'snap', gaze=(-22, -18 - 4 * i), turn=-4), K(t0 + 1.25, 'lin', gaze=(20, -18 - 4 * i), turn=4, neck=(10 + i, 0, 0))]
    seg('work_read', 'working', 'rest', 6.0, WORK, read, blinks=[2.0, 3.45])
    edit = []
    for i, t in enumerate([.6, 1.0, 1.4, 1.8, 2.2, 3.3, 3.7, 4.1]):
        edit += [K(t, 'out', neck=(13, 0, 0), head=(10, 0, 0), stretch=.98), K(t + .2, neck=(10, 0, 0), head=(8, 0, 0), stretch=1.0)]
    edit += [K(2.5, gaze=(10, -24)), K(3.05, gaze=(-8, -26))]
    seg('work_edit', 'working', 'rest', 5.2, WORK, sorted(edit, key=lambda k: k.t), blinks=[2.75])
    run = [K(.5, gaze=(0, -10))]
    for i, t in enumerate([1.0, 1.9, 2.8]):
        run += [K(t, 'lin', gaze=(2, -26 - 2 * i)), K(t + .15, 'snap', gaze=(-2, -10 - 2 * i))]
    run += [K(3.6, toward=.6, lids=(-30, 55), neck=(13, 0, 0)), K(4.6, toward=.6), K(4.9, 'back', lids=(-70, 75), toward=0)]
    seg('work_run', 'working', 'rest', 6.0, WORK, run, blinks=[1.5])
    seg('work_search', 'working', 'rest', 6.0, WORK, [
        K(.6, 'snap', gaze=(-32, -8)), K(1.3, turn=-16, mid=(6, -6, 0)), K(2.4), K(2.6, 'snap', gaze=(32, -8)), K(3.3, turn=16, mid=(6, 6, 0)),
        K(4.3), K(4.5, 'snap', gaze=(-8, -26), turn=0, mid=(6, 0, 0))], blinks=[2.0])
    seg('work_nod', 'working', 'beat', 2.4, WORK, [
        K(.75, neck=(16, 0, 0), head=(12, 0, 0), lids=(-30, 60)), K(1.05, neck=(8, 0, 0), head=(6, 0, 0)), K(1.35, neck=(14, 0, 0)), K(1.7, lids=(-22, 40), neck=(10, 0, 0))])
    seg('work_squint', 'working', 'beat', 3.0, WORK, [K(1.0, toward=.8, lids=(-14, 34), neck=(14, 0, 0), gaze=(0, -24)), K(2.1)])
    seg('work_ponder', 'working', 'beat', 3.2, WORK, [
        K(.9, gaze=(20, 20), lidsR=(-60, 80), head=(-6, 8, 0), neck=(4, 6, 0)), K(1.8), K(2.1, 'snap', gaze=(-8, -26), lids=(-22, 40))])
    seg('work_blink', 'working', 'beat', 1.6, WORK, [], blinks=[.55, .8])
    add(Clip('bump', 1.0, [K(0, base=WORK), K(.18, base=WORK, gaze=(0, 24), lids=(-75, 75), neck=(4, 0, 0), head=(0, 0, 0)),
             K(.3, 'out', stretch=.86, rise=-.52, neck=(16, 0, 0), head=(8, 0, 0), lids=(6, 30), poof=.9),
             K(.45, 'out', stretch=1.12, rise=-.32, neck=(0, 0, 0), head=(-6, 0, 0), lids=(-75, 70), gaze=(14, 26), poof=1.08),
             K(.65, stretch=.98, rise=-.45), K(1.0, base=WORK)], breath=(0, 1), events={'land': .24, 'launch': .42}, hair=1.4, role='react', state='working'))
    add(Clip('oops', 1.1, [K(0, base=WORK), K(.12, 'snap', stretch=.86, lids=(10, 30), neck=(18, 0, 0), mid=(6, -10, 0), turn=-10),
             K(.4, lids=(-75, 80), gaze=(0, -30), stretch=1.02, mid=(6, 0, 0), turn=0), K(.62, 'snap', gaze=(8, 0), lids=(-30, 75), toward=.3), K(1.1, base=WORK)],
             breath=(0, 1), hair=1.3, role='react', state='working'))
    add(Clip('interrupted', 1.2, [K(0, base=WORK), K(.08, 'snap', stretch=1.12, lids=(-88, 88), pupil=7, toward=-.3, neck=(-2, 0, 0), head=(-6, 0, 0)), K(.55),
             K(.7, 'snap', gaze=(0, 0), lids=(-30, 80)), K(1.2, base=DEAD)], breath=(0, 1), hair=1.3, role='react', state='working'))

    # ======================= subagents: three small Noodles copy whatever it does =======================
    UP = dict(h0=0.0, h1=0.0, h2=0.0)
    SUBR = {**SUBS, **UP}
    def bob(t, p):
        p = dict(p)
        for i, ph in enumerate((0, .33, .66)):
            p[f'h{i}'] = p[f'h{i}'] + .07 * math.sin(2 * math.pi * (t / 1.2 + ph))
            p[f'r{i}'] = math.radians(8) * math.sin(2 * math.pi * (t / 2.4 + ph))
        return p
    def ramp_bob(t, p):       # the bob fades in once the minis are up, and is in phase with the rest loop at the end
        q = bob(t, p); k = max(0.0, min(1.0, (t - 1.2) / 1.0)); k = k * k * (3 - 2 * k)
        for i in range(3): q[f'h{i}'] = p[f'h{i}'] + (q[f'h{i}'] - p[f'h{i}']) * k; q[f'r{i}'] = q[f'r{i}'] * k
        return q
    sub_in = [K(0, base=DEAD), K(.4, base=SUBS, gaze=(-20, -6))]
    for i, t in enumerate([.2, .6, 1.0]):
        sub_in += [K(0, **{f'h{i}': -3.0}), K(t, **{f'h{i}': -3.0}), K(t + .35, 'back', **{f'h{i}': 0.0})]
    sub_in += [K(.55, 'snap', gaze=(-28, -14)), K(.95, 'snap', gaze=(24, -14)), K(1.35, 'snap', gaze=(0, -24), lids=(-85, 88), stretch=1.08),
               K(1.7, gaze=(0, -24), stretch=1.0), K(2.4, base=SUBR)]
    add(Clip('subagents_in', 2.4, sub_in, helpers=True, breath=(0, 1), role='enter', state='subagents', extra=lambda t, p: ramp_bob(t, p)))
    seg('subagents_rest', 'subagents', 'rest', 4.8, SUBR, [
        K(1.0, gaze=(-28, -12), turn=-8), K(1.7), K(2.0, gaze=(-4, -22), turn=0), K(2.8), K(3.1, gaze=(22, -14), turn=8), K(3.7)],
        helpers=True, blinks=[1.8, 3.9], extra=bob)
    seg('subagents_hop', 'subagents', 'beat', 2.4, SUBR, [
        K(.5, gaze=(-28, -14)), K(.7, 'out', h0=.35), K(.95, 'in', h0=0.0), K(.9, gaze=(0, -22)), K(1.0, 'out', h1=.35), K(1.25, 'in', h1=0.0),
        K(1.2, gaze=(24, -14)), K(1.3, 'out', h2=.35), K(1.55, 'in', h2=0.0), K(1.6, lids=(-80, 30))], helpers=True, extra=bob)
    seg('subagents_sigh', 'subagents', 'beat', 2.4, SUBR, [
        K(.85, stretch=1.08, poof=1.06, lids=(-40, 80)), K(1.45, stretch=.9, poof=.95, lids=(-6, 70), gaze=(0, -10)), K(1.65)], helpers=True, extra=bob, hair=1.2)
    seg('subagents_lean', 'subagents', 'beat', 2.4, SUBR, [
        K(.85, toward=-.2, turn=-14, mid=(6, -8, 0), gaze=(-30, -22), lids=(-20, 50)), K(1.7)], helpers=True, extra=bob)

    # ======================= speaking: phrases at a natural pace, a small nod per syllable =======================
    def phrase(name, dur, beats, emph=(), side=1):
        P = dict(turn=7 * side, mid=(0, -4 + 4 * side, 0))
        ks = [K(.5, **P)]
        for b in beats:
            big = b in emph
            ks.append(K(b, 'io', head=(-12 if big else -7, 6, 0), neck=(-7 if big else -4, -4, 0), stretch=1.07 if big else 1.03,
                        poof=1.05 if big else 1.0, **({'lids': (-80, 86), 'pupil': 23} if big else {})))
            ks.append(K(b + .14, 'io', head=(0, 6, 0), neck=(-2, -4, 0), stretch=.99, poof=1.0, lidsL=(-34, 80), lidsR=(-30, 80), pupil=21))
        ks.append(K(beats[-1] + .45, **P))
        seg(name, 'speaking', 'beat', dur, SPEAK, ks, hold_in=.3, hold_out=.55, breath=(0, 1), hair=1.1)
    phrase('speak_a', 3.2, [.75, 1.0, 1.25, 1.5, 1.8, 2.05], emph=(1.25,), side=-1)
    phrase('speak_b', 3.8, [.75, .99, 1.23, 1.47, 1.75, 1.99, 2.24, 2.5], emph=(1.75,), side=1)
    phrase('speak_c', 2.6, [.75, 1.0, 1.28, 1.5], side=1)
    phrase('speak_d', 4.4, [.75, .99, 1.24, 1.5, 1.9, 2.14, 2.4, 2.66, 2.9, 3.1], emph=(1.24, 2.66), side=-1)
    seg('speaking_rest', 'speaking', 'rest', 1.8, SPEAK, [K(.8, gaze=(6, 4)), K(1.1)], hold_in=.3, hold_out=.4, blinks=[.9], breath=(.01, 1.8))

    # ======================= done =======================
    enter('done_in', 'done', 2.2, [K(0, base=DEAD), K(.35, stretch=.82, rise=-.14, lids=(4, 40), mid=(6, 0, 0), poof=.9),
          K(.68, 'out', base=DONE, stretch=1.28, rise=.45, head=(-10, 0, 0), poof=1.24), K(.9, turn=28), K(1.15, turn=-24),
          K(1.35, turn=8, stretch=1.18, rise=.18), K(1.5, 'in', stretch=.86, rise=0, turn=0), K(1.8, 'back', stretch=1.18, poof=1.18),
          K(2.2, base=DONE)], events={'apex': .7, 'land': 1.5}, hair=1.4)
    seg('done_rest', 'done', 'rest', 3.6, DONE, [K(1.5, 'out', rise=.05, stretch=1.2), K(1.8, 'in', rise=0, stretch=1.12), K(2.1, stretch=1.16)],
        sway=(8, 5, 3.6), hair=1.2)
    seg('done_wiggle', 'done', 'beat', 2.8, DONE, [
        K(.65, mid=(-4, 10, 0), neck=(0, 8, 0)), K(1.0, mid=(-4, -10, 0), neck=(0, -8, 0)), K(1.35, mid=(-4, 10, 0), neck=(0, 8, 0)),
        K(1.7, mid=(-4, -6, 0), neck=(0, -5, 0)), K(2.0, mid=(-4, 0, 0), neck=(0, 0, 0))], hair=1.4)
    seg('done_hop', 'done', 'beat', 2.4, DONE, [K(.6, stretch=.9, rise=-.06), K(.85, 'out', stretch=1.24, rise=.3), K(1.1, 'in', stretch=.92, rise=0),
        K(1.35, 'back', stretch=1.16)], hair=1.4)

    # ======================= needs you: at the glass =======================
    enter('needs_in', 'needs', .8, [K(0, base=DEAD), K(.15, stretch=.92, lids=(-88, 88), pupil=12),
          K(.42, 'in', base=NEEDS, toward=3.3, stretch=1.08), K(.5, 'out', toward=3.2, stretch=.88), K(.8, 'back', base=NEEDS)],
          events={'contact': .47}, hair=1.3)
    seg('needs_rest', 'needs', 'rest', 4.0, NEEDS, [
        K(.5, 'out', toward=2.5, stretch=1.04, head=(-6, 0, 0)), K(.63, 'in', toward=3.26, stretch=.9, head=(0, 0, 0)),
        K(.78, 'out', toward=2.55, stretch=1.04, head=(-6, 0, 0)), K(.91, 'in', toward=3.26, stretch=.9, head=(0, 0, 0)), K(1.15, toward=3.2, stretch=1.0),
        K(1.45, 'snap', gaze=(-30, 4), turn=-6), K(1.9), K(2.05, 'snap', gaze=(30, 4), turn=6), K(2.5), K(2.65, 'snap', gaze=(0, 6), turn=0)],
        hold_in=.3, hold_out=.5, events={'contact': [.63, .91]}, hair=1.3)
    seg('needs_slide', 'needs', 'beat', 3.2, NEEDS, [
        K(1.3, rise=-1.4, head=(-10, 0, 0), stretch=.95, gaze=(0, 12), pupil=9), K(1.8), K(2.25, 'back', rise=-1.0, head=(0, 0, 0), stretch=1.0, pupil=7)],
        hold_in=.3, hold_out=.5, hair=1.2)
    seg('needs_tap', 'needs', 'beat', 2.4, NEEDS, [
        K(.45, 'out', toward=2.7), K(.56, 'in', toward=3.26), K(.7, 'out', toward=2.7), K(.81, 'in', toward=3.26),
        K(.95, 'out', toward=2.7), K(1.06, 'in', toward=3.26), K(1.3, toward=3.2)], hold_in=.3, hold_out=.5, events={'contact': [.56, .81, 1.06]})

    # ======================= approval: the card sits on its hair =======================
    enter('approval_in', 'approval', .9, [K(0, base=DEAD), K(.22, 'snap', gaze=(0, 30), lids=(-82, 86)), K(.35, gaze=(0, 30)),
          K(.45, 'out', rise=-.55, stretch=.84, lids=(0, 50), poof=.88), K(.7, rise=-1.34, stretch=1.0, poof=1.0), K(.9, 'back', base=APPR)],
          events={'land': .35}, hair=1.3)
    seg('approval_rest', 'approval', 'rest', 4.2, APPR, [
        K(1.3, gaze=(0, 34)), K(1.45, 'snap', gaze=(0, 0), lids=(-60, 85), toward=.4), K(2.3), K(2.45, 'snap', gaze=(0, 34), lids=(-80, 85), toward=0)],
        sway=(7, 3, 4.2), blinks=[2.0])
    seg('approval_wobble', 'approval', 'beat', 2.4, APPR, [
        K(.7, mid=(-2, 9, 0), neck=(-4, 4, 0), gaze=(14, 30), pupil=13), K(1.05, mid=(-2, -8, 0), neck=(-4, -4, 0), gaze=(-12, 30)), K(1.4, mid=(-2, 3, 0)),
        K(1.7, mid=(-2, 0, 0), neck=(-4, 0, 0), pupil=18)], hair=1.3)
    def hold_pose(k):
        p = dict(NEUTRAL); p.update(APPR)
        p.update(rise=-1.25 + .32 * k, stretch=1 + .14 * k, poof=1 - .1 * k, lidsL=(-80 + 86 * k, 85 - 45 * k), lidsR=(-80 + 86 * k, 85 - 45 * k),
                 pupilL=18 - 9 * k, pupilR=18 - 9 * k, mid=(-2, (1 if round(k * 12) % 2 else -1) * (.5 + 3 * k), 0))
        return p
    add(Clip('approval_hold', 0, scrub=hold_pose, n=13, role='scrub', state='approval'))
    held = hold_pose(1.0)
    add(Clip('approval_allow', 1.0, [K(0, base=held), K(.12, 'in', rise=-1.34, stretch=.86), K(.3, 'out', rise=-.5, stretch=1.24, lids=(-80, 22), gaze=(0, 30), pupil=18),
             K(.6, rise=-.9, stretch=1.04), K(1.0, base=DEAD)], breath=(0, 1), events={'launch': .28}, hair=1.4, role='react', state='approval'))
    add(Clip('approval_deny', 1.0, [K(0, base=APPR), K(.15, 'snap', rise=-1.6, stretch=.88, lids=(6, 40)), K(.5, rise=-1.45, gaze=(0, -24), lids=(-20, 70)),
             K(1.0, base=DEAD)], breath=(0, 1), events={'drop': .15}, role='react', state='approval'))

    # ======================= blocked =======================
    enter('blocked_in', 'blocked', 1.2, [K(0, base=DEAD), K(.25, stretch=.9, mid=(-6, 0, 0)), K(.45, 'out', stretch=1.16, rise=.24, head=(-14, 0, 0), gaze=(0, 22), lids=(-82, 86)),
          K(.52, 'out', stretch=.82, rise=.04, lids=(10, 30), pupil=8, head=(6, 0, 0)), K(.8, rise=0, stretch=1.0), K(1.2, base=BLOCK)],
          events={'bonk': .5}, hair=1.5)
    seg('blocked_rest', 'blocked', 'rest', 5.6, BLOCK, [
        K(1.7, stretch=1.1, mid=(0, 0, 3), neck=(2, 3, 3), head=(-2, 5, 0), lidsL=(-24, 80), lidsR=(-18, 80), gaze=(2, -8), poof=1.04),
        K(3.0, stretch=.86, mid=(12, 0, 8), neck=(16, 9, 8), head=(10, 11, 0), lidsL=(10, 70), lidsR=(14, 70), gaze=(4, -40), poof=.92), K(3.6),
        K(3.9, neck=(16, 9, 18)), K(4.2, neck=(16, 9, -2)), K(4.5, neck=(16, 9, 8))], breath=(0, 1), hair=1.3)
    seg('blocked_try', 'blocked', 'beat', 3.2, BLOCK, [
        K(.9, stretch=1.14, rise=.2, head=(-12, 0, 0), neck=(0, 0, 0), mid=(0, 0, 0), gaze=(0, 22), lids=(-82, 86), pupil=20),
        K(1.0, 'out', stretch=.84, rise=.06, lids=(8, 30), pupil=8, head=(6, 0, 0)), K(1.5, stretch=1.0, rise=0), K(2.1, lids=(6, 70))],
        breath=(0, 1), events={'bonk': 1.0}, hair=1.5)

    # ======================= compacting, waiting =======================
    enter('compacting_in', 'compacting', .8, [K(0, base=DEAD), K(.15, 'snap', stretch=1.08, lids=(-88, 88), pupil=12), K(.6, base=SQUASH, stretch=.7), K(.8, base=SQUASH)], hair=1.3)
    seg('compacting_rest', 'compacting', 'rest', 3.6, SQUASH, [
        K(.6, 'snap', gaze=(-22, 0)), K(1.1), K(1.25, 'snap', gaze=(22, 0)), K(1.6, stretch=.8, poof=.88), K(2.1, stretch=.69, poof=.78), K(2.4, 'snap', gaze=(0, 0))],
        hold_in=.3, hold_out=.5, breath=(0, 1), sway=(5, 0, .9))
    add(Clip('compact_out', .8, [K(0, base=SQUASH), K(.25, 'out', stretch=1.26, rise=.12, poof=1.2, lids=(-80, 85), pupil=19), K(.5, stretch=.94, rise=0),
             K(.8, base=DEAD)], breath=(0, 1), hair=1.5, role='react', state='compacting'))
    seg('waiting_rest', 'waiting', 'rest', 4.4, WAIT, [
        K(1.0, gaze=(28, 34), head=(-14, 6, 0), neck=(-4, 4, 0), lids=(-44, 80)), K(2.0), K(2.4, gaze=(4, -6), head=(0, 0, 0), neck=(3, -2, 0), lids=(4, 68)),
        K(3.0, stretch=.9, poof=.95, mid=(6, 0, 0)), K(3.5, stretch=1.0, poof=1.0, mid=(2, -3, 0))], blinks=[1.45, 2.75], sway=(2, 2, 4.4))
    tap = []
    for i, t in enumerate([.6, .9, 1.2, 1.5, 1.8]):
        tap += [K(t, 'out', neck=(9, -2, 0), head=(4, 0, 0)), K(t + .15, neck=(3, -2, 0), head=(0, 0, 0))]
    seg('waiting_tap', 'waiting', 'beat', 2.6, WAIT, tap + [K(.5, gaze=(10, -10))])

    # ======================= dizzy (one-shot) =======================
    def dizzy_extra(t, p):
        p = dict(p)
        T = 3.2
        if t < T:
            env = math.exp(-t * .85); a = 20 * math.sin(t * 9.5) * env; sw = 32 * env
            p['mid'] = (0, a * .5, 0); p['neck'] = (0, a * .8, 0); p['head'] = (0, a * .6, 0); p['turn'] = a * .5
            p['gazeL'] = (sw * math.cos(t * 7.5), sw * math.sin(t * 7.5)); p['gazeR'] = (sw * math.cos(-t * 7.5 + 2), sw * math.sin(-t * 7.5 + 2))
            p['pupilL'] = 19 - 7 * env; p['pupilR'] = 19 + 3 * env
            p['lidsR'] = (p['lidsR'][0] + 20 * env, p['lidsR'][1] - 20 * env)
        elif t < T + .5:
            s = 16 * math.sin((t - T) * 2 * math.pi * 6) * (1 - (t - T) / .5)
            p['neck'] = (3, s, 0); p['head'] = (0, s * .7, 0); p['lidsL'] = p['lidsR'] = (8, 30)
        return p
    add(Clip('dizzy', 4.8, [K(0, base=DEAD), K(3.2, base=DEAD, lids=(-60, 80)), K(3.7, base=DEAD, lids=(8, 30)), K(4.0, 'back', base=DEAD, lids=(-50, 85)), K(4.8, base=DEAD)],
             breath=(0, 1), blinks=[4.2], extra=dizzy_extra, hair=1.6, role='once', state='dizzy'))

    # ======================= sleep =======================
    enter('sleep_in', 'sleep', 2.8, [K(0, base=DEAD), K(.6, stretch=1.2, rise=.12, lids=(8, 20), head=(-14, 0, 0), neck=(-4, 0, 0), poof=1.12), K(1.0),
          K(1.4, 'back', stretch=.93, lids=CLOSED, head=(4, 0, 0), neck=(4, 0, 0), poof=1.0), K(2.8, base=SLEEP)], hair=1.2)
    seg('sleep_rest', 'sleep', 'rest', 4.0, SLEEP, [K(2.75, base=SLEEP), K(2.85, 'snap', rise=-2.6), K(3.05, rise=-2.7)], hold_in=.3, hold_out=.4,
        extra=lambda t, p: {**p, 'rise': p['rise'] + .07 * math.sin(2 * math.pi * t / 4.0)})
    seg('sleep_twitch', 'sleep', 'beat', 2.4, SLEEP, [K(.8, 'snap', hairtilt=(10, -8, 0), poof=1.06), K(1.1, hairtilt=(0, 0, 0), poof=1.0)], hold_in=.3, hold_out=.4, hair=1.6)

    # ======================= popping up and the touch reactions =======================
    add(Clip('popup', 1.8, [K(0, base=DEAD, rise=-4.2, lids=(-88, 88), gaze=(0, 0), pupil=10), K(.35, 'out', rise=.32, stretch=1.18),
             K(.48, 'in', rise=0, stretch=.88), K(.6, stretch=1.0), K(.72, 'snap', gaze=(-32, 0), lids=(-80, 88), pupil=14, mid=(0, 5, 0), turn=-8), K(1.0),
             K(1.1, 'snap', gaze=(32, 0), mid=(0, -5, 0), turn=8), K(1.3), K(1.8, base=DEAD)], breath=(0, 1), events={'land': .48}, hair=1.4, role='react'))
    add(Clip('poke', 1.5, [K(0, base=DEAD), K(.06, 'out', stretch=.8, lids=CLOSED, poof=.88), K(.2, 'out', stretch=1.12, toward=-.3, lids=(-88, 88), pupil=6, poof=1.12),
             K(.8, stretch=1.02), K(1.0, lids=(-40, 70), pupil=14, toward=0), K(1.5, base=DEAD)], breath=(0, 1), hair=1.5, role='react'))
    add(Clip('pet', 1.8, [K(0, base=DEAD), K(.22, lids=(4, 40), mid=(0, 12, 0), neck=(0, 10, 0), head=(0, 8, 0), stretch=.95, toward=.3),
             K(.5, mid=(0, 4, 0), neck=(0, 4, 0)), K(.75, mid=(0, 12, 0), neck=(0, 10, 0)), K(1.0, mid=(0, 4, 0), neck=(0, 4, 0), lids=(6, 42)),
             K(1.3, 'io', lids=(-70, 28), stretch=1.06, poof=1.08, mid=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), toward=0), K(1.8, base=DEAD)],
             breath=(0, 1), hair=1.3, role='react'))
    return C


CLIPS = build()
SKIP = '--skip' in sys.argv


def frames_of(clip):
    if clip.scrub:
        return [clip.scrub(i / (clip.n - 1)) for i in range(clip.n)]
    ts = [i / FPS for i in range(clip.n)]
    return springs(clip, [overlay(clip, t, clip.primary(t)) for t in ts])


def preview_mode(on):
    """motion review: no hair strands, the surface material instead of the gel volume, no bloom. About 1 s a frame."""
    for m in D.objects['HairCloud'].modifiers:
        if m.type == 'PARTICLE_SYSTEM': m.show_render = not on
    D.objects['Body'].material_slots[0].material = D.materials['Skin' if on else 'Gel']
    sc.render.use_compositing = not on


def render(names, step=1, samples=128, pct=50, out='anim'):
    meta_path = bpy.path.abspath('//renders/clips.json')
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {'fps': FPS, 'clips': {}}
    t0 = time.time()
    for name in names:
        clip = CLIPS[name]
        poses = frames_of(clip)
        data = []
        for i, p in enumerate(poses):
            apply(p, clip.helpers)
            data.append(anchors(p))
            path = bpy.path.abspath(f'//renders/{out}/{name}_{i:03d}.png')
            if i % step == 0 and not (SKIP and os.path.exists(path)): shot(f'{out}/{name}_{i:03d}', samples, pct)
        if out == 'anim':
            ev = {k: ([round(x * FPS) for x in v] if isinstance(v, list) else round(v * FPS)) for k, v in clip.events.items()}
            meta['beat_chance'] = BEAT_CHANCE
            meta['clips'][name] = {'n': len(poses), 'loop': clip.loop, 'scrub': bool(clip.scrub), 'events': ev, 'role': clip.role, 'state': clip.state,
                                   'anchors': ['hairX', 'hairY', 'faceX', 'faceY', 'roll', 'press', 'rise'], 'frames': data}
            json.dump(meta, open(meta_path, 'w'), separators=(',', ':'))
        print(f'{name}: {len(poses)} frames, {time.time() - t0:.0f} s', flush=True)
    apply(frames_of(CLIPS['idle_rest'])[0], False)


if __name__ in ('__main__', '<run_path>') or 'animate' in sys.argv[0:1]:
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    opts = {'step': 1, 'samples': 128, 'out': 'anim'}
    names = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('--preview', '--skip'): opts[a[2:]] = True; i += 1
        elif a.startswith('--'): opts[a[2:]] = argv[i + 1]; i += 2
        else: names.append(a); i += 1
    if not names or names == ['all']: names = list(CLIPS)
    if 'preview' in opts or '--preview' in argv:
        preview_mode(True)
        try: render(names, step=int(opts.get('step', 3)), samples=8, pct=25, out='preview')
        finally: preview_mode(False)
    else:
        render(names, step=int(opts['step']), samples=int(opts['samples']), out=opts['out'])
