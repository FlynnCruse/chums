// Markdown, text and tables as HTML pages, dark like the iPhone's card: what the hub turns into pictures for the watch
// (tools/page-shot.swift) and keeps as view.html for the iPhone. Everything from the file is escaped, and a page loads
// nothing: links are their text, images their description, raw HTML is dropped, and its policy allows no fetch at all.
// The hub runs it as its own process, with a time limit, so a large or odd file never holds up the hub:
//   node hub/render.mjs markdown|text|table <file> <dir> <title>
// It writes <dir>/view.html (for the iPhone) and, when the picture shows less, <dir>/shot.html, and prints what the
// hub needs as JSON: { shot: the page to render, note: what the title adds when the picture shows all of it, cutNote:
// what it adds when the picture is cut, maxWidth: how wide page-shot may widen it }.
import fs from 'node:fs'
import path from 'node:path'
import { StringDecoder } from 'node:string_decoder'

export const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])
const count = n => n.toLocaleString('en-US')

const STYLE = `
:root { color-scheme: dark }
html, body { background: #000 }
body { margin: 0; padding: 20px 18px 28px; color: #e8e8ea; font: 16px/1.5 -apple-system, system-ui, sans-serif;
  -webkit-text-size-adjust: 100%; overflow-wrap: break-word }
h1, h2, h3, h4, h5, h6 { color: #fff; line-height: 1.25; margin: 1.3em 0 .5em }
h1 { font-size: 1.6em } h2 { font-size: 1.35em } h3 { font-size: 1.15em } h4, h5, h6 { font-size: 1em }
body > :first-child { margin-top: 0 }
p, ul, ol, blockquote, pre, table, .front { margin: 0 0 .9em }
ul, ol { padding-left: 1.4em } li { margin: .2em 0 } li > ul, li > ol { margin: .2em 0 }
.link { color: #6cb6ff } .img { color: #8e8e93; font-style: italic } .box { color: #8e8e93 }
code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace }
code { font-size: .86em; background: #1c1c1e; border-radius: 5px; padding: .1em .35em }
pre { font-size: 13px; line-height: 1.45; background: #1c1c1e; border-radius: 10px; padding: 12px 14px;
  white-space: pre-wrap; overflow-wrap: anywhere }
pre code { background: none; padding: 0; font-size: 1em }
blockquote { padding-left: 14px; border-left: 3px solid #3a3a3c; color: #b4b4b8; margin-left: 0 }
hr { border: 0; border-top: 1px solid #3a3a3c; margin: 1.4em 0 }
table { border-collapse: collapse; font-size: 14px }
th, td { border: 1px solid #3a3a3c; padding: 6px 9px; text-align: left; vertical-align: top }
th { background: #1c1c1e; color: #fff; font-weight: 600 }
td.n { text-align: right; font-variant-numeric: tabular-nums }
.front { font-size: 12px; color: #8e8e93 }
.note { color: #8e8e93; font-size: 13px; margin-top: 14px }
body.text { padding: 14px 12px 20px; font: 11px/15px ui-monospace, "SF Mono", Menlo, monospace }
body.text .l { white-space: pre-wrap; overflow-wrap: anywhere; padding-left: 2ch; text-indent: -2ch }
body.text .note { font-family: -apple-system, system-ui, sans-serif }
body.table { padding: 14px 12px 20px }
body.table table.cut td, body.table table.cut th { white-space: nowrap; padding: 4px 8px; line-height: 18px }
`

/// A whole page: its title, the style above, and a policy that lets it load nothing.
export function page(title, body, cls = 'doc') {
  return `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title><style>${STYLE}</style></head>
<body class="${cls}">${body}</body></html>
`
}

// ---------- Markdown ----------
// CommonMark's common parts and GitHub's tables, strikethrough and task lists: headings (# and underlined), paragraphs,
// emphasis, lists (nested), links and images (as text), inline code, code blocks (fenced and indented), block quotes,
// tables, rules, and front matter (shown small, as it is).
const FENCE = /^ {0,3}(`{3,}|~{3,})(.*)$/
const ATX = /^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$/
const RULE = /^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/
const QUOTE = /^ {0,3}>/
const ITEM = /^( *)([-*+]|\d{1,9}[.)])(?:( +)(.*))?$/
const DELIM = /^ {0,3}\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$/
const tableAt = (lines, i) => lines[i].includes('|') && (lines[i + 1] ?? '').includes('|') && DELIM.test(lines[i + 1])  // a header row, then its delimiter row
const indentOf = l => l.match(/^ */)[0].length
const startsBlock = l => FENCE.test(l) || ATX.test(l) || RULE.test(l) || QUOTE.test(l) || ITEM.test(l)

export function markdown(src) {
  const text = String(src).replace(/^﻿/, '').replace(/\r\n?/g, '\n').replace(/\t/g, '    ').replace(/<!--[\s\S]*?-->/g, '')
  const lines = text.split('\n')
  let front = ''
  if (lines[0] === '---') {                                          // front matter: --- … --- (or …) at the very top
    const end = lines.findIndex((l, i) => i > 0 && (l === '---' || l === '...'))
    if (end > 0 && end < 200) { front = `<pre class="front">${esc(lines.slice(1, end).join('\n'))}</pre>`; lines.splice(0, end + 1) }
  }
  return front + blocks(lines)
}

function blocks(lines) {
  let out = '', i = 0, m
  while (i < lines.length) {
    const l = lines[i]
    if (!l.trim()) { i++; continue }
    if ((m = l.match(FENCE)) && !(m[1][0] === '`' && m[2].includes('`'))) {
      const fence = m[1], body = []
      for (i++; i < lines.length && !new RegExp(`^ {0,3}${fence[0]}{${fence.length},}[ \\t]*$`).test(lines[i]); i++) body.push(lines[i])
      i++
      out += `<pre><code>${esc(body.join('\n'))}</code></pre>`
    } else if ((m = l.match(ATX))) {
      out += `<h${m[1].length}>${inline(m[2] ?? '')}</h${m[1].length}>`; i++
    } else if (RULE.test(l)) {
      out += '<hr>'; i++
    } else if (QUOTE.test(l)) {
      const body = []
      // its lines, and the lines that carry on its paragraph without a > (lazy continuation)
      while (i < lines.length && lines[i].trim() && (QUOTE.test(lines[i]) || !startsBlock(lines[i]))) body.push(lines[i++].replace(/^ {0,3}> ?/, ''))
      out += `<blockquote>${blocks(body)}</blockquote>`
    } else if (ITEM.test(l)) {
      const [html, next] = list(lines, i); out += html; i = next
    } else if (indentOf(l) >= 4) {
      const body = []
      while (i < lines.length && (indentOf(lines[i]) >= 4 || !lines[i].trim())) body.push(lines[i++].slice(4))
      while (body.length && !body.at(-1).trim()) body.pop()
      out += `<pre><code>${esc(body.join('\n'))}</code></pre>`
    } else if (tableAt(lines, i)) {
      const [html, next] = table(lines, i); out += html; i = next
    } else {
      const para = [l]
      let heading = 0
      for (i++; i < lines.length && lines[i].trim(); i++) {
        if (/^ {0,3}=+[ \t]*$/.test(lines[i])) { heading = 1; i++; break }   // a line under it: a heading
        if (/^ {0,3}-+[ \t]*$/.test(lines[i])) { heading = 2; i++; break }
        if (startsBlock(lines[i]) || tableAt(lines, i)) break
        para.push(lines[i])
      }
      const html = inline(para.map(s => s.replace(/^ +/, '')).join('\n').trimEnd())
      out += heading ? `<h${heading}>${html}</h${heading}>` : `<p>${html}</p>`
    }
  }
  return out
}

function list(lines, i) {
  const first = lines[i].match(ITEM), ordered = /\d/.test(first[2])
  const start = ordered ? parseInt(first[2], 10) : 1
  let html = ordered ? `<ol${start !== 1 ? ` start="${start}"` : ''}>` : '<ul>'
  let m
  while (i < lines.length && (m = lines[i].match(ITEM)) && /\d/.test(m[2]) === ordered) {
    const content = m[1].length + m[2].length + Math.min(m[3]?.length ?? 1, 4)   // where its text starts
    const body = [m[4] ?? '']
    for (i++; i < lines.length; i++) {
      const l = lines[i]
      if (!l.trim()) {                                              // a blank line: the item goes on if what follows is indented
        let j = i
        while (j < lines.length && !lines[j].trim()) j++
        if (j < lines.length && indentOf(lines[j]) >= content) { body.push(...Array(j - i).fill('')); i = j - 1; continue }
        break
      }
      if (indentOf(l) >= content) body.push(l.slice(content))
      else if (ITEM.test(l) || startsBlock(l)) break                // the next item, or the end of the list
      else body.push(l.trim())                                       // its paragraph, carried on without the indent
    }
    let inner = blocks(body)
    const one = inner.match(/^<p>([\s\S]*?)<\/p>(?![\s\S]*<p>)([\s\S]*)$/)
    if (one && !body.slice(1).some(x => !x.trim())) inner = one[1] + one[2]   // a tight item: no paragraph around its text
    inner = inner.replace(/^\[( |x|X)\] /, (_, x) => `<span class="box">${x === ' ' ? '☐' : '☑'}</span> `)
    html += `<li>${inner}</li>`
    let j = i                                                        // blank lines between items
    while (j < lines.length && !lines[j].trim()) j++
    if (j > i && j < lines.length && (m = lines[j].match(ITEM)) && /\d/.test(m[2]) === ordered && m[1].length < content) i = j
  }
  return [html + (ordered ? '</ol>' : '</ul>'), i]
}

function table(lines, i) {
  const cells = l => l.trim().replace(/^\|/, '').replace(/(?<!\\)\|$/, '').split(/(?<!\\)\|/).map(c => c.trim().replace(/\\\|/g, '|'))
  const head = cells(lines[i])
  const align = cells(lines[i + 1]).map(c => c.endsWith(':') ? (c.startsWith(':') ? 'center' : 'right') : '')
  const cell = (tag, c, k) => `<${tag}${align[k] ? ` style="text-align:${align[k]}"` : ''}>${inline(c ?? '')}</${tag}>`
  let html = `<table><tr>${head.map((c, k) => cell('th', c, k)).join('')}</tr>`
  for (i += 2; i < lines.length && lines[i].trim() && !startsBlock(lines[i]); i++) {
    const row = cells(lines[i])
    html += `<tr>${head.map((_, k) => cell('td', row[k], k)).join('')}</tr>`
  }
  return [html + '</table>', i]
}

/// A paragraph's text: code spans, emphasis, links and images as text, line breaks; the rest escaped.
export function inline(s) {
  const held = []
  const hold = html => `\u0000${held.push(html) - 1}\u0000`
  s = String(s).replace(/\u0000/g, '')
    .replace(/(`+)([\s\S]*?[^`])\1(?!`)/g, (_, __, c) => hold(`<code>${esc(c.replace(/\n/g, ' ').replace(/^ ([\s\S]*) $/, '$1'))}</code>`))
    .replace(/\\([!-/:-@[-`{-~])/g, (_, c) => hold(esc(c)))
    .replace(/<((?:https?|mailto|ftp):[^\s<>]+|[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+)>/gi, (_, u) => hold(`<span class="link">${esc(u)}</span>`))
    .replace(/<br\s*\/?>/gi, () => hold('<br>'))
    .replace(/<img\b[^>]*?\balt\s*=\s*"([^"]*)"[^>]*>/gi, (_, alt) => hold(`<span class="img">${esc(alt ? `Image: ${alt}` : 'Image')}</span>`))
    .replace(/<\/?[A-Za-z][\w-]*(?:\s[^<>]*)?\/?>/g, '')            // other HTML: dropped, its text kept
  s = esc(s)
    .replace(/!\[([^\]]*)\]\((?:[^()]|\([^)]*\))*\)/g, (_, alt) => `<span class="img">${alt ? `Image: ${alt}` : 'Image'}</span>`)
    .replace(/!\[([^\]]*)\]\[[^\]]*\]/g, (_, alt) => `<span class="img">${alt ? `Image: ${alt}` : 'Image'}</span>`)
    .replace(/\[([^\]]+)\]\((?:[^()]|\([^)]*\))*\)/g, '<span class="link">$1</span>')
    .replace(/\[([^\]]+)\]\[[^\]]*\]/g, '<span class="link">$1</span>')
    .replace(/(\*\*|__)(?=\S)([\s\S]*?\S)\1/g, '<strong>$2</strong>')
    .replace(/(?<![\w*])\*(?=[^\s*])([\s\S]*?[^\s*])\*(?![\w*])/g, '<em>$1</em>')
    .replace(/(?<![\w_])_(?=[^\s_])([\s\S]*?[^\s_])_(?![\w_])/g, '<em>$1</em>')
    .replace(/~~(?=\S)([\s\S]*?\S)~~/g, '<del>$1</del>')
    .replace(/(?: {2,}|\\)\n/g, '<br>').replace(/\n/g, ' ')
  return s.replace(/\u0000(\d+)\u0000/g, (_, n) => held[n])
}

// ---------- text and code ----------
// Monospaced, each line wrapped at the page's width with its continuation indented; at most `cap` characters of a line.
/// lines: the first lines of the file; total: how many it has (null when it wasn't counted).
export function textBody(lines, total, cap) {
  const rows = lines.map(l => `<div class="l">${esc(l.length > cap ? l.slice(0, cap) + '…' : l) || ' '}</div>`).join('')
  const more = total == null ? `First ${count(lines.length)} lines.` : total > lines.length ? `First ${count(lines.length)} lines of ${count(total)}.` : ''
  return rows + (more ? `<p class="note">${more}</p>` : '')
}
/// How many of these lines fit in `rows` rows of a text page 390 pt wide: 11 px SF Mono is 6.6 px a character, so 55
/// to the first row of a line and 53 to each row it wraps onto, less what wrapping at a space leaves (counted as 51
/// and 49). East Asian characters and emoji count two.
export function linesThatFit(lines, rows, cap) {
  let used = 0, n = 0
  for (const l of lines) {
    let w = 0
    for (const ch of l.length > cap ? l.slice(0, cap + 1) : l) w += ch.codePointAt(0) >= 0x1100 ? 2 : 1
    used += w <= 55 ? 1 : 1 + Math.ceil((w - 51) / 49)
    if (used > rows) break
    n++
  }
  return Math.max(1, n)
}

// ---------- tables (CSV, TSV) ----------
/// rows: the first rows (the first one is the header); total: how many it has. A cut table keeps each cell on one line,
/// at most `cap` characters, so its rows are the same height (the picture's); otherwise cells wrap at 22 em.
export function tableBody(rows, total, cols, cap, oneLine) {
  const width = Math.max(...rows.map(r => r.length), 1), shownCols = Math.min(width, cols)
  const cut = c => { c = String(c ?? '').replace(/\s+/g, ' ').trim(); return c.length > cap ? c.slice(0, cap) + '…' : c }
  const numeric = c => /^[-+]?[$€£]?[\d.,]+%?$/.test(c)
  const [head = [], ...body] = rows
  const tr = (r, tag) => `<tr>${Array.from({ length: shownCols }, (_, k) => {
    const c = cut(r[k]); return `<${tag}${tag === 'td' && numeric(c) ? ' class="n"' : ''}${oneLine ? '' : ' style="max-width:22em"'}>${esc(c)}</${tag}>`
  }).join('')}</tr>`
  const notes = []
  if (total > body.length) notes.push(`First ${count(body.length)} rows of ${count(total)}.`)
  if (width > shownCols) notes.push(`First ${shownCols} columns of ${width}.`)
  return `<table class="${oneLine ? 'cut' : ''}">${tr(head, 'th')}${body.map(r => tr(r, 'td')).join('')}</table>` +
    (notes.length ? `<p class="note">${notes.join(' ')}</p>` : '')
}

// ---------- the files themselves (run by the hub as its own process) ----------
const HEAD = { markdown: 256 * 1024, text: 1024 * 1024 }            // what is read of a long file: more than any page shows
const TEXT_LINES = 300, TEXT_ROWS = 380                              // the picture: at most 300 lines in 380 rows
const VIEW_LINES = 5000                                              // view.html
const TABLE_COLS = 30, VIEW_ROWS = 1000, VIEW_COLS = 100
const READ_ALL = 200e6                                               // past 200 MB, lines and rows aren't counted

function head(file, n) {
  const fd = fs.openSync(file, 'r')
  try { const buf = Buffer.alloc(n); return buf.subarray(0, fs.readSync(fd, buf, 0, n, 0)) } finally { fs.closeSync(fd) }
}
/// Text without control characters other than tab and line breaks (a stray NUL or escape code shows as nothing).
const clean = s => s.replace(/^﻿/, '').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '')

function lineCount(file, size) {
  if (size > READ_ALL) return null
  const fd = fs.openSync(file, 'r'), buf = Buffer.alloc(1 << 20)
  let n = 0, last = 10
  try {
    for (let got; (got = fs.readSync(fd, buf, 0, buf.length, null)) > 0;) {
      for (let k = buf.indexOf(10); k !== -1 && k < got; k = buf.indexOf(10, k + 1)) n++
      last = buf[got - 1]
    }
  } finally { fs.closeSync(fd) }
  return n + (last !== 10 ? 1 : 0)
}

/// The first `keep` rows of a CSV (quoted fields, "" inside them, line breaks in them) or TSV, and how many it has
/// (null past 200 MB).
function readTable(file, sep, keep, size) {
  const fd = fs.openSync(file, 'r'), buf = Buffer.alloc(1 << 20), dec = new StringDecoder('utf8'), csv = sep === ','
  const rows = []
  let row = [], field = '', quoted = false, total = 0, read = 0, pending = false
  const endField = () => { if (rows.length < keep) row.push(field.slice(0, 2000)); field = '' }
  const endRow = () => { endField(); if (rows.length < keep) rows.push(row); row = []; total++ }
  try {
    for (let got; (got = fs.readSync(fd, buf, 0, buf.length, null)) > 0;) {
      if ((read += got) > READ_ALL && rows.length >= keep) return { rows: rows.map(r => r.map(clean)), total: null }
      const s = dec.write(buf.subarray(0, got))
      for (let k = 0; k < s.length; k++) {
        const c = s[k]
        if (pending) { pending = false; if (c === '"') { field += '"'; continue } quoted = false }   // a "" split by a read
        if (quoted) {
          if (c !== '"') { if (rows.length < keep) field += c }
          else if (k + 1 === s.length) pending = true
          else if (s[k + 1] === '"') { field += '"'; k++ }
          else quoted = false
        }
        else if (c === '"' && csv && field === '') quoted = true
        else if (c === sep) endField()
        else if (c === '\n') endRow()
        else if (c !== '\r' && rows.length < keep) field += c
      }
    }
  } finally { fs.closeSync(fd) }
  if (field || row.length) endRow()
  return { rows: rows.map(r => r.map(clean)), total }
}

function render(kind, file, dir, title) {
  const size = fs.statSync(file).size
  if (kind === 'markdown') {
    const buf = head(file, HEAD.markdown), whole = buf.length >= size
    let text = clean(new TextDecoder().decode(buf))
    if (!whole) text = text.slice(0, text.lastIndexOf('\n') + 1)
    const more = whole ? '' : `<p class="note">The first ${count(HEAD.markdown / 1024)} KB of ${count(Math.round(size / 1024))} KB.</p>`
    fs.writeFileSync(path.join(dir, 'view.html'), page(title, markdown(text) + more))
    return { shot: 'view.html', note: whole ? null : 'first part', cutNote: 'first part' }
  }
  if (kind === 'text') {
    const buf = head(file, HEAD.text), whole = buf.length >= size
    let text = clean(new TextDecoder().decode(buf)).replace(/\r\n?/g, '\n').replace(/\t/g, '    ')
    // minified JSON, laid out (its lines are then the laid-out ones)
    if (whole && /\.json$/i.test(file) && text.length > 200 && text.split('\n', 4).length < 4) {
      try { text = JSON.stringify(JSON.parse(text), null, 2) } catch {}
    }
    const lines = text.split('\n')
    if (lines.at(-1) === '') lines.pop()
    if (!whole && lines.length > 1) lines.pop()                     // a line cut by the read
    const total = whole ? lines.length : lineCount(file, size)
    const n = Math.min(lines.length, linesThatFit(lines.slice(0, TEXT_LINES), TEXT_ROWS, 1000))
    fs.writeFileSync(path.join(dir, 'view.html'), page(title, textBody(lines.slice(0, VIEW_LINES), total, 5000), 'text'))
    fs.writeFileSync(path.join(dir, 'shot.html'), page(title, textBody(lines.slice(0, n), total, 1000), 'text'))
    return {
      shot: 'shot.html',
      note: total == null ? `first ${count(n)} lines` : n < total ? `first ${count(n)} lines of ${count(total)}` : null,
      cutNote: total == null ? 'first part' : `first part of ${count(total)} lines`,
    }
  }
  if (kind === 'table') {
    const { rows, total: all } = readTable(file, /\.tsv$/i.test(file) ? '\t' : ',', VIEW_ROWS + 1, size)
    const total = all == null ? null : Math.max(0, all - 1)           // rows under the header
    // the picture: each cell on one line, at most 40 characters (about 7.4 pt each, 18 pt of padding), the columns
    // that fit in 1300 pt; page-shot widens the page to the table, up to 1600 pt, the picture at most 1200 px wide.
    // Its rows, 27 pt each: as many as a picture of that width holds (10 M pixels, a page 9000 pt tall).
    const allCols = Math.max(...rows.map(r => r.length), 1)
    let cols = 0, wide = 24
    for (; cols < Math.min(TABLE_COLS, allCols); cols++) {
      const col = Math.max(1, ...rows.slice(0, 201).map(r => Math.min(40, (r[cols] ?? '').length))) * 7.4 + 18
      if (cols && wide + col > 1300) break
      wide += col
    }
    const w = Math.max(390, wide), px = Math.min(w * 2, Math.max(780, 1200))
    const fit = Math.floor((Math.min(9000, 10e6 / px / (px / w)) - 90) / 27)
    const shown = Math.max(0, Math.min(200, fit, rows.length - 1))
    fs.writeFileSync(path.join(dir, 'view.html'), page(title, tableBody(rows, total ?? rows.length - 1, VIEW_COLS, 300, false), 'table'))
    fs.writeFileSync(path.join(dir, 'shot.html'), page(title, tableBody(rows.slice(0, shown + 1), total ?? shown, cols, 40, true), 'table'))
    const narrower = cols < allCols ? `, ${cols} of ${allCols} columns` : ''
    return {
      shot: 'shot.html', maxWidth: 1600,
      note: total == null ? `first ${count(shown)} rows${narrower}` : shown < total ? `first ${count(shown)} rows of ${count(total)}${narrower}` : narrower.slice(2) || null,
      cutNote: total == null ? 'first part' : `first part of ${count(total)} rows`,
    }
  }
  throw new Error(`no such kind: ${kind}`)
}

if (process.argv[1] === import.meta.filename) {
  const [kind, file, dir, title] = process.argv.slice(2)
  try { process.stdout.write(JSON.stringify(render(kind, file, dir, title || path.basename(file)))) }
  catch (e) { process.stderr.write(`render: ${e.message}\n`); process.exit(1) }
}
