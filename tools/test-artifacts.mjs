// Artifacts: each kind of file a session shows (chums_show's file, through /channel/artifact) or you send from the
// iPhone (/v1/upload) becomes a picture the watch fetches, and keeps what the iPhone opens (meta.view, /source, /view).
// The files are made here, in the private hub's temporary home. node tools/test-artifacts.mjs
import path from 'node:path'
import fs from 'node:fs'
import { spawnSync } from 'node:child_process'
import { startPrivateHub } from './test-hub-private.mjs'
import { markdown } from '../hub/render.mjs'

let fails = 0; const ok = (c, m) => { console.log(c ? 'PASS' : 'FAIL', m); if (!c) fails++ }

// ---------- Markdown, converted (no hub needed) ----------
const md = markdown([
  '# Title', '', 'Some **bold**, _em_ and `a <b> code`, a [link](https://example.com) and ![a chart](https://example.com/c.png).',
  'snake_case_stays <script>alert(1)</script><img src="https://example.com/x.png" alt="Logo"> <https://example.com/auto>', '',
  '1. one', '2. two', '   - nested', '', '- [x] done', '', '> quoted', '', '| a | b |', '| - | -: |', '| 1 | 2 |', '',
  '```', 'if (a < b) {}', '```', '', '---', '', 'Underlined', '==========',
].join('\n'))
ok(/<h1>Title<\/h1>/.test(md) && /<strong>bold<\/strong>/.test(md) && /<em>em<\/em>/.test(md) && /<code>a &lt;b&gt; code<\/code>/.test(md),
   'Markdown: a heading, emphasis and inline code (escaped)')
ok(/<span class="link">link<\/span>/.test(md) && /Image: a chart/.test(md) && /Image: Logo/.test(md) && /https:\/\/example\.com\/auto/.test(md),
   'links and images become their text')
ok(!/<(script|img|a)\b|\bhref=|\bsrc=/.test(md) && /snake_case_stays/.test(md), 'nothing in it loads or links; raw HTML is dropped, words with _ stay whole')
ok(/<ol><li>one<\/li><li>two<ul><li>nested<\/li><\/ul><\/li><\/ol>/.test(md) && /☑/.test(md), 'lists, nested, and a task list')
ok(/<blockquote><p>quoted<\/p><\/blockquote>/.test(md) && /<table><tr><th>a<\/th><th style="text-align:right">b<\/th><\/tr><tr><td>1<\/td>/.test(md),
   'a block quote and a table')
ok(/<pre><code>if \(a &lt; b\) \{\}<\/code><\/pre>/.test(md) && /<hr>/.test(md) && /<h1>Underlined<\/h1>/.test(md), 'a code block, a rule, an underlined heading')

// ---------- the files ----------
const { cfg, home, stop } = await startPrivateHub()
const H = `http://127.0.0.1:${cfg.port}`, P = `http://127.0.0.1:${cfg.publicPort}`
const call = async (pathname, body) => {
  const r = await fetch(H + pathname, { method: 'POST', headers: { authorization: `Bearer ${cfg.token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) })
  return { status: r.status, body: await r.json().catch(() => null) }
}
const get = (pathname, headers = {}, token = cfg.watchToken) => fetch(P + pathname, { headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers } })
const sid = 'artifacts-' + Date.now()
await call('/channel/register', { sessionId: sid, name: 'artifacts', cwd: '/tmp/artifacts' })

const fx = path.join(home, 'files')
fs.mkdirSync(fx)
const at = f => path.join(fx, f)
/// A PDF of `n` US Letter pages, each with its number in Helvetica and an orange band at the top.
function makePDF(file, n) {
  const objs = ['', '<< /Type /Catalog /Pages 2 0 R >>', '', '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
  const pages = Array.from({ length: n }, (_, i) => 4 + i * 2)
  objs[2] = `<< /Type /Pages /Kids [${pages.map(p => `${p} 0 R`).join(' ')}] /Count ${n} >>`
  pages.forEach((p, i) => {
    const s = `0.85 0.47 0.34 rg 0 672 612 120 re f 0 g BT /F1 64 Tf 72 500 Td (Page ${i + 1}) Tj ET`
    objs[p] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${p + 1} 0 R >>`
    objs[p + 1] = `<< /Length ${s.length} >>\nstream\n${s}\nendstream`
  })
  let out = '%PDF-1.4\n'
  const offsets = objs.map((o, i) => { if (!i) return 0; const at = out.length; out += `${i} 0 obj\n${o}\nendobj\n`; return at })
  const xref = out.length
  out += `xref\n0 ${objs.length}\n0000000000 65535 f \n${offsets.slice(1).map(o => `${String(o).padStart(10, '0')} 00000 n \n`).join('')}`
  fs.writeFileSync(file, out + `trailer\n<< /Size ${objs.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`)
}
makePDF(at('three.pdf'), 3)
fs.writeFileSync(at('notes.md'), '# Notes\n\nA paragraph with **bold** text.\n\n- one\n- two\n\n```\ncode\n```\n')
fs.writeFileSync(at('long.txt'), Array.from({ length: 500 }, (_, i) => `line ${i + 1}: ${'word '.repeat(i % 7)}`).join('\n') + '\n')
fs.writeFileSync(at('people.csv'), 'id,name,"city, country"\n' + Array.from({ length: 300 }, (_, i) => `${i + 1},Person ${i + 1},"Lisbon, ""PT"""`).join('\n') + '\n')
fs.writeFileSync(at('page.html'), '<!doctype html><meta name=viewport content="width=device-width"><body style="background:#123;color:#fff"><h1 id=h>Static</h1><script>h.textContent = "Ran"</script>')
fs.writeFileSync(at('blob.bin'), Buffer.from(Array.from({ length: 4096 }, (_, i) => (i * 37) & 0xff)))
fs.writeFileSync(at('data'), '{"a":1}\n')                           // no extension, but UTF-8 text
spawnSync('/usr/bin/textutil', ['-convert', 'docx', at('long.txt'), '-output', at('letter.docx')])
spawnSync('/usr/bin/textutil', ['-convert', 'rtf', at('notes.md'), '-output', at('notes.rtf')])
const ffmpeg = ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg', ...(process.env.PATH ?? '').split(':').map(d => path.join(d, 'ffmpeg'))].find(f => fs.existsSync(f))
if (ffmpeg) spawnSync(ffmpeg, ['-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=2:size=320x240:rate=10', '-pix_fmt', 'yuv420p', '-y', at('clip.mov')])

// each one, shown by a session: its kind, its picture, its title, and what the iPhone gets
const cases = [
  // file, kind, view.type, view.file, a check of the title, a check of the picture
  ['three.pdf', 'pdf', 'pdf', 'source.pdf', t => t === 'three.pdf', a => a.w === 1200 && a.h > 2 * a.w * 792 / 612, 'all 3 pages, stacked'],
  ['notes.md', 'doc', 'html', 'view.html', t => t === 'notes.md', a => a.w === 780, 'rendered at phone width'],
  ['long.txt', 'text', 'text', 'view.html', t => /^long\.txt, first \d+ lines of 500$/.test(t), a => a.w === 780 && a.h > 4000, 'the first lines that fit'],
  ['people.csv', 'table', 'html', 'view.html', t => t === 'people.csv, first 200 rows of 300', a => a.w >= 780 && a.h > 3000, 'a table of the first 200 rows'],
  ['page.html', 'page', 'html', 'source.html', t => t === 'page.html', a => a.w === 780, 'rendered at phone width'],
  ['letter.docx', 'doc', 'doc', 'source.docx', t => t === 'letter.docx', a => a.w > 500 && a.h > 500, "Quick Look's picture"],
  ['notes.rtf', 'doc', 'doc', 'source.rtf', t => t === 'notes.rtf', a => a.w > 500, "Quick Look's picture, not its text"],
  ['data', 'text', 'text', 'view.html', t => t === 'data', a => a.w === 780, 'UTF-8 text without an extension'],
  ...(ffmpeg ? [['clip.mov', 'video', 'video', 'source.mov', t => t === 'clip.mov, a still at 0:01', a => a.w === 320 && a.h === 240, 'a still from a second in']] : []),
]
if (!ffmpeg) console.log('SKIP the video checks: no ffmpeg on this Mac (brew install ffmpeg)')
const shown = {}
for (const [file, kind, type, served, titleOK, pictureOK, what] of cases) {
  const t0 = Date.now()
  const r = await call('/channel/artifact', { sessionId: sid, file: at(file) })
  const a = r.body ?? {}, ms = Date.now() - t0
  const full = await get(`/v1/artifact/${a.id}/full`), jpeg = Buffer.from(await full.arrayBuffer())
  const sane = a.w > 0 && a.h > 0 && a.w <= 1200 && a.w * a.h <= 10_000_000 && jpeg[0] === 0xFF && jpeg[1] === 0xD8
  ok(r.status === 200 && a.kind === kind && titleOK(a.title) && sane && pictureOK(a),
     `${file}: ${kind}, ${what} ("${a.title}", ${a.w}×${a.h}, ${ms} ms)${r.status !== 200 ? ` ${JSON.stringify(r.body)}` : ''}`)
  const size = fs.statSync(at(file)).size
  ok(a.view?.type === type && a.view.file === served && a.view.name === file && a.view.ext === path.extname(file).slice(1) && a.view.size === size && a.view.source === true,
     `${file}: meta.view ${JSON.stringify(a.view)}`)
  shown[file] = a
}
ok((await call('/channel/artifact', { sessionId: sid, file: at('blob.bin') })).status === 422, 'a file with no picture (binary, unknown to Quick Look) is refused with a reason')
ok((await call('/channel/artifact', { sessionId: sid, file: at('nothing.pdf') })).status === 422, 'so is a file that isn\'t there')
const again = Date.now(), second = await call('/channel/artifact', { sessionId: sid, file: at('three.pdf') })
console.log(`     (the PDF again, its helper compiled: ${Date.now() - again} ms)`)
ok(second.body?.id !== shown['three.pdf'].id, 'each showing is its own artifact')

// a PDF longer than one picture holds: the title says which pages it shows
makePDF(at('long.pdf'), 14)
const long = (await call('/channel/artifact', { sessionId: sid, file: at('long.pdf') })).body
ok(/^long\.pdf, pages 1–\d of 14$/.test(long?.title ?? '') && long.w >= 900 && long.w * long.h <= 10_000_000, `a 14-page PDF: "${long?.title}" (${long?.w}×${long?.h})`)

// what the state carries: the line, with the artifact's view
const line = (await (await get('/v1/state?since=0')).json()).spoken.find(l => l.artifact?.id === shown['notes.md'].id)
ok(line?.artifact?.view?.type === 'html' && line.artifact.view.file === 'view.html', "the conversation's line carries meta.view")

// ---------- the routes ----------
const pdf = shown['three.pdf'], pdfBytes = fs.readFileSync(at('three.pdf'))
const src = await get(`/v1/artifact/${pdf.id}/source`), body = Buffer.from(await src.arrayBuffer())
ok(src.status === 200 && src.headers.get('content-type') === 'application/pdf' && body.equals(pdfBytes) &&
   /filename="three\.pdf"/.test(src.headers.get('content-disposition') ?? '') && src.headers.get('accept-ranges') === 'bytes',
   '/source: the original, its type and file name')
const part = await get(`/v1/artifact/${pdf.id}/source`, { range: 'bytes=10-19' }), partBytes = Buffer.from(await part.arrayBuffer())
ok(part.status === 206 && part.headers.get('content-range') === `bytes 10-19/${pdfBytes.length}` && partBytes.equals(pdfBytes.subarray(10, 20)),
   'a range: 206 with those bytes')
const tail = await get(`/v1/artifact/${pdf.id}/source`, { range: 'bytes=-7' })
ok(tail.status === 206 && Buffer.from(await tail.arrayBuffer()).equals(pdfBytes.subarray(-7)), 'the last bytes: 206 with those')
ok((await get(`/v1/artifact/${pdf.id}/source`, { range: `bytes=${pdfBytes.length}-` })).status === 416, 'a range past the end: 416')
ok((await get(`/v1/artifact/${pdf.id}/view`)).headers.get('content-type') === 'application/pdf', '/view of a PDF: the PDF (no page of the hub\'s)')
const view = await get(`/v1/artifact/${shown['notes.md'].id}/view`), html = await view.text()
ok(view.status === 200 && view.headers.get('content-type') === 'text/html; charset=utf-8' && /default-src 'none'/.test(html) && /<h1>Notes<\/h1>/.test(html) &&
   /sandbox/.test(view.headers.get('content-security-policy') ?? ''), "/view of Markdown: the hub's page, loading nothing, sandboxed")
ok((await (await get(`/v1/artifact/${shown['notes.md'].id}/source`)).text()) === fs.readFileSync(at('notes.md'), 'utf8'), '/source of Markdown: the Markdown')
const page = await get(`/v1/artifact/${shown['page.html'].id}/view`)
ok(/sandbox allow-scripts/.test(page.headers.get('content-security-policy') ?? '') && (await page.text()).includes('h.textContent'), "/view of an agent's page: the page, its scripts allowed, in an origin of its own")
const vid = shown['clip.mov']
if (vid) {
  const v = await get(`/v1/artifact/${vid.id}/source`, { range: 'bytes=0-1' })
  ok(v.status === 206 && v.headers.get('content-type') === 'video/quicktime' && (await v.arrayBuffer()).byteLength === 2, 'a video: its type, and the two-byte range a player asks for first')
}
ok((await get(`/v1/artifact/${pdf.id}/source`, {}, null)).status === 401, 'not without a token')
ok((await get(`/v1/artifact/${pdf.id}/source`, {}, cfg.token)).status === 401, 'not with the local token on the public door')
ok((await get('/v1/artifact/0123456789ab/source')).status === 404 && (await get('/v1/artifact/0123456789ab/view')).status === 404, 'an id that isn\'t there: 404')
for (const p of [`/v1/artifact/..%2F..%2Fconfig.json/source`, `/v1/artifact/${pdf.id}%2F..%2F..%2Fconfig.json/source`, `/v1/artifact/${pdf.id}/../../config.json`,
                 `/v1/artifact/${pdf.id}/meta.json`, `/v1/artifact/${pdf.id}/source.pdf`, `/v1/artifact/${pdf.id}0/source`]) {
  const r = await get(p), text = await r.text()
  ok(r.status === 404 && !text.includes(cfg.token) && !text.includes('%PDF'), `a path in the id is refused: ${p.replace(pdf.id, '<id>')} (${r.status})`)
}

// ---------- uploads from the iPhone: the same, with the name it was sent with ----------
const put = (name, file) => fetch(`${P}/v1/upload?name=${encodeURIComponent(name)}`, { method: 'POST', headers: { authorization: `Bearer ${cfg.watchToken}` }, body: fs.readFileSync(file) })
for (const [name, file, kind] of [['My notes.md', 'notes.md', 'doc'], ['scan.pdf', 'three.pdf', 'pdf'], ['report.docx', 'letter.docx', 'doc'],
  ['log.txt', 'long.txt', 'text'], ['people.csv', 'people.csv', 'table'], ...(ffmpeg ? [['clip.mov', 'clip.mov', 'video']] : [])]) {
  const t0 = Date.now(), up = await (await put(name, at(file))).json(), a = up.artifact
  const back = a && Buffer.from(await (await get(`/v1/artifact/${a.id}/source`)).arrayBuffer())
  ok(a?.kind === kind && a.view?.name === up.name && a.view.source && back?.equals(fs.readFileSync(at(file))) && fs.existsSync(path.join(home, '.chums/artifacts', a.id, 'full.jpg')),
     `upload ${name}: ${a?.kind} "${a?.title}" ${a?.w}×${a?.h}, its original kept (${Date.now() - t0} ms)`)
}
const bin = await (await put('blob.bin', at('blob.bin'))).json()
ok(bin.path && bin.artifact === null, 'an upload with no picture is just the file')

console.log(fails ? `${fails} FAILED` : 'all passed'); stop(); process.exit(fails ? 1 : 0)
