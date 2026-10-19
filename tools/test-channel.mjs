// End-to-end check of hub + channel without Claude Code: this script plays Claude Code's side of the
// MCP stdio connection and the watch's side of the hub API.
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import readline from 'node:readline'

import { startPrivateHub } from './test-hub-private.mjs'
const { cfg, home, stop } = await startPrivateHub()                 // never the real hub: its sessions would get the test's orders
const HUB = `http://127.0.0.1:${cfg.port}`
const auth = { authorization: `Bearer ${cfg.token}`, 'content-type': 'application/json' }
const watch = (p, body) => fetch(HUB + p, { method: body ? 'POST' : 'GET', headers: auth, body: body && JSON.stringify(body) }).then(r => r.json())
const sleep = ms => new Promise(r => setTimeout(r, ms))

const ch = spawn('node', [path.join(import.meta.dirname, '../channel/chums-channel.mjs')], {
  env: { ...process.env, HOME: home, CHUMS_NAME: 'chumstest' }, stdio: ['pipe', 'pipe', 'inherit'], cwd: os.tmpdir(),
})
const inbox = []
readline.createInterface({ input: ch.stdout }).on('line', l => inbox.push(JSON.parse(l)))
const send = m => ch.stdin.write(JSON.stringify({ jsonrpc: '2.0', ...m }) + '\n')
const waitFor = async (pred, ms = 5000) => {
  const end = Date.now() + ms
  while (Date.now() < end) { const i = inbox.findIndex(pred); if (i >= 0) return inbox.splice(i, 1)[0]; await sleep(50) }
  throw new Error('timeout waiting for message')
}
const ok = (c, m) => { console.log(c ? 'PASS' : 'FAIL', m); if (!c) process.exitCode = 1 }

send({ id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'fake-claude-code', version: '0' } } })
const init = await waitFor(m => m.id === 1)
ok(init.result.capabilities.experimental?.['claude/channel'] && init.result.capabilities.experimental?.['claude/channel/permission'], 'channel declares claude/channel + permission capabilities')
send({ method: 'notifications/initialized' })

await sleep(800)
let st = await watch('/v1/state?since=0')
ok(st.sessions.some(s => s.name === 'chumstest'), 'session registered with hub')

// watch -> order -> channel notification into the session
const r = await watch('/v1/say', { text: 'Tell chumstest to run the channel tests' })
ok(r.kind === 'order' && r.target === 'chumstest', `routed order: ${r.echo}`)
const note = await waitFor(m => m.method === 'notifications/claude/channel')
ok(note.params.content.includes('channel tests'), `session received: "${note.params.content}"`)

// Claude calls chums_reply -> spoken line on the watch
send({ id: 2, method: 'tools/call', params: { name: 'chums_reply', arguments: { text: 'Channel tests passed.', status: 'done' } } })
await waitFor(m => m.id === 2)
st = await watch('/v1/state?since=0')
ok(/^(chumstest: )?Channel tests passed\.$/.test(st.spoken.at(-1)?.text ?? ''), `watch hears: "${st.spoken.at(-1)?.text}"`)

// a spoken update of a few sentences reaches the watch whole
const update = 'All ten channel tests pass. I ran them twice to rule out flaky failures, and fixed one slow reconnect in the hub along the way.'
send({ id: 8, method: 'tools/call', params: { name: 'chums_reply', arguments: { text: update, status: 'done' } } })
await waitFor(m => m.id === 8)
ok((await watch('/v1/state?since=0')).spoken.at(-1)?.text?.endsWith('along the way.'), 'a 25-word update reaches the watch whole')

// a reply longer than 45 words is refused, so the session says it again, shorter or split; the watch hears nothing
const tooLong = `${update} Then I read every log line from the last run, checked each retry and timeout against the spec, and wrote down the three flaky spots I found for later in our notes.`
send({ id: 9, method: 'tools/call', params: { name: 'chums_reply', arguments: { text: tooLong, status: 'done' } } })
const long = await waitFor(m => m.id === 9)
const st9 = await watch('/v1/state?since=0')
ok(long.result?.isError && /Too long/.test(long.result.content[0].text) && !/spec/.test(st9.spoken.at(-1)?.text ?? ''), `a ${tooLong.split(' ').length}-word reply is refused and never reaches the watch`)

// from the iPhone: the order says so, and the reply can be a few sentences (the iPhone shows the text)
await watch('/v1/say', { text: 'Tell chumstest what the label on this tube means', device: 'phone' })
const phoneNote = await waitFor(m => m.method === 'notifications/claude/channel')
ok(phoneNote.params.meta?.via === 'phone', `an order from the iPhone arrives via="${phoneNote.params.meta?.via}"`)
// between the watch's limit and the iPhone's: shown on the iPhone, too long for the watch
const fifty = 'It is a fluoride-free spearmint toothpaste. All-One is the maker\'s motto: one human family. The label also says seventy percent organic ingredients and that it helps freshen breath and whiten teeth without any harsh additives at all. It comes in a recyclable tube, and the box asks you to reuse it.'
send({ id: 10, method: 'tools/call', params: { name: 'chums_reply', arguments: { text: fifty, status: 'done' } } })
const phoneReply = await waitFor(m => m.id === 10)
const st10 = await watch('/v1/state?since=0')
ok(!phoneReply.result?.isError && /fluoride-free/.test(st10.spoken.at(-1)?.text ?? ''), `a ${fifty.split(' ').length}-word reply to the iPhone is shown`)
await watch('/v1/say', { text: 'Tell chumstest to run them again' })
const watchNote = await waitFor(m => m.method === 'notifications/claude/channel')
send({ id: 11, method: 'tools/call', params: { name: 'chums_reply', arguments: { text: fifty, status: 'done' } } })
const watchReply = await waitFor(m => m.id === 11)
ok(watchNote.params.meta?.via === 'watch' && watchReply.result?.isError, 'from the watch again: via="watch", and the same reply is too long for it')

// Claude Code opens a permission prompt -> approval card on the watch -> "yes" -> verdict back
send({ method: 'notifications/claude/channel/permission_request', params: { request_id: 'abcde', tool_name: 'Bash', description: 'Delete build folder', input_preview: '{"command":"rm -rf build"}' } })
await sleep(300)
st = await watch('/v1/state?since=0')
ok(st.approvals[0]?.requestId === 'abcde' && st.approvals[0].preview.includes('rm -rf'), 'approval card shows tool + command')
const v = await watch('/v1/say', { text: 'yes' })
ok(v.kind === 'verdict', `spoken "yes" -> ${v.echo}`)
const verdict = await waitFor(m => m.method === 'notifications/claude/channel/permission')
ok(verdict.params.request_id === 'abcde' && verdict.params.behavior === 'allow', 'session received allow verdict')

const f = await watch('/v1/say', { text: 'Tell the chalmtest session to open a pull request' })
ok(f.kind === 'order' && f.target === 'chumstest', `misheard name still routes: ${f.echo}`)
await waitFor(m => m.method === 'notifications/claude/channel')

const s = await watch('/v1/say', { text: "what's running" })
ok(s.kind === 'status', `status answer: ${s.echo}`)

ch.stdin.end()
await sleep(300)
stop()
process.exit()
