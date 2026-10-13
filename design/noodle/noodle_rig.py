"""Noodle: pose and render helpers for noodle.blend.

Open noodle.blend, then run this file from Blender's Text editor (it is also stored inside the .blend as
the text block "noodle_rig.py"). It registers the helpers in bpy.app.driver_namespace so they can be called
from the Python console or over the Blender MCP:

    ns = bpy.app.driver_namespace
    ns['pose'](**ns['STATES']['idle'])               # pose the character
    ns['shot']('st_idle', samples=128, pct=50)       # render one still to OUT/st_idle.png
    ns['render_states']()                            # every state + hero
    ns['render_gags']()                              # every gag loop, OUT/anim/<gag>_NN.png

Then tools/noodle-watch.sh turns the PNGs into the watch's clips.

The rig
  Rig (armature)        bones Base / Mid / Neck / Head bend the body; Mid's Y scale is the stretch
  Rig location          rise (z, negative sinks it below the screen edge), toward (-y, toward the camera)
  Eye{L,R}Upper/Lower   felt lid shells, rotated about X. Upper: about -88 wide open … 14 closed.
                        Lower: 88 open … 6 closed. (14, 6) is the clean closed pair; more overlap z-fights.
                        Lids are hidden when fully open, and their back half is masked in the LidSkin/LidFur
                        shaders so no rim shows around the eyeball.
  Eye{L,R}Ball          the eyeball; gaze rotates it (yaw, pitch in degrees) and the pupil shader moves with it
  EyeWhite{L,R}         pupil and iris size are shader masks (pupil_size in degrees, 19 = normal)
  HairCloud             pink hairdo; poof scales it, hairtilt rotates it around the crown
  Helper0-2             collection instances of "Noodle" used for the subagents shot

Look notes (2026-10-01, v4: gel)
  The body is a glowing gel, not a surface shader. Material "Gel" on Body:
    Surface: Principled BSDF, Transmission 1, Roughness .3 (frosted), IOR 1.38, mixed with a Transparent BSDF
      on shadow rays (Light Path > Is Shadow Ray), so lights outside reach the inside of the volume.
    Volume: Volume Scatter (color 1/.48/.14, density 4, anisotropy .35) + Volume Absorption (color 1/.32/.06,
      density 3.5). Thin parts glow orange; thick parts go deep red. Lower densities wash out to pale pink.
    The body mesh is capped at the bottom (off-screen) so the volume is watertight.
  "Core": a warm point light (700 W, 1/.52/.16) inside the neck, parented to the Neck bone and hidden from
    camera/reflections: the glow from inside. CoreH0-2 are the same for the subagent minis (only on in that shot).
  Lids stay opaque silicone (LidSkin*, old Skin look) tuned to the gel's orange: gel lids show the pupils
    through closed lids. The silicone material "Skin" is kept for comparison.
  Fur on body and lids is off (particle modifiers disabled). Hair keeps its fur.
  Lighting: Key 700 (big softbox), Fill 40, Top 120. Back/KickL/KickR at ~14% of before (1365/588/294),
    saturated orange, silicone-only: too much backlight blows the gel to pink-white. Hair has its own rim
    lights (HairOnly). EyeKey 220 + Catch 260 light the eyeballs only (EyesOnly).
  Color: Khronos PBR Neutral view transform (AgX desaturated the glow to white), exposure -2.0.
  Compositor "NoodleComp": Bloom (threshold 2.5, strength .22, size .45) for the halo; the eyeballs
    (pass_index 7) are masked out so pupils stay pure black, and the background stays true black for OLED.
  Volumes are noisier: gag loops were rendered at 64 samples.
"""
import bpy, math

OUT = bpy.path.abspath('//renders')            # next to noodle.blend; change before rendering if needed
ns = bpy.app.driver_namespace
D = bpy.data
sc = bpy.context.scene
arm = D.objects['Rig']
cloud = D.objects['HairCloud']
for pb in arm.pose.bones: pb.rotation_mode = 'XYZ'

# the hairdo's rest transform is stored on the object so poof/hairtilt are always relative to it
if 'rest_loc' not in cloud:
    cloud['rest_loc'] = list(cloud.location); cloud['rest_rot'] = list(cloud.rotation_euler); cloud['rest_scale'] = list(cloud.scale)


def lids(side, up, lo):
    u = D.objects['Eye' + side + 'Upper']; l = D.objects['Eye' + side + 'Lower']
    u.rotation_euler = (math.radians(up), 0, 0); l.rotation_euler = (math.radians(lo), 0, 0)
    u.hide_render = up <= -50; l.hide_render = lo >= 60          # an open lid tucks away


def gaze(side, yaw, pitch):
    # the pupil is painted in the eyeball's own coordinates, so rotating the ball moves it. (The shader used to read
    # the Gaze empty's coordinates; collection instances like the subagent minis then lost their pupils.)
    r = (math.radians(pitch), 0, math.radians(yaw))
    D.objects['Eye' + side + 'Gaze'].rotation_euler = r
    D.objects['Eye' + side + 'Ball'].rotation_euler = r


def pupil_size(side, deg):
    m = D.materials['EyeWhite' + side].node_tree.nodes
    for name, extra, soft in (('PupilMask', 0, 0.004), ('IrisMask', 4.5, 0.012)):
        c = math.cos(math.radians(deg + extra)); n = m[name]
        n.inputs['From Min'].default_value = c - soft; n.inputs['From Max'].default_value = c + soft


def bend(base=(0, 0, 0), mid=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), stretch=1.0):
    for n, r in (('Base', base), ('Mid', mid), ('Neck', neck), ('Head', head)):
        pb = arm.pose.bones[n]; pb.rotation_euler = tuple(math.radians(a) for a in r); pb.scale = (1, 1, 1)
    arm.pose.bones['Mid'].scale = (1 / math.sqrt(stretch), stretch, 1 / math.sqrt(stretch))


def pose(base=(0, 0, 0), mid=(0, 0, 0), neck=(0, 0, 0), head=(0, 0, 0), stretch=1.0, rise=0.0, turn=0.0, toward=0.0,
         lidsL=(-10, 80), lidsR=(-10, 80), gazeL=(4, -6), gazeR=(4, -6), pupil=19, pupilL=None, pupilR=None,
         poof=1.0, hairtilt=(0, 0, 0)):
    bend(base, mid, neck, head, stretch)
    arm.location = (0, -toward, rise); arm.rotation_euler = (0, 0, math.radians(turn))
    lids('L', *lidsL); lids('R', *lidsR); gaze('L', *gazeL); gaze('R', *gazeR)
    pupil_size('L', pupilL or pupil); pupil_size('R', pupilR or pupil)
    cloud.location = tuple(cloud['rest_loc']); cloud.scale = tuple(s * poof for s in cloud['rest_scale'])
    cloud.rotation_euler = tuple(r + math.radians(a) for r, a in zip(cloud['rest_rot'], hairtilt))
    bpy.context.view_layer.update()


def shot(name, samples=64, pct=50):
    sc.cycles.samples = samples; sc.render.resolution_percentage = pct
    sc.render.filepath = f'{OUT}/{name}.png'
    bpy.ops.render.render(write_still=True)


def seq(name, n, fn, samples=64, pct=40):
    for f in range(n):
        pose(**fn(f)); shot(f'anim/{name}_{f:02d}', samples, pct)
    pose()


STATES = {
    'idle': dict(mid=(2, -3, 0), neck=(3, -2, 0), lidsL=(-10, 80), lidsR=(-6, 80), gazeL=(6, -4), gazeR=(6, -4)),
    'listening': dict(mid=(6, 0, 0), neck=(8, 0, 0), head=(4, 0, 0), stretch=1.1, lidsL=(-85, 85), lidsR=(-85, 85), gazeL=(0, 0), gazeR=(0, 0), pupil=24, poof=1.06),
    'thinking': dict(mid=(0, 8, 0), neck=(-4, 12, 0), head=(-6, 10, 0), lidsL=(-55, 80), lidsR=(-2, 80), gazeL=(22, 24), gazeR=(22, 24)),
    'working': dict(mid=(6, 0, 0), neck=(10, 0, 0), head=(8, 0, 0), lidsL=(-22, 40), lidsR=(-22, 40), gazeL=(-8, -26), gazeR=(-8, -26)),
    'speaking': dict(mid=(0, -6, 0), neck=(-2, -6, 0), head=(0, 9, 0), stretch=0.97, lidsL=(-34, 80), lidsR=(-30, 80), gazeL=(0, 2), gazeR=(0, 2), pupil=21),
    'done': dict(stretch=1.16, mid=(-4, 0, 0), lidsL=(-80, 22), lidsR=(-80, 22), gazeL=(0, 10), gazeR=(0, 10), poof=1.18),
    'needs': dict(toward=3.0, rise=-1.0, lidsL=(-88, 88), lidsR=(-88, 88), gazeL=(0, 4), gazeR=(0, 4), pupil=7),
    'blocked': dict(mid=(8, 0, 6), neck=(12, 6, 6), head=(6, 8, 0), lidsL=(6, 80), lidsR=(12, 80), gazeL=(4, -34), gazeR=(0, -34), poof=.95, hairtilt=(8, 6, 0)),
    'dizzy': dict(mid=(0, -10, 0), neck=(0, 14, 0), head=(0, -12, 0), lidsL=(-70, 80), lidsR=(-30, 50), gazeL=(-28, 24), gazeR=(26, -22), pupilL=13, pupilR=22),
    'sleep': dict(rise=-2.75, lidsL=(14, 6), lidsR=(14, 6)),
}


def subagents(samples=128, pct=50):
    """The main one side-eyes three small instances of itself popping up in front."""
    H = [D.objects[f'Helper{i}'] for i in range(3)] + [o for o in D.objects if o.name.startswith('CoreH')]
    pose(gazeL=(-26, -8), gazeR=(-26, -8), lidsL=(-10, 80), lidsR=(-6, 80))
    arm.location = (0.25, 0.8, 0.15)
    for h in H: h.hide_render = False
    bpy.context.view_layer.update(); shot('st_subagents', samples, pct)
    for h in H: h.hide_render = True
    arm.location = (0, 0, 0); pose()


def render_states(samples=128, pct=50):
    for k, v in STATES.items():
        pose(**v); shot('st_' + k, samples, pct)
    subagents(samples, pct)
    pose(**STATES['idle']); shot('hero', 256, 100)


# ---------- gag loops (12 fps) ----------
def ease(k): k = max(0.0, min(1.0, k)); return k * k * (3 - 2 * k)
def lerp(a, b, k): return a + (b - a) * k
DEAD = dict(lidsL=(-10, 80), lidsR=(-6, 80), gazeL=(6, -4), gazeR=(6, -4))


def popup(f):   # rises from below the edge, overshoots, double take, deadpan
    if f < 6: k = ease(f / 5); return dict(rise=lerp(-4.2, 0.35, k), stretch=1 + 0.12 * k, lidsL=(-88, 88), lidsR=(-88, 88), gazeL=(0, 0), gazeR=(0, 0), pupil=10)
    if f < 9: k = ease((f - 6) / 2); return dict(rise=lerp(0.35, 0.0, k), stretch=lerp(1.12, 0.94, k) if f < 8 else 1.0, lidsL=(-88, 88), lidsR=(-88, 88), gazeL=(0, 0), gazeR=(0, 0), pupil=10)
    if f < 12: return dict(lidsL=(-80, 88), lidsR=(-80, 88), gazeL=(-30, 0), gazeR=(-30, 0), pupil=14, mid=(0, 3, 0))
    if f < 15: return dict(lidsL=(-80, 88), lidsR=(-80, 88), gazeL=(30, 0), gazeR=(30, 0), pupil=14, mid=(0, -3, 0))
    k = ease((f - 15) / 4); return dict(lidsL=(lerp(-80, -10, k), 80), lidsR=(lerp(-80, -6, k), 80), gazeL=(6 * k, -4 * k), gazeR=(6 * k, -4 * k), pupil=lerp(14, 19, k))


def poke(f):    # flinch, frozen pinprick stare, lids come back down slowly
    if f < 3: return dict(DEAD)
    if f == 3: return dict(stretch=0.9, lidsL=(-88, 88), lidsR=(-88, 88), gazeL=(0, 0), gazeR=(0, 0), pupil=7)
    if f < 16: return dict(stretch=1.06, lidsL=(-88, 88), lidsR=(-88, 88), gazeL=(0, 0), gazeR=(0, 0), pupil=7)
    if f < 19: k = ease((f - 16) / 2); return dict(stretch=lerp(1.06, 1.0, k), lidsL=(lerp(-88, -42, k), 80), lidsR=(lerp(-88, -40, k), 80), gazeL=(0, 0), gazeR=(0, 0), pupil=lerp(7, 15, k))
    if f < 21: return dict(lidsL=(-42, 80), lidsR=(-40, 80), gazeL=(0, 0), gazeR=(0, 0), pupil=15)
    k = ease((f - 21) / 5); return dict(lidsL=(lerp(-42, -10, k), 80), lidsR=(lerp(-40, -6, k), 80), gazeL=(6 * k, -4 * k), gazeR=(6 * k, -4 * k), pupil=lerp(15, 19, k))


def sleep(f):   # eyes close, then it sinks until only the hair is out
    if f < 9: k = ease(f / 8); return dict(lidsL=(lerp(-10, 14, k), lerp(80, 6, k)), lidsR=(lerp(-6, 14, k), lerp(80, 6, k)), mid=(3 * k, 0, 0), neck=(4 * k, 0, 0))
    k = ease((f - 9) / 13); return dict(rise=lerp(0, -2.75, k) + 0.08 * math.sin(f * 1.3) * (1 - k), lidsL=(14, 6), lidsR=(14, 6), mid=(4, 0, 0), neck=(4, 0, 0), head=(4 * k, 0, 0))


def press(f):   # face on the glass, looks left and right for you, slides down
    if f < 6: k = ease(f / 5); return dict(toward=3.0 * k, rise=-1.0 * k, lidsL=(-88, 88), lidsR=(-88, 88), gazeL=(0, 4), gazeR=(0, 4), pupil=lerp(19, 7, k))
    if f < 15:
        dx = [0, -24, -24, 24, 24, 0, 0, 0, 0][f - 6]
        return dict(toward=3.0, rise=-1.0, lidsL=(-88, 88), lidsR=(-88, 88), gazeL=(dx, 4), gazeR=(dx, 4), pupil=7)
    k = ease((f - 15) / 6); return dict(toward=3.0, rise=lerp(-1.0, -1.45, k), lidsL=(-88, 88), lidsR=(-88, 88), gazeL=(0, 10), gazeR=(0, 10), pupil=7, head=(-6 * k, 0, 0))


def dizzy(f):   # head wobbles, each eye goes its own way, settles
    t = f / 12.0; env = math.exp(-t * 1.3); a = 16 * math.sin(t * 11) * env; sw = 30 * env
    gl = (sw * math.cos(t * 9), sw * math.sin(t * 9)); gr = (sw * math.cos(-t * 9 + 2), sw * math.sin(-t * 9 + 2)); lid = (lerp(-60, -10, 1 - env), 80)
    return dict(mid=(0, a * 0.5, 0), neck=(0, a * 0.8, 0), head=(0, a * 0.6, 0), lidsL=lid, lidsR=(lid[0] + 20 * env, 60 + 20 * (1 - env)),
                gazeL=gl, gazeR=gr, pupilL=lerp(19, 12, env), pupilR=lerp(19, 22, env), hairtilt=(0, a * 0.4, 0))


def think(f):   # one lid drops, the eyes roll up and across
    if f < 5: k = ease(f / 4); return dict(lidsL=(lerp(-10, -60, k), 80), lidsR=(lerp(-6, -60, k), 80), gazeL=(-22 * k, 24 * k), gazeR=(-22 * k, 24 * k), mid=(0, 4 * k, 0), neck=(0, 6 * k, 0))
    if f < 11: k = ease((f - 5) / 3); return dict(lidsL=(-60, 80), lidsR=(lerp(-60, -4, k), 80), gazeL=(-22, 24), gazeR=(-22, 24), mid=(0, 4, 0), neck=(0, 6, 0))
    if f < 17: k = ease((f - 11) / 3); return dict(lidsL=(-60, 80), lidsR=(-4, 80), gazeL=(lerp(-22, 24, k), 24), gazeR=(lerp(-22, 24, k), 24), mid=(0, lerp(4, -4, k), 0), neck=(0, lerp(6, -6, k), 0))
    k = ease((f - 17) / 5); return dict(lidsL=(lerp(-60, -10, k), 80), lidsR=(lerp(-4, -6, k), 80), gazeL=(lerp(24, 6, k), lerp(24, -4, k)), gazeR=(lerp(24, 6, k), lerp(24, -4, k)), mid=(0, -4 * (1 - k), 0), neck=(0, -6 * (1 - k), 0))


GAGS = [('popup', 22, popup), ('poke', 30, poke), ('sleep', 26, sleep), ('press', 22, press), ('dizzy', 28, dizzy), ('think', 24, think)]


def render_gags(names=None):
    for name, n, fn in GAGS:
        if names is None or name in names: seq(name, n, fn)


ns.update(dict(lids=lids, gaze=gaze, pupil_size=pupil_size, bend=bend, pose=pose, shot=shot, seq=seq, STATES=STATES,
               GAGS=GAGS, subagents=subagents, render_states=render_states, render_gags=render_gags,
               mpose=pose, mshot=shot))
print('noodle rig ready; renders go to', OUT)
