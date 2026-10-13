/* Pix: a deadpan fruit sprite that knows it is a sprite. Its moods are render settings.
 * Two species: an apple and a banana. Each pixel is a slightly different shade of an OKLab gradient,
 * with a one-pixel bevel and a glint. Eyes are two pixels wide (white + black): permanent side-eye.
 *
 *   thinking   its resolution drops: all its pixels go to the brain
 *   done       it renders in HD for two seconds (gloss, blush, sparkles, a mouth), then back to pixels
 *   blocked    "Not Responding": dragged like a frozen window, a copy every frame; each copy a bit more
 *              overripe (the apple browns, the banana gets spots)
 *   sleep      the bouncing screensaver; a different variety on every wall; it celebrates a corner
 *   dizzy      shake the keys: pixels scatter, it reassembles upside down (and goes green)
 *   subagents  it splits into half-resolution copies of other varieties
 *   speaking   an RPG dialog box types the reply out
 *   working    walks in place; each tool call floats up like an RPG damage number
 *   needs you  "!" over its head; it stares, and slowly leans closer to the glass
 *   compacting squashed flat under a press, JPEG'd into blocks, the file size dropping
 *   waiting    rate limited: taps a foot under an hourglass, looks up at the clock, counts down
 *
 *   PIX.draw(ctx, { species, cx, cy, px, t, state, stateT, look, voice, text, tools, subagents, screen, room, eyeMode })
 *     screen   the area it may use (below the watch's status row); room  max height when it leans in; bang  false hides the ! in needs; eyeMode  force the eyes (e.g. 'cam')
 *   draw() is a pure function of its input, so the watch port can render any frame.
 */
(function (root) {
  'use strict';

  // ---------- color ----------
  const PAL = {
    apple: ['#FFC27A', '#FF5A4E', '#E3243F', '#8E1240'],
    greenApple: ['#F4FFA8', '#B8F05E', '#62C93C', '#2E8A3A'],
    golden: ['#FFF6B0', '#FFDA4A', '#FFAF1F', '#E2701A'],
    pinkLady: ['#FFD9C8', '#FF8E8A', '#F0507A', '#A8306E'],
    rot: ['#C8A47C', '#9A6C45', '#6E462A', '#4B2D1C'],
    banana: ['#FFF8B8', '#FFE65C', '#FFC928', '#E39A1A'],
    greenBanana: ['#EEFFB8', '#C2EC6E', '#86CB42', '#559C30'],
    redBanana: ['#FFC9A8', '#F07F5E', '#C2454C', '#7E2A44'],
    ripe: ['#FFE9A0', '#FFC94A', '#F2A42A', '#C8781E'],
    gray: ['#D5D8DD', '#A3A9B2', '#7A828D', '#59606B'],
  };
  const PART = { leaf: ['#C2F57E', '#5CC94F', '#2F8F43'], stem: ['#8A5A2E', '#5A3418'], bstem: ['#A8A04A', '#5E5524'], tip: ['#5A3A20', '#3A2414'] };

  const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
  const toLin = c => { c /= 255; return c <= .04045 ? c / 12.92 : Math.pow((c + .055) / 1.055, 2.4); };
  const toSrgb = c => 255 * (c <= .0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - .055);
  function oklab([r, g, b]) {
    r = toLin(r); g = toLin(g); b = toLin(b);
    const l = Math.cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b), m = Math.cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b), s = Math.cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
    return [.2104542553 * l + .793617785 * m - .0040720468 * s, 1.9779984951 * l - 2.428592205 * m + .4505937099 * s, .0259040371 * l + .7827717662 * m - .808675766 * s];
  }
  function srgb([L, a, b]) {
    const l = (L + .3963377774 * a + .2158037573 * b) ** 3, m = (L - .1055613458 * a - .0638541728 * b) ** 3, s = (L - .0894841775 * a - 1.291485548 * b) ** 3;
    return [toSrgb(4.0767416621 * l - 3.3077115913 * m + .2309699292 * s), toSrgb(-1.2684380046 * l + 2.6097574011 * m - .3413193965 * s), toSrgb(-.0041960863 * l - .7034186147 * m + 1.707614701 * s)].map(v => Math.max(0, Math.min(255, v)));
  }
  const LAB = {}; for (const k in PAL) LAB[k] = PAL[k].map(h => oklab(hex(h)));
  const PLAB = {}; for (const k in PART) PLAB[k] = PART[k].map(h => oklab(hex(h)));
  function grad(stops, u) {
    u = Math.max(0, Math.min(.9999, u)) * (stops.length - 1); const i = Math.floor(u), f = u - i, a = stops[i], b = stops[i + 1];
    return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
  }
  const mix = (a, b, k) => [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
  const hash = (x, y, s) => { const v = Math.sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453; return v - Math.floor(v); };
  const css = (lab, a = 1) => { const c = srgb(lab); return a >= 1 ? `rgb(${c[0] | 0},${c[1] | 0},${c[2] | 0})` : `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`; };
  const WHITE = '#FFFFFF', INK = '#0A0A0C';
  const clamp01 = v => Math.max(0, Math.min(1, v));
  const ease = k => { k = clamp01(k); return k * k * (3 - 2 * k); };
  const step = (v, n) => Math.floor(v * n) / n;

  // ---------- species ----------
  const cellsOf = rows => { const out = []; rows.forEach((r, y) => [...r].forEach((c, x) => { if (c !== '.') out.push([x, y, c]); })); return out; };

  const APPLE = {
    key: 'apple', name: 'APPLE', W: 15, H: 17,
    rows: [
      '...............', '...............', '...............',
      '..XXXX...XXXX..', '.XXXXXXXXXXXXX.',
      'XXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXX', 'XXXXXXXXXXXXXXX',
      '.XXXXXXXXXXXXX.', '.XXXXXXXXXXXXX.', '..XXXXXXXXXXX..', '...XXXXXXXXX...', '....XXX.XXX....',
    ],
    parts: {   // S stem, L leaf
      curl: [[8, 0, 'S'], [7, 1, 'S'], [7, 2, 'S'], [7, 3, 'S'], [10, 0, 'L'], [11, 0, 'L'], [9, 1, 'L'], [10, 1, 'L'], [11, 1, 'L'], [12, 1, 'L'], [8, 2, 'L'], [9, 2, 'L'], [10, 2, 'L']],
      antenna: [[7, 0, 'S'], [7, 1, 'S'], [7, 2, 'S'], [7, 3, 'S'], [8, 2, 'L'], [9, 2, 'L'], [9, 1, 'L'], [10, 1, 'L'], [10, 2, 'L'], [11, 1, 'L']],
      droop: [[7, 3, 'S'], [7, 2, 'S'], [6, 2, 'L'], [5, 2, 'L'], [4, 2, 'L'], [3, 2, 'L'], [5, 1, 'L'], [4, 1, 'L']],
    },
    stemKind: 'stem',
    eyes: [4, 9], eyeY: 8, mouth: [6, 10, 3],
    legs: {
      stand: [[5, 15], [5, 16], [4, 16], [9, 15], [9, 16], [8, 16]],
      stepL: [[5, 15], [4, 15], [3, 15], [9, 15], [9, 16], [8, 16]],
      stepR: [[5, 15], [5, 16], [4, 16], [9, 15], [8, 15], [7, 15]],
    },
    legsHD: [[5.5, 14.6, 16.45, 4.3], [9.5, 14.6, 16.45, 8.3]],
    shine: [[2, 5], [3, 5], [2, 6]],
    tip: [7.5, .5], bangX: 7.5, badge: [2.2, .7],
    base: 'apple', moods: { needs: 'golden', dizzy: 'greenApple' }, cycle: ['apple', 'greenApple', 'golden', 'pinkLady'],
  };

  const BANANA = {
    // a ")" crescent: long tapered neck up to the stem, belly bowing right, blunt bottom with a dark nub
    key: 'banana', name: 'BANANA', W: 15, H: 23, pxScale: 6 / 7, visW: 13, blushDX: 1.1,
    rows: [   // rasterized from the HD outline so both versions are the same banana
      '...............', '...XX..........', '..XXXXX........', '...XXXXXX......', '....XXXXXX.....', '....XXXXXXX....',
      '.....XXXXXXX...', '.....XXXXXXXX..', '......XXXXXXX..', '......XXXXXXXX.', '......XXXXXXXX.', '......XXXXXXXX.',
      '.....XXXXXXXXX.', '.....XXXXXXXX..', '.....XXXXXXXX..', '....XXXXXXXXX..', '....XXXXXXXX...', '...XXXXXXXX....',
      '...XXXXXXX.....', '..XXXXXXX......', '..TTXXX........',
    ],
    parts: {
      curl: [[3, 0, 'S'], [2, 0, 'N']],
      antenna: [[3, 0, 'S'], [2, 0, 'N']],
      droop: [[2, 1, 'S'], [1, 1, 'N']],
    },
    stemKind: 'bstem',
    eyes: [7, 11], eyeY: 11, mouth: [8, 13, 2],
    legs: {
      stand: [[4, 21], [4, 22], [3, 22], [6, 21], [6, 22], [5, 22]],
      stepL: [[4, 21], [3, 21], [2, 21], [6, 21], [6, 22], [5, 22]],
      stepR: [[4, 21], [4, 22], [3, 22], [6, 21], [7, 21]],
    },
    legsHD: [[4.5, 20.6, 22.45, 3.3], [6.5, 20.6, 22.45, 5.3]],
    shine: [[6, 6], [7, 6], [6, 7]],
    tip: [3.5, .5], bangX: 3.5, badge: [12.6, 4.2],
    base: 'banana', moods: { needs: 'ripe', dizzy: 'greenBanana' }, cycle: ['banana', 'greenBanana', 'redBanana', 'ripe'],
  };

  for (const sp of [APPLE, BANANA]) {
    sp.cells = cellsOf(sp.rows);
    sp.isBody = (x, y) => y >= 0 && y < sp.rows.length && x >= 0 && x < sp.W && sp.rows[y][x] !== '.';
    sp.span = sp.rows.map(r => { const a = r.search(/[^.]/); if (a < 0) return null; let b = r.length - 1; while (r[b] === '.') b--; return [a, b]; });
  }
  const SPECIES = { apple: APPLE, banana: BANANA };

  // the shade of one cell: gradient + per-pixel jitter + bevel + glint, then rot / spots
  function shadeBody(sp, mood, x, y, boost, rot, spots) {
    const st = LAB[mood] || LAB[sp.base], W = sp.W, H = sp.H, ch = sp.rows[y][x];
    if (ch === 'T') { const c = grad(PLAB.tip, (x + y) / 30); return [c[0] + boost * .5, c[1], c[2]]; }
    let c = grad(st, (x / W) * .42 + (y / H) * .58);
    if (rot > 0) c = mix(c, grad(LAB.rot, (x / W) * .42 + (y / H) * .58), rot);
    let L = c[0] + (hash(x, y, 3) - .5) * .035 + boost;
    if (!sp.isBody(x + 1, y) || !sp.isBody(x, y + 1)) L -= .065;
    else if (!sp.isBody(x - 1, y) || !sp.isBody(x, y - 1)) L += .045;
    if (sp.shine.some(([sx, sy]) => sx === x && sy === y)) L += .12;
    if (sp.key === 'banana' && sp.span[y] && y >= 5 && y <= 17 && x === sp.span[y][1] - 2) L -= .035;      // the banana's ridge
    c = [L, c[1], c[2]];
    if (spots > 0 && hash(x, y, 5) < spots * .32) c = mix(c, grad(PLAB.tip, .3), .8);
    return c;
  }
  function shadePart(sp, kind, x, y, boost, rot) {
    if (kind === 'L') {
      let c = grad(PLAB.leaf, clamp01((y + (x - 8) * .25) / 3.2));
      if (rot > 0) c = mix(c, grad(LAB.rot, .5), rot * .8);
      return [c[0] + boost + (hash(x, y, 9) - .5) * .03, c[1], c[2]];
    }
    if (kind === 'N') { const c = grad(PLAB.tip, .4); return [c[0] + boost, c[1], c[2]]; }
    const c = grad(PLAB[sp.stemKind], y / 3); return [c[0] + boost, c[1], c[2]];
  }
  const MEMO = new Map();
  function color(key, f) { let c = MEMO.get(key); if (!c) { c = css(f()); if (MEMO.size > 30000) MEMO.clear(); MEMO.set(key, c); } return c; }
  const legColor = (sp, mood) => { const c = grad(LAB[mood] || LAB[sp.base], .9); return css([c[0] * .7, c[1] * .85, c[2] * .85]); };

  // ---------- crisp cells: snap both edges to device pixels so neighbours share an edge at any scale ----------
  function snapper(g) {
    const m = g.getTransform(), sx = m.a || 1, sy = m.d || 1, ex = m.e, fy = m.f;
    return (x, y, w, h) => {
      const x0 = Math.round(x * sx + ex), x1 = Math.round((x + w) * sx + ex), y0 = Math.round(y * sy + fy), y1 = Math.round((y + h) * sy + fy);
      if (x1 > x0 && y1 > y0) g.fillRect((x0 - ex) / sx, (y0 - fy) / sy, (x1 - x0) / sx, (y1 - y0) / sy);
    };
  }

  // ---------- pixel font, 3 × 5 ----------
  const FONT = {
    A: [2, 5, 7, 5, 5], B: [6, 5, 6, 5, 6], C: [3, 4, 4, 4, 3], D: [6, 5, 5, 5, 6], E: [7, 4, 6, 4, 7], F: [7, 4, 6, 4, 4], G: [3, 4, 5, 5, 3],
    H: [5, 5, 7, 5, 5], I: [7, 2, 2, 2, 7], J: [1, 1, 1, 5, 2], K: [5, 5, 6, 5, 5], L: [4, 4, 4, 4, 7], M: [5, 7, 7, 5, 5], N: [6, 5, 5, 5, 5],
    O: [2, 5, 5, 5, 2], P: [6, 5, 6, 4, 4], Q: [2, 5, 5, 6, 3], R: [6, 5, 6, 5, 5], S: [3, 4, 2, 1, 6], T: [7, 2, 2, 2, 2], U: [5, 5, 5, 5, 7],
    V: [5, 5, 5, 5, 2], W: [5, 5, 7, 7, 5], X: [5, 5, 2, 5, 5], Y: [5, 5, 2, 2, 2], Z: [7, 1, 2, 4, 7],
    0: [7, 5, 5, 5, 7], 1: [2, 6, 2, 2, 7], 2: [6, 1, 2, 4, 7], 3: [6, 1, 2, 1, 6], 4: [5, 5, 7, 1, 1], 5: [7, 4, 6, 1, 6], 6: [3, 4, 6, 5, 2],
    7: [7, 1, 2, 2, 2], 8: [2, 5, 2, 5, 2], 9: [2, 5, 3, 1, 6], '+': [0, 2, 7, 2, 0], '-': [0, 0, 7, 0, 0], '.': [0, 0, 0, 0, 2], '!': [2, 2, 2, 0, 2],
    '?': [6, 1, 2, 0, 2], ':': [0, 2, 0, 2, 0], "'": [2, 2, 0, 0, 0], '/': [1, 1, 2, 4, 4], ',': [0, 0, 0, 2, 4], '(': [1, 2, 2, 2, 1], ')': [4, 2, 2, 2, 4], ' ': [0, 0, 0, 0, 0],
  };
  const textWidth = (str, s) => Math.max(0, String(str).length * 4 * s - s);
  function text(g, str, x, y, s, col, align = 'left') {
    str = String(str).toUpperCase();
    let cx = align === 'center' ? x - textWidth(str, s) / 2 : align === 'right' ? x - textWidth(str, s) : x;
    g.fillStyle = col; const R = snapper(g);
    for (const ch of str) {
      const gl = FONT[ch] || FONT[' '];
      for (let r = 0; r < 5; r++) for (let c = 0; c < 3; c++) if (gl[r] & (4 >> c)) R(cx + c * s, y + r * s, s, s);
      cx += 4 * s;
    }
  }

  // ---------- the sprite ----------
  // o: { sp, ox, oy, px, mood, eyes: { mode, look }, legs, dy, flip, stem, mouth, boost, rot, spots, offset(x, y) }
  function paint(g, o) {
    const sp = o.sp, { ox, oy, px } = o, mood = o.mood || sp.base, dy = o.dy || 0, H = sp.H;
    const b = Math.round((o.boost || 0) * 200) / 200, rot = Math.round((o.rot || 0) * 20) / 20, spots = Math.round((o.spots || 0) * 20) / 20;
    const Y = y => (o.flip ? H - 1 - y : y), R = snapper(g), lift = dy * (o.flip ? -1 : 1);
    const cell = (x, y, col, lifted) => {
      const off = o.offset ? o.offset(x, y) : [0, 0];
      g.fillStyle = col; R(ox + (x + off[0]) * px, oy + (Y(y) + off[1] + (lifted ? lift : 0)) * px, px, px);
    };
    const leg = legColor(sp, mood);
    for (const [x, y] of sp.legs[o.legs || 'stand']) cell(x, y, leg, false);
    for (const [x, y, k] of sp.parts[o.stem || 'curl']) cell(x, y, color(`${sp.key}${k}${x},${y},${b},${rot}`, () => shadePart(sp, k, x, y, b, rot)), true);
    for (const [x, y] of sp.cells) cell(x, y, color(`${sp.key}${mood}${x},${y},${b},${rot},${spots}`, () => shadeBody(sp, mood, x, y, b, rot, spots)), true);
    eyes(g, o, Y);
    if (o.mouth) {
      const [mx, my, mw] = sp.mouth, top = oy + (Y(my) + lift) * px, h = o.mouth === 1 ? px * .45 : px;
      g.fillStyle = INK; R(ox + mx * px, top + (px - h) / 2, px * mw, h);
    }
  }

  function eyes(g, o, Y) {
    const sp = o.sp, { ox, oy, px } = o, e = o.eyes || {}, mode = e.mode || 'side', look = e.look ?? 1, dy = (o.dy || 0) * (o.flip ? -1 : 1), EY = sp.eyeY;
    if (mode === 'none') return;
    const R = snapper(g);
    const box = (cx, cy, col, fx = 0, fy = 0, fw = 1, fh = 1) => { g.fillStyle = col; R(ox + (cx + fx) * px, oy + (Y(cy) + dy + fy) * px, fw * px, fh * px); };
    sp.eyes.forEach((ex, i) => {
      if (mode === 'closed') { box(ex, EY, 'rgba(10,10,12,.82)', 0, .55, 2, .3); return; }
      if (mode === 'happy') { box(ex, EY, WHITE, 0, 0, 2, .42); return; }
      if (mode === 'cam') { box(ex, EY, INK, 0, 0, 2, 1); box(ex, EY, WHITE, .18, .16, .32, .32); return; }
      if (mode === 'up') { box(ex, EY, WHITE, 0, 0, 2, 1); box(ex, EY - 1, WHITE, 0, 0, 2, 1); box(ex + (look > 0 ? 1 : 0), EY - 1, INK); return; }
      let right = look > 0;
      if (mode === 'cross') right = i === 0;
      if (mode === 'squint') { box(ex, EY, right ? WHITE : INK, 0, .5, 1, .5); box(ex + 1, EY, right ? INK : WHITE, 0, .5, 1, .5); return; }
      box(ex, EY, right ? WHITE : INK); box(ex + 1, EY, right ? INK : WHITE);
    });
  }

  // ---------- HD: the same fruit as smooth shapes, with everything the pixels could not afford ----------
  function smooth(g, pts) {   // a closed curve through the midpoints of a point list
    const n = pts.length, mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    const m = mid(pts[n - 1], pts[0]); g.moveTo(m[0], m[1]);
    for (let i = 0; i < n; i++) { const p = pts[i], q = mid(pts[i], pts[(i + 1) % n]); g.quadraticCurveTo(p[0], p[1], q[0], q[1]); }
    g.closePath();
  }
  const HD = {
    apple: {
      back(g, X, Y, px) {
        g.strokeStyle = PART.stem[1]; g.lineWidth = px * .9;
        g.beginPath(); g.moveTo(X(7.5), Y(4.2)); g.quadraticCurveTo(X(7.1), Y(2.0), X(8.4), Y(.5)); g.stroke();
        const lg = g.createLinearGradient(X(8), Y(2.4), X(13), Y(.6)); lg.addColorStop(0, PART.leaf[2]); lg.addColorStop(1, PART.leaf[0]);
        g.beginPath(); g.moveTo(X(8.2), Y(2.3)); g.quadraticCurveTo(X(9.4), Y(-.3), X(13.1), Y(.8)); g.quadraticCurveTo(X(11.6), Y(3.1), X(8.2), Y(2.3)); g.fillStyle = lg; g.fill();
        g.beginPath(); g.moveTo(X(8.6), Y(2.1)); g.quadraticCurveTo(X(10.4), Y(1.2), X(12.4), Y(.95)); g.lineWidth = px * .16; g.strokeStyle = 'rgba(20,80,30,.55)'; g.stroke();
      },
      body(g, X, Y) {
        g.beginPath(); g.moveTo(X(7.5), Y(4.1));
        g.bezierCurveTo(X(8.6), Y(2.7), X(12.6), Y(2.4), X(14.2), Y(5.2));
        g.bezierCurveTo(X(15.5), Y(8.2), X(14.6), Y(12.8), X(11.6), Y(14.5));
        g.bezierCurveTo(X(10.2), Y(15.3), X(8.7), Y(14.7), X(7.5), Y(14.8));
        g.bezierCurveTo(X(6.3), Y(14.7), X(4.8), Y(15.3), X(3.4), Y(14.5));
        g.bezierCurveTo(X(.4), Y(12.8), X(-.5), Y(8.2), X(.8), Y(5.2));
        g.bezierCurveTo(X(2.4), Y(2.4), X(6.4), Y(2.7), X(7.5), Y(4.1)); g.closePath();
      },
      front(g, X, Y, px) {
        g.save(); g.translate(X(3.6), Y(5.8)); g.rotate(-.7); g.beginPath(); g.ellipse(0, 0, px * 1.7, px * .7, 0, 0, Math.PI * 2); g.fillStyle = 'rgba(255,255,255,.72)'; g.fill(); g.restore();
      },
      bounds: [-.6, 2.3, 15.6, 15.4],
    },
    banana: {
      // centerline: a quadratic from the stem end (top left) bowing right to the blunt end (bottom left)
      P: [[2.6, 1.7], [16.6, 10.6], [2.9, 20.9]],
      at(t) {
        const [a, b, c] = HD.banana.P, u = 1 - t;
        const x = u * u * a[0] + 2 * u * t * b[0] + t * t * c[0], y = u * u * a[1] + 2 * u * t * b[1] + t * t * c[1];
        const dx = 2 * u * (b[0] - a[0]) + 2 * t * (c[0] - b[0]), dy = 2 * u * (b[1] - a[1]) + 2 * t * (c[1] - b[1]), l = Math.hypot(dx, dy) || 1;
        let w = 1.5 + 6.6 * Math.pow(Math.sin(Math.PI * Math.pow(Math.min(t, .985), 1.18)), .62);
        if (t > .86) w = Math.max(w, 4.6 - (t - .86) * 7);                  // the blunt end
        return { x, y, nx: -dy / l, ny: dx / l, w };                         // n points to the concave (left) side
      },
      back(g, X, Y, px) {
        g.strokeStyle = PART.bstem[1]; g.lineWidth = px * 1.0; g.lineCap = 'butt';
        g.beginPath(); g.moveTo(X(3.0), Y(2.4)); g.quadraticCurveTo(X(2.1), Y(1.0), X(1.0), Y(.4)); g.stroke(); g.lineCap = 'round';
        g.beginPath(); g.ellipse(X(1.0), Y(.4), px * .5, px * .55, .5, 0, Math.PI * 2); g.fillStyle = PART.tip[1]; g.fill();
      },
      body(g, X, Y) {
        const N = 28, L = [], R = [];
        for (let i = 0; i <= N; i++) { const p = HD.banana.at(i / N); L.push([X(p.x + p.nx * p.w / 2), Y(p.y + p.ny * p.w / 2)]); R.push([X(p.x - p.nx * p.w / 2), Y(p.y - p.ny * p.w / 2)]); }
        g.beginPath(); smooth(g, [...R, ...L.reverse()]);
      },
      front(g, X, Y, px) {
        const e = HD.banana.at(1);
        g.beginPath(); g.ellipse(X(e.x), Y(e.y), px * 1.3, px * .75, Math.atan2(e.ny, e.nx), 0, Math.PI * 2); g.fillStyle = PART.tip[0]; g.fill();
        const line = (t0, t1, off, w, col) => { g.beginPath(); for (let i = 0; i <= 20; i++) { const p = HD.banana.at(t0 + (t1 - t0) * i / 20), x = X(p.x + p.nx * p.w * off), y = Y(p.y + p.ny * p.w * off); i ? g.lineTo(x, y) : g.moveTo(x, y); } g.lineWidth = px * w; g.strokeStyle = col; g.stroke(); };
        line(.22, .9, -.22, .2, 'rgba(160,100,0,.22)');                      // the ridge on the back
        line(.3, .62, .3, .5, 'rgba(255,255,255,.6)');                        // gloss
      },
      bounds: [0, 0, 15, 22],
    },
  };

  function paintHD(g, o, t) {
    const sp = o.sp, { ox, oy, px } = o, mood = o.mood || sp.base, P = PAL[mood] || PAL[sp.base], look = o.eyes?.look ?? 1, by = o.by || 0, hd = HD[sp.key];
    const X = c => ox + c * px, Y = r => oy + r * px + by;
    g.save(); g.lineCap = 'round'; g.lineJoin = 'round';
    g.strokeStyle = legColor(sp, mood); g.lineWidth = px * .78;
    for (const [lx, y0, y1, fx] of sp.legsHD) { g.beginPath(); g.moveTo(X(lx), Y(y0)); g.lineTo(X(lx), Y(y1)); g.lineTo(X(fx), Y(y1)); g.stroke(); }
    hd.back(g, X, Y, px);
    const [bx0, by0, bx1, by1] = hd.bounds;
    const lg = g.createLinearGradient(X(bx0), Y(by0), X(bx0 + (bx1 - bx0) * .9), Y(by1 * 1.02)); P.forEach((c, i) => lg.addColorStop(i / (P.length - 1), c));
    hd.body(g, X, Y); g.fillStyle = lg; g.fill();
    g.save(); hd.body(g, X, Y); g.clip();
    let rg = g.createRadialGradient(X(bx0 + 3.4), Y(by0 + 2.6), 0, X(bx0 + 3.4), Y(by0 + 2.6), 9 * px); rg.addColorStop(0, 'rgba(255,255,255,.4)'); rg.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = rg; g.fillRect(X(bx0), Y(by0), (bx1 - bx0) * px, (by1 - by0) * px);
    rg = g.createLinearGradient(0, Y(by0 + (by1 - by0) * .45), 0, Y(by1)); rg.addColorStop(0, 'rgba(60,0,40,0)'); rg.addColorStop(1, 'rgba(60,0,40,.3)');
    g.fillStyle = rg; g.fillRect(X(bx0), Y(by0), (bx1 - bx0) * px, (by1 - by0) * px);
    g.restore();
    hd.body(g, X, Y); g.lineWidth = px * .14; g.strokeStyle = 'rgba(255,255,255,.35)'; g.stroke();
    hd.front(g, X, Y, px);
    // face
    const ec = sp.eyes.map(ex => [ex + 1, sp.eyeY + .5]);
    const bdx = sp.blushDX || 1.45; ec.forEach(([cx, cy], i) => { g.beginPath(); g.ellipse(X(cx + (i ? bdx : -bdx)), Y(cy + 2.0), px * 1.0, px * .48, 0, 0, Math.PI * 2); g.fillStyle = 'rgba(255,80,130,.42)'; g.fill(); });
    for (const [cx, cy] of ec) {
      g.beginPath(); g.ellipse(X(cx), Y(cy), px * 1.05, px * 1.3, 0, 0, Math.PI * 2); g.fillStyle = WHITE; g.fill();
      const pxp = X(cx) + look * px * .32;
      g.beginPath(); g.ellipse(pxp, Y(cy) + px * .12, px * .66, px * .8, 0, 0, Math.PI * 2); g.fillStyle = INK; g.fill();
      g.beginPath(); g.arc(pxp - px * .24, Y(cy) - px * .22, px * .26, 0, Math.PI * 2); g.fillStyle = WHITE; g.fill();
      g.beginPath(); g.arc(pxp + px * .24, Y(cy) + px * .38, px * .11, 0, Math.PI * 2); g.fill();
    }
    const [mx, my, mw] = sp.mouth, mcx = mx + mw / 2;
    g.beginPath(); g.moveTo(X(mcx - .9), Y(my + .35)); g.quadraticCurveTo(X(mcx), Y(my + 1.1), X(mcx + .9), Y(my + .35)); g.lineWidth = px * .32; g.strokeStyle = INK; g.stroke();
    // sparkles
    const spark = (x, y, s) => { if (s <= 0) return; g.beginPath(); g.moveTo(x, y - s); g.quadraticCurveTo(x, y, x + s, y); g.quadraticCurveTo(x, y, x, y + s); g.quadraticCurveTo(x, y, x - s, y); g.quadraticCurveTo(x, y, x, y - s); g.fillStyle = WHITE; g.fill(); };
    [[-.6, by0 + 1.5, 0], [bx1 + .2, by0 + 3, 1.3], [bx1 - .8, by0 - 1.2, 2.1], [-.2, by1 - 2.5, 3.2], [bx1 + .6, by1 - 3.5, .7]].forEach(([sx, sy, ph]) => spark(X(sx), Y(sy), px * .9 * Math.max(0, Math.sin(t * 5 + ph))));
    // badge
    const bx = X(sp.badge[0]), byy = Y(sp.badge[1]);
    g.font = `800 ${px * 1.15}px ui-rounded, system-ui, sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.beginPath(); if (g.roundRect) g.roundRect(bx - px * 1.35, byy - px * .75, px * 2.7, px * 1.5, px * .45); else g.rect(bx - px * 1.35, byy - px * .75, px * 2.7, px * 1.5);
    g.fillStyle = WHITE; g.fill(); g.fillStyle = INK; g.fillText('HD', bx, byy + px * .06);
    g.restore();
  }

  // ---------- resolution: draw something, then show it at `block` pt per sample, with hard pixel edges ----------
  const pool = {};
  function surface(key, w, h, opts) {
    let c = pool[key];
    if (!c || c.width !== w || c.height !== h) {
      c = typeof OffscreenCanvas !== 'undefined' ? new OffscreenCanvas(w, h) : document.createElement('canvas');
      c.width = w; c.height = h; c._ctx = c.getContext('2d', opts); pool[key] = c;
    }
    return c;
  }
  function atRes(ctx, x, y, w, h, block, draw) {
    const s = Math.hypot(ctx.getTransform().a, ctx.getTransform().b) || 1;
    const hi = surface('hi', Math.ceil(w * s), Math.ceil(h * s)), hg = hi._ctx;
    hg.setTransform(1, 0, 0, 1, 0, 0); hg.clearRect(0, 0, hi.width, hi.height); hg.setTransform(s, 0, 0, s, -x * s, -y * s); draw(hg);
    if (block * s <= 1.01) { ctx.drawImage(hi, x, y, w, h); return; }
    const lw = Math.max(1, Math.round(w / block)), lh = Math.max(1, Math.round(h / block));
    let src = hi, sw = hi.width, sh = hi.height, k = 0;
    while (sw / 2 >= lw && sh / 2 >= lh) {
      const nw = Math.max(lw, Math.round(sw / 2)), nh = Math.max(lh, Math.round(sh / 2)), c = surface('half' + (k++ % 2), nw, nh), cg = c._ctx;
      cg.setTransform(1, 0, 0, 1, 0, 0); cg.clearRect(0, 0, nw, nh); cg.imageSmoothingEnabled = true; cg.drawImage(src, 0, 0, sw, sh, 0, 0, nw, nh);
      src = c; sw = nw; sh = nh;
    }
    const lo = surface('lo', lw, lh, { willReadFrequently: true }), lg = lo._ctx;
    lg.setTransform(1, 0, 0, 1, 0, 0); lg.clearRect(0, 0, lw, lh); lg.imageSmoothingEnabled = true; lg.imageSmoothingQuality = 'high'; lg.drawImage(src, 0, 0, sw, sh, 0, 0, lw, lh);
    const im = lg.getImageData(0, 0, lw, lh), d = im.data;
    for (let i = 3; i < d.length; i += 4) d[i] = d[i] > 96 ? 255 : 0;
    lg.putImageData(im, 0, 0);
    const was = ctx.imageSmoothingEnabled; ctx.imageSmoothingEnabled = false;
    ctx.drawImage(lo, 0, 0, lw, lh, x, y, lw * block, lh * block);
    ctx.imageSmoothingEnabled = was;
  }

  // ---------- states ----------
  const blinkAt = (t, seed = 0) => ((t + seed * .7) % 3.7) < .11;

  function draw(ctx, p) {
    const sp = SPECIES[p.species] || APPLE, W = sp.W, H = sp.H;
    const st = p.state || 'idle', T = p.stateT || 0, t = p.t || 0, px0 = Math.round((p.px || 7) * (sp.pxScale || 1));
    const scr = p.screen || { x: 0, y: 0, w: 198, h: 242 };
    const mood0 = p.palette || sp.moods[st] || sp.base;
    const base = (px, cx = p.cx, cy = p.cy) => ({ sp, ox: Math.round(cx - W * px / 2), oy: Math.round(cy - H * px / 2), px, mood: mood0 });
    const idleBob = Math.floor(t * 1.25) % 2;
    ctx.save();

    if (st === 'idle') {
      const ph = t % 8, look = p.look ?? (ph < 2.6 ? 1 : ph < 5.2 ? -1 : 1);
      const mode = p.eyeMode || (blinkAt(t) ? 'closed' : (ph > 5.2 && ph < 6.5) ? 'cam' : 'side');
      paint(ctx, { ...base(px0), dy: p.eyeMode ? 0 : idleBob, eyes: { mode, look } });
    }

    else if (st === 'listening') {
      const v = clamp01(p.voice ?? (.5 + .5 * Math.sin(t * 9) * Math.sin(t * 2.3)));
      const px = px0 + 1, o = { ...base(px), stem: 'antenna', boost: v * .05, eyes: { mode: blinkAt(t) ? 'closed' : 'cam' } };
      paint(ctx, o);
      // the stem is an antenna: ((( · ))) like a broadcast icon, one arc per loudness step
      const c = Math.max(3, Math.round(px * .5)), tipx = o.ox + sp.tip[0] * px, tipy = o.oy + sp.tip[1] * px, n = Math.ceil(v * 3);
      ctx.fillStyle = WHITE;
      for (let i = 0; i < n; i++) {
        ctx.globalAlpha = 1 - i * .22;
        const hh = i + 1;
        for (let j = -hh; j <= hh; j++) for (const side of [-1, 1]) {
          const dx = (2 * i + 2.2 - (Math.abs(j) === hh ? 1 : 0)) * c * side;
          ctx.fillRect(Math.round(tipx + dx - c / 2), Math.round(tipy + j * c - c / 2), c, c);
        }
      }
      ctx.globalAlpha = 1;
    }

    else if (st === 'thinking') {
      const c = T % 4.6, block = c < .45 ? 1 : c < 1.3 ? 2 : c < 2.4 ? 3 : c < 4.0 ? 4 : 1;
      const lk = Math.floor(T / 1.15) % 2 ? -1 : 1;
      const o = { ...base(px0), eyes: { mode: 'up', look: lk } };
      if (block === 1) paint(ctx, { ...o, eyes: { mode: c >= 4.0 ? 'cam' : 'up', look: lk } });
      else { atRes(ctx, o.ox, o.oy, W * o.px, H * o.px, o.px * block, g => paint(g, { ...o, eyes: { mode: 'none' } })); eyes(ctx, o, y => y); }
    }

    else if (st === 'working') {
      const stepI = Math.floor(T / .2), legs = stepI % 2 ? 'stepL' : 'stepR';
      const o = { ...base(px0), legs, dy: stepI % 2, eyes: { mode: blinkAt(t) ? 'closed' : 'squint', look: 1 } };
      paint(ctx, o);
      const tools = (p.tools && p.tools.length ? p.tools : ['Read', 'Edit', 'Bash', 'Grep', 'Edit', 'Test']).map(s => String(s).toUpperCase());
      const every = .75, k0 = Math.floor(T / every);
      for (let k = Math.max(0, k0 - 2); k <= k0; k++) {
        const age = T - k * every; if (age < 0 || age > 1.5) continue;
        const label = '+1 ' + tools[k % tools.length], rise = step(age / 1.5, 10) * Math.max(8, Math.min(34, o.oy - 20 - scr.y));
        const x = o.ox + W * o.px / 2 + (k % 2 ? 30 : -30), y = o.oy - 14 - rise;
        ctx.globalAlpha = age > 1.1 ? .5 : 1;
        text(ctx, label, x + 1, y + 1, 2, 'rgba(120,40,0,.9)', 'center'); text(ctx, label, x, y, 2, '#FFE66B', 'center');
      }
      ctx.globalAlpha = 1;
      if (stepI % 4 === 1) { ctx.fillStyle = '#8FD8FF'; const sx = o.ox + W * o.px + 2, sy = o.oy + 5 * o.px; ctx.fillRect(sx, sy, 3, 3); ctx.fillRect(sx, sy + 3, 2, 2); }
    }

    else if (st === 'speaking') {
      const msg = (p.text || 'All 14 tests pass. I also fixed a typo you made in 2019.').toUpperCase();
      const bx = scr.x + 8, bw = scr.w - 16, bh = 82, by = scr.y + scr.h - bh - 8, cpl = Math.floor((bw - 18) / 8);
      const lines = []; let line = '';
      for (const w of msg.split(' ')) { if ((line + ' ' + w).trim().length > cpl) { lines.push(line.trim()); line = w; } else line += ' ' + w; }
      if (line.trim()) lines.push(line.trim());
      const shown = Math.floor(T * 22); let left = shown;
      const typed = lines.map(l => { const n = Math.max(0, Math.min(l.length, left)); left -= l.length; return l.slice(0, n); });
      const doneTyping = shown >= lines.join('').length;
      const lastCh = (typed.filter(Boolean).pop() || ' ').slice(-1);
      const mouth = doneTyping ? 0 : (/[AEIOU]/.test(lastCh) ? 2 : Math.floor(T * 11) % 2);
      const px = Math.round(5 * (sp.pxScale || 1)), o = { ...base(px, scr.x + scr.w / 2, by - H * px / 2 - 8), dy: doneTyping ? idleBob : Math.floor(T * 6) % 2, mouth, eyes: { mode: blinkAt(t) ? 'closed' : 'cam' } };
      paint(ctx, o);
      ctx.fillStyle = '#0D0D1A'; ctx.fillRect(bx, by, bw, bh);
      ctx.fillStyle = WHITE; ctx.fillRect(bx, by, bw, 2); ctx.fillRect(bx, by + bh - 2, bw, 2); ctx.fillRect(bx, by, 2, bh); ctx.fillRect(bx + bw - 2, by, 2, bh);
      ctx.fillStyle = '#5B5BFF'; ctx.fillRect(bx + 4, by + 4, bw - 8, 1); ctx.fillRect(bx + 4, by + bh - 5, bw - 8, 1);
      const tw = textWidth(sp.name, 2) + 12, ty = by - 15; ctx.fillStyle = '#0D0D1A'; ctx.fillRect(bx + 10, ty, tw, 17);
      ctx.fillStyle = WHITE; ctx.fillRect(bx + 10, ty, tw, 2); ctx.fillRect(bx + 10, ty, 2, 17); ctx.fillRect(bx + 10 + tw - 2, ty, 2, 17);
      text(ctx, sp.name, bx + 16, ty + 5, 2, '#FFE66B');
      typed.slice(0, 5).forEach((l, i) => text(ctx, l, bx + 9, by + 12 + i * 13, 2, WHITE));
      if (doneTyping && Math.floor(t * 2.5) % 2) { ctx.fillStyle = WHITE; const ax = bx + bw - 16, ay = by + bh - 14; ctx.fillRect(ax, ay, 8, 2); ctx.fillRect(ax + 2, ay + 2, 4, 2); ctx.fillRect(ax + 3, ay + 4, 2, 2); }
    }

    else if (st === 'done') {
      const c = T % 4.2, o = { ...base(px0), mood: sp.base };
      const up = [.14, .23, .32, .41], down = [2.55, 2.62, 2.69, 2.76], blocks = [1, .5, .25, .125];
      const region = (g, b) => atRes(ctx, o.ox - o.px, o.oy - 3 * o.px, (W + 2) * o.px, (H + 3) * o.px, o.px * b, g);
      if (c < .14) paint(ctx, { ...o, dy: -1, eyes: { mode: 'happy' } });
      else if (c < .5) { const i = up.findIndex(v => c < v + .09); region(g => paintHD(g, o, t), blocks[Math.max(0, i)]); }
      else if (c < 2.55) paintHD(ctx, { ...o, by: Math.sin((c - .5) * 3.2) * 2.2 }, t);
      else if (c < 2.83) { const i = down.findIndex(v => c < v + .07); region(g => paintHD(g, o, t), blocks[3 - Math.max(0, i)]); }
      else paint(ctx, { ...o, dy: idleBob, eyes: { mode: c < 3.4 ? 'happy' : 'side', look: 1 } });
    }

    else if (st === 'needs') {
      const lean = Math.max(0, Math.min(3, Math.floor((p.room || 172) / H) - px0, Math.floor(Math.max(0, T - 1.4) / 1.4)));
      const px = px0 + lean, hop = T < .26 ? -Math.round(Math.sin(T / .26 * Math.PI) * 2) : 0;
      const o = { ...base(px, p.cx, p.cy + lean * 4), dy: hop, eyes: { mode: blinkAt(t, 2) && T > 1 ? 'closed' : 'cam' } };
      paint(ctx, o);
      if (p.bang === false) { ctx.restore(); return; }
      const pop = T < .1 ? T / .1 : 1, bob = Math.floor(t * 2) % 2, s = Math.max(2, Math.round(px * .62 * pop));
      const ex = o.ox + sp.bangX * px - s, ey = o.oy - 1.5 * px + hop * px - bob * 2 - 7 * s;
      ctx.fillStyle = WHITE; ctx.fillRect(ex - s / 2, ey - s / 2, s * 3, s * 5.5); ctx.fillRect(ex - s / 2, ey + 5.5 * s, s * 3, s * 2.5);
      ctx.fillStyle = '#FF3B30'; ctx.fillRect(ex, ey, s * 2, s * 4.5); ctx.fillRect(ex, ey + 6 * s, s * 2, s * 1.5);
    }

    else if (st === 'blocked') {
      // dragged around like a frozen window: a stamp every frame, 15 pt apart, each one a bit more overripe
      const c = T % 6.5, px = Math.max(3, Math.round(4 * (sp.pxScale || 1))), frames = Math.min(Math.floor(c * 9), 26);
      const P = [[62, 96], [136, 104], [70, 160], [138, 178]].map(([x, y]) => [scr.x + x * scr.w / 198, scr.y + y * scr.h / 242]);
      const seg = []; let tot = 0; for (let i = 1; i < P.length; i++) { const l = Math.hypot(P[i][0] - P[i - 1][0], P[i][1] - P[i - 1][1]); seg.push(l); tot += l; }
      const path = k => { let d = Math.min(tot, k * 15); for (let i = 0; i < seg.length; i++) { if (d <= seg[i]) { const f = d / seg[i]; return [P[i][0] + (P[i + 1][0] - P[i][0]) * f, P[i][1] + (P[i + 1][1] - P[i][1]) * f]; } d -= seg[i]; } return P[P.length - 1]; };
      for (let k = 0; k <= frames; k++) {
        const [cx, cy] = path(k), age = k / 26;
        paint(ctx, { ...base(px, cx, cy), mood: sp.base, stem: k > 13 ? 'droop' : 'curl', rot: sp.key === 'apple' ? age * .85 : age * .3, spots: sp.key === 'banana' ? age : 0, eyes: { mode: 'side', look: 1 } });
      }
      text(ctx, 'NOT RESPONDING', scr.x + scr.w / 2, scr.y + 18, 2, Math.floor(t * 1.6) % 2 ? WHITE : '#9AA1AA', 'center');
    }

    else if (st === 'dizzy') {
      const c = T % 3.4, seed = 11;
      const scatter = c < .45 ? ease(c / .45) : c < 1.0 ? 1 - ease((c - .45) / .55) : 0;
      const flip = c >= .72 && c < 2.3;
      const offset = scatter > 0 ? (x, y) => { const a = hash(x, y, seed) * Math.PI * 2, r = (2 + hash(y, x, seed) * 5) * scatter; return [Math.round(Math.cos(a) * r), Math.round(Math.sin(a) * r)]; } : null;
      const look = Math.floor(t * 8) % 2 ? 1 : -1;
      const eyesMode = c < 1.0 ? 'cross' : flip ? (c > 1.6 && c < 1.75 ? 'closed' : 'side') : c < 2.9 ? 'cross' : 'side';
      if (c >= 2.3 && c < 2.42) {
        const o = base(px0); ctx.save(); ctx.translate(0, p.cy); ctx.scale(1, .45); ctx.translate(0, -p.cy);
        paint(ctx, { ...o, eyes: { mode: 'closed' } }); ctx.restore();
      } else paint(ctx, { ...base(px0), flip, offset, eyes: { mode: eyesMode, look } });
    }

    else if (st === 'compacting') {
      // the context is being compacted, so it is: squashed flat under a press, its pixels JPEG'd into blocks
      const c = T % 2.4, squeeze = .56 + .05 * Math.sin(c / 2.4 * Math.PI * 2) - Math.min(.1, T * .12);
      const o = base(px0), bottom = o.oy + H * px0;
      ctx.save(); ctx.translate(p.cx, bottom); ctx.scale(1 + (1 - squeeze) * .4, squeeze); ctx.translate(-p.cx, -bottom);
      atRes(ctx, o.ox - px0 * 2, o.oy - px0, (W + 4) * px0, (H + 1) * px0, px0 * 2, g => paint(g, { ...o, eyes: { mode: 'none' } }));
      eyes(ctx, { ...o, eyes: { mode: 'cam' } }, y => y);
      ctx.restore();
      // the press rests on its head
      const top = bottom - H * px0 * squeeze - 3, plateW = scr.w - 24;
      ctx.fillStyle = '#3A3F46'; ctx.fillRect(scr.x + 12, top - 9, plateW, 9);
      ctx.fillStyle = '#5A6069'; ctx.fillRect(scr.x + 12, top - 9, plateW, 2);
      ctx.fillStyle = '#2A2E33'; ctx.fillRect(scr.x + scr.w / 2 - 3, scr.y, 6, top - 9 - scr.y);
      const pct = 40 + Math.floor(T * 9) % 50;
      text(ctx, `-${pct}%`, scr.x + scr.w - 16, top - 22, 2, '#FFE66B', 'right');
    }

    else if (st === 'waiting') {
      // rate limited: it waits, tapping a foot under an hourglass, and keeps looking up at the clock
      const ph = T % 4, clock = ph > 1.2 && ph < 2.6;
      const o = { ...base(px0), legs: Math.floor(T * 2.2) % 2 ? 'stepR' : 'stand', dy: 0,
        eyes: { mode: clock ? 'up' : blinkAt(t) ? 'closed' : 'squint', look: 1 } };
      paint(ctx, o);
      // the hourglass: 5 x 7 pixels, sand running down, turned over every 3 s
      const hp = Math.max(2, Math.round(px0 * .55)), hx = o.ox + (W + 1) * px0, hy = o.oy + 2 * px0;
      const run = (T % 3) / 3, flip = (T % 3) > 2.8;
      const GL = ['XXXXX', '.X.X.', '..X..', '..X..', '.X.X.', 'X...X', 'XXXXX'];
      ctx.save(); if (flip) { ctx.translate(hx + 2.5 * hp, hy + 3.5 * hp); ctx.rotate(Math.PI / 2); ctx.translate(-(hx + 2.5 * hp), -(hy + 3.5 * hp)); }
      ctx.fillStyle = '#C9CDD2'; GL.forEach((r, j) => [...r].forEach((ch, i) => { if (ch === 'X') ctx.fillRect(hx + i * hp, hy + j * hp, hp, hp); }));
      ctx.fillStyle = '#FFD23F';
      const topN = Math.round((1 - run) * 3), botN = Math.round(run * 3);
      if (topN > 0) ctx.fillRect(hx + hp, hy + hp, 3 * hp, hp * Math.min(1, topN));
      if (topN > 1) ctx.fillRect(hx + 2 * hp, hy + 2 * hp, hp, hp);
      if (Math.floor(T * 6) % 2) ctx.fillRect(hx + 2 * hp, hy + 3 * hp, hp, hp);
      if (botN > 0) ctx.fillRect(hx + hp, hy + 5 * hp, 3 * hp, hp);
      if (botN > 1) ctx.fillRect(hx + 2 * hp, hy + 4 * hp, hp, hp);
      ctx.restore();
      const left = Math.max(0, 33 * 60 - 1 - Math.floor(T)), mm = String(Math.floor(left / 60)).padStart(2, '0'), ss = String(left % 60).padStart(2, '0');
      text(ctx, `BACK IN ${mm}:${ss}`, scr.x + scr.w / 2, o.oy + H * px0 + 10, 2, '#9AA1AA', 'center');
    }

    else if (st === 'sleep') {
      const px = 4, sw = W * px, sh = H * px, m = 6, rx = scr.w - 2 * m - sw, ry = scr.h - 2 * m - sh;
      const vx = rx / 2.5, vy = ry / 3.75, TT = T + 1.2;                       // first corner hit at T = 6.3 s
      const tri = (d, r) => { const n = Math.floor(d / r), f = d - n * r; return [n % 2 ? r - f : f, n]; };
      const [x, nx] = tri(TT * vx, rx), [y, ny] = tri(TT * vy, ry);
      const corner = []; for (let k = 1; k < 8; k++) { const tc = 7.5 * k - 1.2; if (T >= tc && T - tc < 1.6) corner.push(T - tc); }
      const o = { sp, ox: Math.round(scr.x + m + x), oy: Math.round(scr.y + m + y), px, mood: sp.cycle[(nx + ny) % sp.cycle.length], eyes: { mode: corner.length && corner[0] < .9 ? 'cam' : 'closed' }, stem: 'droop', boost: -.06 };
      paint(ctx, o);
      if (corner.length) {                                                       // it hit the corner. Everyone has waited years for this.
        const a = corner[0];
        for (let i = 0; i < 26; i++) {
          const ang = hash(i, 3, 1) * Math.PI * 2, spd = 30 + hash(i, 9, 2) * 70, r0 = 22;
          const gx = o.ox + sw / 2 + Math.cos(ang) * (r0 + spd * a), gy = o.oy + sh / 2 + Math.sin(ang) * (r0 + spd * a) + 40 * a * a;
          ctx.fillStyle = css(grad(LAB[sp.cycle[i % sp.cycle.length]], .3)); ctx.fillRect(Math.round(gx), Math.round(gy), 4, 4);
        }
        text(ctx, 'CORNER!', scr.x + scr.w / 2, scr.y + scr.h / 2 - 6, 3, Math.floor(a * 8) % 2 ? WHITE : '#FFE66B', 'center');
      } else {
        const zt = T % 1.4;
        ctx.globalAlpha = 1 - zt / 1.4; text(ctx, 'z', o.ox + sw - 2, o.oy - 4 - step(zt / 1.4, 6) * 16, 2, WHITE); ctx.globalAlpha = 1;
      }
    }

    else if (st === 'subagents') {
      const n = Math.max(1, Math.min(5, p.subagents ?? 3)), all = n + 1, c = T, o = base(px0);
      if (c < .5) {
        const jit = Math.floor(c * 24) % 2 ? 1 : -1;
        paint(ctx, { ...o, ox: o.ox + (c > .2 ? jit : 0), eyes: { mode: c > .2 ? 'cam' : 'side', look: 1 } });
      } else {
        const k = ease((c - .5) / .45), gap = (scr.w - 16) / all, mpx = Math.max(2, Math.min(4, Math.floor(gap / ((sp.visW || W) + 1))));
        for (let i = 0; i < all; i++) {
          const qx = o.ox + ((i % 2) + .5) * W * px0 / 2, qy = o.oy + (Math.floor(i / 2) % 2 + .5) * H * px0 / 2;
          const fx = scr.x + scr.w / 2 + (i - (all - 1) / 2) * gap, fy = p.cy + 16;
          const cx = Math.round(qx + (fx - qx) * k), cy = Math.round(qy + (fy - qy) * k);
          const walk = Math.floor((c * 5) + i * .5) % 2;
          paint(ctx, { ...base(mpx, cx, cy), mood: sp.cycle[i % sp.cycle.length], legs: k >= 1 ? (walk ? 'stepL' : 'stepR') : 'stand', dy: k >= 1 ? walk : 0, eyes: { mode: blinkAt(t, i) ? 'closed' : 'side', look: i === 0 ? 1 : -1 } });
        }
        if (k >= 1) text(ctx, 'X' + all, scr.x + scr.w / 2, p.cy - 36, 2, '#FFE66B', 'center');
      }
    }

    ctx.restore();
  }

  root.PIX = { draw, paint, paintHD, text, SPECIES, PAL, STATES: ['idle', 'listening', 'thinking', 'compacting', 'working', 'subagents', 'speaking', 'done', 'needs', 'waiting', 'blocked', 'dizzy', 'sleep'] };
})(typeof window !== 'undefined' ? window : globalThis);
