# Noodle's renderer, prototyped in numpy

How NoodleStage.swift paints the tube (October 2026), worked out here against a per-pixel truth. Frames come from the
app: run any render with `SIMCTL_CHILD_NOODLE_DUMP=1` and the app writes `Documents/coil-dump.bin` (per frame: t, then
the 64 points as Float32), which these scripts read.

- `coilpaint.py`: the Swift colour model (albedo × light + sheen + highlight, the shade and depth cue) read from
  NoodleRest.swift; `truth()` renders a frame per pixel as the union of spheres along the curve (z-buffer, the normal of
  the frontmost sphere with its component along the tube removed, the 3D proximity shade). That is what the tube
  should look like.
- `tiles4.py`: the painter the Swift does. The tube is the union of discs at cuts along the curve; each disc paints the
  crescent its nearer neighbour's disc leaves uncovered (so within a stretch every pixel is painted by the nearest disc
  holding it); a disc nearer than both neighbours (an apex of the stretch, an end facing you) is painted whole, in
  strips across. Every tile is one fill with one linear gradient across the tube whose stops are the truth sampled on
  the tile itself (the frontmost sphere within 3R of arc at that point, refined along the sweep). Painted back to
  front. The gradient axis is the projected tangent smoothed along the tube.
- `view.py dump.bin 32 out.png`: truth | painter for the frame at 32 s, with zooms of the head and the leftmost nose.
- `variants.py`, `tiles.py`, `tiles2.py`, `sweep.py`: the earlier attempts (a port of the previous quad renderer,
  discs with straight-tube gradients, forward-only crescents), kept for the record of what fails and why: beads come
  from gradients modelled per slice instead of sampled, from unstable axes, and from any tile painted far from where
  its colours were taken.
- `motion.py dump.bin timeline`: per-second peak speed, acceleration, tightest bend (R·k) and self-clearance.
- `beforeafter.py before-dir after-dir out.png 32,44`: close-ups of the same frames from two renders.
