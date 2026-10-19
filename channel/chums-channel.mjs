#!/usr/bin/env node
// Chums channel: a Claude Code channel (MCP server) that connects one session to the Chums hub.
//   in:  orders spoken on the watch  -> notifications/claude/channel
//   out: chums_reply tool            -> one spoken line on the watch
//   both ways: permission prompts    -> approval card on the watch -> allow/deny verdict
// Launched by Claude Code (see bin/chums-claude). Talks to the hub over localhost HTTP.
//
// Tools only (CHUMS_SESSION set): for agents the hub itself drives (Codex, Copilot and other Agent Client Protocol
// agents, hub/runtimes.mjs), which give it to their agent as an ordinary MCP server. The hub already knows the session
// and brings it orders and verdicts, so this only offers chums_reply and chums_show for that session: no channel, no
// registering, no polling.

import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { execFile } from 'node:child_process'
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js'
import { z } from 'zod'
import { MAX_WORDS, PHONE_WORDS, WATCH_GUIDE, PAGE_GUIDE, OWNER, Owner, wordsFor } from '../hub/standing.mjs'

const toolsOnly = !!process.env.CHUMS_SESSION
// a hub-driven agent's MCP server gets the hub's address from the hub, and its token or the file that has it (its HOME
// may be another)
const CONFIG = process.env.CHUMS_CONFIG || path.join(os.homedir(), '.chums', 'config.json')
let cfg
try { cfg = process.env.CHUMS_HUB && process.env.CHUMS_TOKEN ? { token: process.env.CHUMS_TOKEN } : JSON.parse(fs.readFileSync(CONFIG, 'utf8')) }
catch (e) {
  // (not e.message: a JSON error quotes the file, and the file holds the token)
  process.stderr.write(`[chums] can't read ${CONFIG} (${e.code ?? 'not valid JSON'}). Start the hub once (bin/chums-hub): it writes it.\n`)
  process.exit(1)
}
const HUB = process.env.CHUMS_HUB || `http://127.0.0.1:${cfg.port}`
const sessionId = process.env.CHUMS_SESSION || crypto.randomUUID()
const name = process.env.CHUMS_NAME || path.basename(process.cwd())
const err = (...a) => process.stderr.write(`[chums] ${a.join(' ')}\n`)

async function hub(pathname, body, method = body ? 'POST' : 'GET') {
  const res = await fetch(HUB + pathname, {
    method,
    headers: { authorization: `Bearer ${cfg.token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    const why = await res.json().then(b => b.error).catch(() => null)
    throw Object.assign(new Error(why ?? `hub ${res.status} ${pathname}`), { status: res.status })
  }
  return res.json()
}

const mcp = new Server(
  { name: 'chums', version: '0.1.0' },
  {
    capabilities: toolsOnly ? { tools: {} } : {
      experimental: { 'claude/channel': {}, 'claude/channel/permission': {} },
      tools: {},
    },
    instructions: toolsOnly ? WATCH_GUIDE : [
      `${Owner} talks to this session (named "${name}") from an Apple Watch, often away from the desk.`,
      `${Owner}'s messages arrive as <channel source="chums" utterance_id="..." via="watch"> or via="phone"; from the watch they are voice transcripts, so expect recognition errors and read for intent.`,
      'Do the work exactly as if it had been typed here.',
      `Whenever you finish work ${OWNER} asked for from the watch, or you need ${OWNER}, call the chums_reply tool.`,
      `Each reply is spoken aloud: give a spoken update like a capable colleague's quick report, ${MAX_WORDS} words at most (the tool refuses longer).`,
      'Lead with the result, then what you did and what you found that matters, in plain spoken sentences; no preamble, no restating what was said.',
      `When ${OWNER} asks for details or more, give them: several chums_reply calls in a row, each a natural spoken chunk, or chums_show for anything long or visual (code, a diff, a table).`,
      `From the iPhone (via="phone") the reply is shown as text: give the answer itself in plain sentences, ${PHONE_WORDS} words at most, still no code, paths, URLs, markdown or lists.`,
      'Never include code, file paths, URLs, markdown or lists; they are read aloud.',
      "Set status: 'done' when finished, 'question' when you need an answer, 'blocked' when you cannot continue, 'working' only for a rare progress note on long tasks.",
      `To ask ${OWNER} something (a choice, a go-ahead), call chums_reply with status 'question' and wait: the answer comes as the next message. Don't use AskUserQuestion: its dialog shows only in this terminal, where nobody is.`,
      'Only use chums_reply for messages that came from the watch, not for messages typed in the terminal.',
      'The watch shows and speaks every chums_reply; you cannot see or hear it, and that is expected.',
      `If ${OWNER} asks whether you can hear, just answer. Never investigate the watch app or the hub unless asked to.`,
      `Never start replies with a name or give yourself one: on the watch you appear as the character ${OWNER} picked.`,
      `When ${OWNER} asks to see something (the screen, an app or browser tab, a web page, a file, an image, a chart), or you made something visual that was asked for, call chums_show instead of chums_reply: it puts a picture in the watch chat that can be opened and zoomed, and says its text; the iPhone opens the file itself.`,
      "For the whole screen use screenshot: 'screen'; for an app use its name, e.g. screenshot: 'Safari'. chums_show finds the app's window itself and is quick: call it first, without looking for apps, windows or browser extensions some other way. If what's wanted isn't on screen in that app (a Stripe dashboard, say), also pass open: its URL, and it opens there before the screenshot. Pages that need a login (dashboards, mail) are screenshots of the browser; a public page is url; a file is file (a page, a document, a PDF, text or code, a table, an image or a video). If it fails, the error says why and which apps have windows open.", PAGE_GUIDE,
    ].join(' '),
  },
)

// For hub-driven agents: neither tool changes anything on the Mac (one speaks on the watch, the other shows a picture
// there), so agents that ask before MCP tool calls that might can run them without asking.
const QUIET = { readOnlyHint: true, destructiveHint: false, idempotentHint: false, openWorldHint: false }

mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: 'chums_reply',
    description: `Speak to ${OWNER} on the Apple Watch. Use after finishing or when you need ${OWNER}; call it again in a row to say more.`,
    inputSchema: {
      type: 'object',
      properties: {
        text: { type: 'string', description: `A spoken update in plain sentences, result first: ${MAX_WORDS} words at most (to the iPhone: ${PHONE_WORDS} words at most). No code, paths or URLs.` },
        status: { type: 'string', enum: ['done', 'question', 'blocked', 'working'] },
      },
      required: ['text'],
    },
    ...(toolsOnly ? { annotations: QUIET } : {}),
  }, {
    name: 'chums_show',
    description: `Show ${OWNER} something on the Apple Watch and the iPhone: a screenshot of the screen or an app window, a web page, or a file: a page, a document, a PDF, text or code, a table, an image or a video. The watch shows it as a picture that can be opened and zoomed (a video as a still), with a short spoken line; the iPhone opens the file itself. ${PAGE_GUIDE}`,
    inputSchema: {
      type: 'object',
      properties: {
        screenshot: { type: 'string', description: "'screen' for the whole display, or an app's name (e.g. 'Safari') for its front window." },
        open: { type: 'string', description: "With screenshot of an app: a URL to open in that app first (e.g. 'https://dashboard.stripe.com'), for when what's wanted isn't already on screen there." },
        url: { type: 'string', description: 'A public web page to render at phone width (not one behind a login: screenshot the browser instead).' },
        file: { type: 'string', description: 'Absolute path of the file: HTML or SVG, PDF, Markdown, text or code, CSV or TSV, an image, a video (.mov, .mp4, .m4v), or a document macOS previews (Word, Excel, PowerPoint, Pages, Keynote, Numbers, RTF, EPUB, USDZ).' },
        title: { type: 'string', description: 'Two to four words, shown on the watch, e.g. "Stripe dashboard".' },
        text: { type: 'string', description: `A spoken line about what is shown: ${MAX_WORDS} words at most.` },
      },
    },
    ...(toolsOnly ? { annotations: QUIET } : {}),
  }],
}))

// a screenshot of the whole screen, or of an app's front window, as a PNG. It needs the Screen Recording permission of
// the app this session runs in (macOS asks for it, or it's in System Settings › Privacy & Security).
const sh = (cmd, args) => new Promise((resolve, reject) => execFile(cmd, args, { timeout: 15_000 }, (e, out, errOut) => e ? reject(new Error(String(errOut || e.message).trim())) : resolve(String(out).trim())))
async function screenshot(target) {
  const out = path.join(os.tmpdir(), `chums-shot-${Date.now()}.png`)
  if (/^(screen|desktop|display|everything)$/i.test(target)) { await sh('/usr/sbin/screencapture', ['-x', out]); return { file: out, from: 'screen' } }
  const js = `ObjC.import("CoreGraphics");
    const all = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll | $.kCGWindowListExcludeDesktopElements, $.kCGNullWindowID)));
    const want = ${JSON.stringify(target.toLowerCase())};
    const w = all.filter(w => w.kCGWindowLayer === 0 && (w.kCGWindowOwnerName || "").toLowerCase().includes(want) && w.kCGWindowBounds.Height > 150 && w.kCGWindowBounds.Width > 150)
      .sort((a, b) => (b.kCGWindowIsOnscreen ? 1 : 0) - (a.kCGWindowIsOnscreen ? 1 : 0));
    w.length ? w[0].kCGWindowNumber + " " + w[0].kCGWindowOwnerName : ""`
  const found = await sh('/usr/bin/osascript', ['-l', 'JavaScript', '-e', js])
  if (!found) {
    // say which apps do have windows, so the session can pick the right one
    const open = await sh('/usr/bin/osascript', ['-l', 'JavaScript', '-e', `ObjC.import("CoreGraphics");
      const all = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll | $.kCGWindowListExcludeDesktopElements, $.kCGNullWindowID)));
      [...new Set(all.filter(w => w.kCGWindowLayer === 0 && w.kCGWindowBounds.Height > 150).map(w => w.kCGWindowOwnerName))].join(", ")`]).catch(() => '')
    throw new Error(`No open window of ${target}.${open ? ` Apps with windows open: ${open}.` : ''}`)
  }
  const [wid, ...owner] = found.split(' ')
  await sh('/usr/sbin/screencapture', ['-x', '-o', '-l', wid, out])
  return { file: out, from: owner.join(' ') }
}
const PERMISSION = `macOS refused the screenshot: the app this session runs in needs Screen Recording (System Settings › Privacy & Security › Screen & System Audio Recording). Tell ${OWNER}, in a few words.`

mcp.setRequestHandler(CallToolRequestSchema, async req => {
  if (req.params.name === 'chums_show') return show(req.params.arguments ?? {})
  if (req.params.name !== 'chums_reply') throw new Error(`unknown tool: ${req.params.name}`)
  const { text, status = 'done' } = req.params.arguments ?? {}
  // the watch shows a line or two and reads it aloud: refuse anything longer, so the session says it again, shorter
  // (the iPhone shows the text: a few sentences)
  const words = String(text ?? '').trim().split(/\s+/).filter(Boolean).length, limit = wordsFor(lastVia)
  if (words > limit) {
    const where = lastVia === 'phone' ? 'the iPhone' : 'the watch'
    return { content: [{ type: 'text', text: `Too long for ${where} (${words} words). Say it again in ${limit} words or fewer, or split it over several chums_reply calls.` }], isError: true }
  }
  try {
    await hub('/channel/reply', { sessionId, text: String(text), status })
    return { content: [{ type: 'text', text: 'Spoken on the watch.' }] }
  } catch (e) {
    return { content: [{ type: 'text', text: `The watch hub is unreachable (${e.message}); ${OWNER} did not hear this.` }], isError: true }
  }
})

async function show({ screenshot: target, open: openURL, url, file, title, text }) {
  const fail = t => ({ content: [{ type: 'text', text: t }], isError: true })
  const words = String(text ?? '').trim().split(/\s+/).filter(Boolean).length
  if (words > wordsFor(lastVia)) return fail(`Too long (${words} words). Say it in ${wordsFor(lastVia)} words or fewer.`)
  if (!target && !url && !file) return fail('Give screenshot, url or file.')
  let shot
  if (target) {
    // what's wanted isn't on screen yet: open it in that app, and give the page a moment to load
    if (openURL && !/^(screen|desktop|display|everything)$/i.test(target)) {
      try { await sh('/usr/bin/open', ['-a', String(target), String(openURL)]); await new Promise(r => setTimeout(r, 3500)) }
      catch (e) { return fail(`Couldn't open ${openURL} in ${target}: ${e.message}`) }
    }
    try { shot = await screenshot(String(target)) }
    catch (e) { return fail(/could not create image|not permitted|denied/i.test(e.message) ? PERMISSION : `Screenshot failed: ${e.message}`) }
  }
  try {
    const a = await hub('/channel/artifact', {
      sessionId, file: shot?.file ?? file, url, title: title ?? (shot ? shot.from : undefined), text,
      kind: shot ? 'screenshot' : undefined, from: shot?.from,
    })
    return { content: [{ type: 'text', text: `Shown on the watch: ${a.title} (${a.w}×${a.h}).` }] }
  } catch (e) {
    return fail(e.status === 422 ? `The watch couldn't show it: ${e.message}` : `The watch hub is unreachable (${e.message}); ${OWNER} did not see this.`)
  } finally { if (shot) fs.rm(shot.file, () => {}) }
}

const PermissionRequest = z.object({
  method: z.literal('notifications/claude/channel/permission_request'),
  params: z.object({
    request_id: z.string(),
    tool_name: z.string(),
    description: z.string(),
    input_preview: z.string(),
  }),
})

mcp.setNotificationHandler(PermissionRequest, async ({ params }) => {
  try { await hub('/channel/permission', { sessionId, ...params }) }
  catch (e) { err('could not relay permission request:', e.message) }
})

await mcp.connect(new StdioServerTransport())

// ---- hub loop: register, then long-poll for orders and verdicts ----
// Each item is acknowledged on the next poll; the hub sends it again until then, so ids already handled are skipped.
let registered = false
let lastVia = 'watch'                    // where the latest order was said: its reply's length follows
const handled = new Set(), handledOrder = []
async function loop() {
  let ack = []
  for (;;) {
    try {
      if (!registered) {
        await hub('/channel/register', { sessionId, name, cwd: process.cwd() })
        registered = true
        err('connected to hub as', name)
      }
      const { items } = await hub(`/channel/next?sessionId=${sessionId}${ack.length ? `&ack=${ack.join(',')}` : ''}`)
      ack = items.map(it => it.id).filter(Boolean)
      for (const it of items) {
        if (it.id && handled.has(it.id)) continue
        if (it.id) { handled.add(it.id); handledOrder.push(it.id); if (handledOrder.length > 500) handled.delete(handledOrder.shift()) }
        if (it.type === 'order') {
          lastVia = it.device === 'phone' ? 'phone' : 'watch'
          await mcp.notification({
            method: 'notifications/claude/channel',
            params: { content: it.text, meta: { utterance_id: it.utteranceId, via: lastVia } },
          })
        } else if (it.type === 'verdict') {
          await mcp.notification({
            method: 'notifications/claude/channel/permission',
            params: { request_id: it.requestId, behavior: it.behavior },
          })
        }
      }
    } catch (e) {
      // 404: the hub restarted and forgot us, re-register now. Anything else: hub down, retry in 5 s.
      registered = false
      if (e.status !== 404) await new Promise(r => setTimeout(r, 5000))
    }
  }
}
const bye = () => { hub('/channel/bye', { sessionId }).catch(() => {}).finally(() => process.exit(0)) }
if (toolsOnly) process.stdin.on('end', () => process.exit(0))        // the hub owns this session: no register, poll or bye
else {
  loop()
  process.stdin.on('end', bye)
  process.on('SIGTERM', bye)
}
