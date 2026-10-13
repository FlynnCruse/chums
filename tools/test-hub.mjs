import path from 'node:path'
import fs from 'node:fs'
import os from 'node:os'
import net from 'node:net'
import { spawnSync } from 'node:child_process'
// Hub safety checks against the running hub: delivery acks, spoken-verdict binding, cleanup on bye, the public door.
// node tools/test-hub.mjs
import { startPrivateHub } from './test-hub-private.mjs'
const { cfg, home, hub, stop } = await startPrivateHub()            // never the real hub: its sessions would get the test's orders
const H = `http://127.0.0.1:${cfg.port}`, P = `http://127.0.0.1:${cfg.publicPort}`
const call = async (base, path, body, token = cfg.token) => {
  const r = await fetch(base + path, { method: body ? 'POST' : 'GET', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: body && JSON.stringify(body) })
  return { status: r.status, body: await r.json().catch(() => null) }
}
let fails = 0; const ok = (c, m) => { console.log(c ? 'PASS' : 'FAIL', m); if (!c) fails++ }
const sid = 'acktest-' + Date.now()
await call(H, '/channel/register', { sessionId: sid, name: 'acktest', cwd: '/tmp/acktest' })
await call(H, '/v1/say', { text: 'tell acktest to run the thing' })
const a = (await call(H, `/channel/next?sessionId=${sid}`)).body.items
ok(a.length === 1 && a[0].id, 'order delivered with an id')
const b = (await call(H, `/channel/next?sessionId=${sid}`)).body.items
ok(b.length === 1 && b[0].id === a[0].id, 'unacknowledged order delivered again (lost response)')
await call(H, '/v1/say', { text: 'tell acktest to run another thing' })
const c = (await call(H, `/channel/next?sessionId=${sid}&ack=${a[0].id}`)).body.items
ok(c.length === 1 && c[0].id !== a[0].id, 'acknowledged order gone, the next one arrives')
// spoken verdicts: two requests pending
await call(H, '/channel/permission', { sessionId: sid, request_id: 'r1', tool_name: 'Bash', description: 'first', input_preview: 'ls' })
await call(H, '/channel/permission', { sessionId: sid, request_id: 'r2', tool_name: 'Bash', description: 'second', input_preview: 'pwd' })
ok((await call(H, '/v1/say', { text: 'yes' })).body.kind === 'ask', 'bare "yes" with two pending and no card asks which')
ok((await call(H, '/v1/say', { text: "yes, but don't run it" })).body.kind !== 'verdict', '"yes, but don\'t run it" is not a yes')
const v = (await call(H, '/v1/say', { text: 'Yes.', approval: 'r1' })).body
ok(v.kind === 'verdict' && /Allowed/.test(v.echo), '"Yes." with the shown card allows that card')
const st = (await call(H, '/v1/state?since=0')).body
ok(st.approvals.length === 1 && st.approvals[0].requestId === 'r2', 'only the shown request was answered')
const d = (await call(H, `/channel/next?sessionId=${sid}&ack=${c[0].id}`)).body.items
ok(d.some(it => it.type === 'verdict' && it.requestId === 'r1' && it.behavior === 'allow'), 'the verdict reaches the session')
// subagents: the hook events count them; a stop clears them
const who = (await call(H, '/v1/state?since=0')).body.sessions.find(x => x.id === sid)
const hook = (event, agent) => call(H, '/hook', { name: who.name, cwd: who.cwd ?? '', event, agent })
await hook('SubagentStart', 'ag1'); await hook('SubagentStart', 'ag2')
ok((await call(H, '/v1/state?since=0')).body.sessions.find(x => x.id === sid).subagents === 2, 'two subagents started: the watch sees 2')
await hook('SubagentStop', 'ag1')
ok((await call(H, '/v1/state?since=0')).body.sessions.find(x => x.id === sid).subagents === 1, 'one stopped: the watch sees 1')
await hook('Stop')
ok((await call(H, '/v1/state?since=0')).body.sessions.find(x => x.id === sid).subagents === 0, 'the turn stopped: no subagents')
// artifacts: a page, an HTML file and an image become pictures the watch can fetch, each said as a line
const page = await call(H, '/channel/artifact', { sessionId: sid, url: 'https://example.com', text: 'Here it is.' })
ok(page.status === 200 && page.body.kind === 'page' && page.body.w === 780 && page.body.h > 400, `a public page renders at phone width (${page.body.w}×${page.body.h})`)
ok(page.body.view?.type === 'url' && page.body.view.url === 'https://example.com' && page.body.view.name === 'example.com', 'the iPhone is given its URL')
const html = path.join(os.tmpdir(), `artifact-test-${Date.now()}.html`)
fs.writeFileSync(html, '<!doctype html><meta name=viewport content="width=device-width"><body style="margin:0;background:#D97757;height:1600px"><h1>Hi</h1>')
const doc = await call(H, '/channel/artifact', { sessionId: sid, file: html, title: 'Test page' })
ok(doc.status === 200 && doc.body.title === 'Test page' && doc.body.h >= 3000, `an HTML file renders whole, top to bottom (${doc.body.h} px)`)
const img = await call(H, '/channel/artifact', { sessionId: sid, file: path.join(import.meta.dirname, '../design/pix/reference', fs.readdirSync(path.join(import.meta.dirname, '../design/pix/reference')).find(f => f.endsWith('.png'))) })
ok(img.status === 200 && img.body.kind === 'image', `an image is shown as it is ${img.status !== 200 ? JSON.stringify(img.body) : ''}`)
ok(img.body.view?.type === 'image' && img.body.view.file === 'source.png' && img.body.view.source, 'and the iPhone gets the image itself')
// (tools/test-artifacts.mjs shows every other kind)
const blob = path.join(home, 'blob.bin')
fs.writeFileSync(blob, Buffer.from(Array.from({ length: 4096 }, (_, i) => (i * 37) & 0xff)))
ok((await call(H, '/channel/artifact', { sessionId: sid, file: blob })).status === 422, 'a file there is no picture of is refused with a reason')
const line = (await call(H, '/v1/state?since=0')).body.spoken.find(l => l.artifact?.id === page.body.id)
ok(line && line.kind === 'artifact' && line.text === 'Here it is.', 'the artifact is a line in the conversation, with its text')
for (const which of ['thumb', 'full']) {
  const r = await fetch(`${P}/v1/artifact/${page.body.id}/${which}`, { headers: { authorization: `Bearer ${cfg.watchToken}` } })
  const b = Buffer.from(await r.arrayBuffer())
  ok(r.status === 200 && r.headers.get('content-type') === 'image/jpeg' && b[0] === 0xFF && b[1] === 0xD8, `the watch fetches its ${which} through the public door (${b.length} bytes)`)
}
ok((await fetch(`${P}/v1/artifact/${page.body.id}/full`)).status === 401, 'not without the watch token')
// agents: an order sent to an agent reaches its session only; one that isn't running says so; lines carry the agent
// the default agents, in order: code, the Mac, design (their ids differ between the internal and the public tree)
// every character is its own agent; the seed souls give Squint the Mac and Peeps design
const MAC = 'squint', DESIGN = 'peeps'
const nid = MAC + '-' + Date.now()
await call(H, '/channel/register', { sessionId: nid, name: MAC, cwd: '/tmp/' + MAC })
const toNoodle = (await call(H, '/v1/say', { text: 'check my calendar', agent: MAC })).body
ok(toNoodle.kind === 'order' && toNoodle.target === MAC && !toNoodle.echo.toLowerCase().includes(MAC + ':'), 'an order to Noodle goes to Noodle, echoed without a name')
const nItems = (await call(H, `/channel/next?sessionId=${nid}`)).body.items
ok(nItems.some(it => it.type === 'order' && it.text.endsWith('check my calendar')), "Noodle's session gets it (after its soul, the first time)")
const notRunning = (await call(H, '/v1/say', { text: 'draw me an icon', agent: DESIGN })).body.echo ?? ''
ok(/^\w+ isn't running\.$/.test(notRunning), `an agent that isn't running says so (${notRunning})`)
await call(H, '/channel/reply', { sessionId: nid, text: 'Two meetings today.', status: 'done' })
const st2 = (await call(H, '/v1/state?since=0')).body
ok(st2.spoken.some(l => l.text === 'Two meetings today.' && l.agent === MAC), "Noodle's reply is tagged as Noodle's")
ok(st2.spoken.some(l => l.kind === 'echo' && l.agent === MAC), 'so is the echo of what you told it')
const ag = Object.fromEntries(st2.agents.map(a => [a.id, a]))
ok(ag[MAC]?.status === 'idle' && ag[DESIGN]?.status === 'offline', `the agents list says who's running (${st2.agents.map(a => a.id + ':' + a.status).join(', ')})`)
ok(st2.agents.length >= 8 && st2.agents.every(a => a.character === a.id && a.runtime === 'claude'), `one agent per character, each on Claude Code by default (${st2.agents.length})`)
// the runtimes installed on this Mac (none on a machine without Claude Code or Codex, like CI)
ok(Array.isArray(st2.runtimes) && st2.runtimes.every(r => ['claude', 'codex'].includes(r)), `the state says what an agent can switch to (${st2.runtimes})`)
ok((await call(H, `/v1/agents/${MAC}/runtime`, { runtime: 'gemini' })).status === 400, 'an unknown runtime is refused')
// its permission mode, from the watch or the iPhone: kept in agents.json, and its session restarts in it (the private
// hub's bin/chums-agents is a stand-in that notes what it's asked)
const perms = (await call(H, '/v1/permissions')).body
ok(perms.claude.modes.map(m => m.id).join() === 'default,acceptEdits,auto' && perms.codex.modes.map(m => m.id).join() === 'untrusted,on-request,never' &&
   [...perms.claude.modes, ...perms.codex.modes].every(m => Object.keys(m).join() === 'id,name,about' && m.name && m.about), "each runtime's modes, each with a name and what it does")
ok(perms.claude.default === 'Asks first' && perms.codex.default === 'Asks when it needs to', `and what each runs in without one (${perms.claude.default}; ${perms.codex.default})`)
fs.mkdirSync(path.join(home, '.claude'))
fs.writeFileSync(path.join(home, '.claude/settings.json'), JSON.stringify({ permissions: { defaultMode: 'auto' } }))
ok((await call(H, '/v1/permissions')).body.claude.default === 'Decides on its own', "Claude Code's is its settings' defaultMode, read when asked")
const entry = () => JSON.parse(fs.readFileSync(path.join(home, '.chums/agents.json'), 'utf8')).find(a => a.id === MAC)
const restarts = () => (fs.existsSync(path.join(home, 'chums-agents.log')) ? fs.readFileSync(path.join(home, 'chums-agents.log'), 'utf8') : '').split('\n').filter(l => l === `restart ${MAC}`).length
const permissionOf = async () => (await call(H, '/v1/state')).body.agents.find(a => a.id === MAC).permission
ok((await call(H, `/v1/agents/${MAC}/permission`, { mode: 'acceptEdits' })).body?.mode === 'acceptEdits' && entry().permissionMode === 'acceptEdits' && await permissionOf() === 'acceptEdits',
   'a Claude Code agent gets a permission mode: kept in agents.json as permissionMode, and the apps are told')
ok(restarts() === 1, 'its session restarts in it (bin/chums-agents restart)')
ok((await call(H, `/v1/agents/${MAC}/permission`, { mode: 'acceptEdits' })).status === 200 && restarts() === 1, 'the same mode again restarts nothing')
const wrong = await call(H, `/v1/agents/${MAC}/permission`, { mode: 'never' })
ok(wrong.status === 400 && entry().permissionMode === 'acceptEdits', `a mode its runtime doesn't have is refused (${wrong.body?.error})`)
ok((await call(H, `/v1/agents/${MAC}/permission`, { mode: null })).body?.mode === null && !('permissionMode' in entry()) && await permissionOf() === null && restarts() === 2,
   "no mode: permissionMode is gone, and it restarts on Claude Code's own setting")
// a step auto mode refused: one line in the agent's conversation, and a burst of them is one line a minute
const refuse = command => call(H, '/hook', { name: MAC, cwd: '/tmp/' + MAC, event: 'PermissionDenied', tool: 'Bash', input: { command } })
await refuse('security find-generic-password -s github -w')
await refuse('security find-generic-password -s npm -w')
const st3 = (await call(H, '/v1/state')).body, refusals = st3.spoken.filter(l => l.kind === 'refused')
ok(refusals.length === 1 && refusals[0].agent === MAC && refusals[0].text === 'Auto mode refused: Bash security find-generic-password…',
   `a refusal is a line in its agent's conversation ("${refusals[0]?.text}"), and a second within a minute adds none`)
ok(st3.reactions.filter(r => r.kind === 'denied' && r.session === MAC).length === 2, 'each still makes the character react')
// souls: a change said by voice is proposed (nothing saved), saved against the version seen, sent with the next order
// (once), and undone
const card0 = (await call(H, `/v1/agents/${MAC}/soul`)).body
ok(card0.name === 'Squint' && /Mac/.test(card0.owns), `Squint starts from its seed soul (${card0.name}: ${card0.owns})`)
// the soul editor is a real model call (the claude CLI, signed in); CHUMS_TEST_NO_MODEL=1 skips it (CI)
if (process.env.CHUMS_TEST_NO_MODEL) console.log('SKIP the soul editor checks (CHUMS_TEST_NO_MODEL)')
else {
const prop = (await call(H, '/v1/say', { soul: MAC, text: 'You also look after my calendar, and talk more casually.' })).body
ok(prop.kind === 'soul' && prop.proposal && /calendar/i.test(prop.soul?.owns ?? '') && prop.summary, `a spoken change comes back as a proposal: "${prop.summary}"`)
ok(!/calendar/i.test((await call(H, `/v1/agents/${MAC}/soul`)).body.owns), 'nothing is saved before Save')
const saved = (await call(H, `/v1/agents/${MAC}/soul/save`, { proposal: prop.proposal })).body
ok(/calendar/i.test(saved.owns) && saved.canUndo, 'Save keeps it')
ok((await call(H, `/v1/agents/${MAC}/soul/save`, { proposal: prop.proposal })).status === 409, "the same change can't be saved twice")
await call(H, '/v1/say', { text: 'what is on my calendar today', agent: MAC })
const o1 = (await call(H, `/channel/next?sessionId=${nid}`)).body.items.filter(it => it.type === 'order').pop()
ok(/^\[Your soul/.test(o1?.text ?? '') && /calendar/i.test(o1.text) && /what is on my calendar today$/.test(o1.text), "Noodle's next order carries its new soul, then the order")
await call(H, '/v1/say', { text: 'and tomorrow', agent: MAC })
const o2 = (await call(H, `/channel/next?sessionId=${nid}&ack=${o1.id}`)).body.items.filter(it => it.type === 'order').pop()
ok(o2?.text === 'and tomorrow', 'the one after that is just the order')
const undone = (await call(H, `/v1/agents/${MAC}/soul/undo`, {})).body
ok(!/calendar/i.test(undone.owns ?? 'calendar') && undone.name === card0.name, 'Undo puts the last version back')
const stale = (await call(H, '/v1/say', { soul: MAC, text: 'Call yourself Mochi.' })).body
await call(H, `/v1/agents/${MAC}/soul/undo`, {})
ok((await call(H, `/v1/agents/${MAC}/soul/save`, { proposal: stale.proposal })).status === 409, 'a change proposed against an older version is refused')
const vague = (await call(H, '/v1/say', { soul: DESIGN, text: 'blue' })).body
ok(vague.kind === 'soul' && (vague.clarify || vague.proposal), `something unclear gets a question back (${vague.clarify ?? vague.summary})`)
}
// a soul's parts, set one at a time from the iPhone: written as given, too long refused, Undo puts the last back
const set1 = (await call(H, `/v1/agents/${MAC}/soul/set`, { field: 'voice', value: 'Short and dry.' })).body
ok(set1.voice === 'Short and dry.', 'a part of a soul is set as written')
ok((await call(H, `/v1/agents/${MAC}/soul/set`, { field: 'owns', value: 'x'.repeat(400) })).status === 400, 'a part longer than its limit is refused')
ok((await call(H, `/v1/agents/${MAC}/soul/set`, { field: 'secret', value: 'x' })).status === 400, 'only the soul\'s parts can be set')
ok((await call(H, `/v1/agents/${MAC}/soul/undo`, {})).body.voice !== 'Short and dry.', 'Undo takes the set back')
// each agent keeps its own lines: a busy one doesn't push a quiet one's conversation out
await call(H, '/v1/say', { text: 'a line for the quiet one', agent: DESIGN })
for (let i = 0; i < 25; i++) await call(H, '/v1/say', { text: `busy line ${i}`, agent: MAC })
const lines = (await call(H, '/v1/state')).body.spoken
ok(lines.some(l => l.agent === DESIGN) && lines.filter(l => l.agent === MAC).length <= 20,
   `25 lines to one agent leave another's in place, and the apps get 20 of each at most (${lines.filter(l => l.agent === MAC).length})`)
// a message is a message: what /v1/say takes is cut at 4000 characters
await call(H, '/v1/say', { text: 'x '.repeat(5000), agent: MAC })
const huge = (await call(H, `/channel/next?sessionId=${nid}`)).body.items.filter(it => it.type === 'order').pop()
ok(huge && huge.text.length < 4000 + 2000, `a 10,000-character message reaches the agent cut to 4000 (${huge?.text.length} with its soul)`)
// the widgets' agent: the one last talked to, or the one the iPhone shows
ok((await call(H, '/v1/state')).body.focus === MAC, 'talking to an agent makes it the one the widgets show')
ok((await call(H, '/v1/focus', { agent: DESIGN })).body.focus === DESIGN && (await call(H, '/v1/state')).body.focus === DESIGN,
   'the agent the iPhone shows is the one the widgets show')
ok((await call(H, '/v1/focus', { agent: 'nobody' })).status === 404, 'only an agent can be shown')
// uploads: a picture from the iPhone lands in the uploads folder, an order names its path (and only uploads), and the
// echo of what you said shows it
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64')
const put = (token, name) => fetch(`${P}/v1/upload?name=${encodeURIComponent(name)}`, { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'image/png' }, body: png })
const up = await (await put(cfg.watchToken, '../../etc/my photo.png')).json()
ok(up.path && path.basename(path.dirname(up.path)) === 'uploads' && !up.name.includes('/') && up.artifact?.kind === 'image',
   `an upload lands in the uploads folder, its name made safe, shown as a picture (${up.name})`)
await call(H, '/v1/say', { text: 'what is this', agent: MAC, files: [up.path, '/etc/hosts'] })
const order = (await call(H, `/channel/next?sessionId=${nid}`)).body.items.filter(it => it.type === 'order' && it.text.includes('what is this')).pop()
ok(order?.text.includes(up.path) && !order.text.includes('/etc/hosts'), 'the order names the upload, and only uploads')
const updir = path.dirname(up.path)
await call(H, '/v1/say', { text: 'look closer', agent: MAC, files: [path.join(updir, '..', 'config.json'), updir, path.join(updir, '..', 'uploads', path.basename(up.path))] })
const order3 = (await call(H, `/channel/next?sessionId=${nid}&ack=${order.id}`)).body.items.filter(it => it.type === 'order' && it.text.includes('look closer')).pop()
ok(order3 && !order3.text.includes('config.json') && order3.text.endsWith(`Attached (files on this Mac; read them): ${up.path}`),
   'an order can\'t name a file outside the uploads folder, or the folder; a path through .. is given resolved')
ok((await call(H, '/v1/state?since=0')).body.spoken.some(l => l.kind === 'echo' && l.agent === MAC && l.artifact?.id === up.artifact.id),
   'the echo of what you said shows the picture')
ok((await put(cfg.token, 'x.png')).status === 401, 'uploads need the watch token on the public door')
await call(H, '/channel/bye', { sessionId: nid })
await call(H, '/channel/bye', { sessionId: sid })
ok(!(await call(H, '/v1/state?since=0')).body.approvals.some(a => a.requestId === 'r2'), 'approvals of a session that said bye are gone')
// the public door
ok((await call(P, '/v1/ping', null, cfg.watchToken)).status === 200, 'public door: watch token works')
ok((await call(P, '/channel/next?sessionId=x', null, cfg.watchToken)).status === 404, 'public door: session endpoints don\'t exist')
ok((await call(P, '/v1/ping', null, cfg.token)).status === 401, 'public door: the local token is refused')
// what anyone on the internet can send through Funnel, without a token: bytes as they come, never a crash
let exited = false
hub.on('exit', () => { exited = true })
const raw = (port, ...parts) => new Promise(resolve => {
  const s = net.connect(port, '127.0.0.1', () => s.write(Buffer.concat(parts.map(x => Buffer.isBuffer(x) ? x : Buffer.from(x)))))
  let got = ''; s.on('data', d => { got += d }); s.on('close', () => resolve(got)); s.on('error', () => resolve(got))
  setTimeout(() => s.destroy(), 5000)
})
const status = reply => Number(reply.match(/^HTTP\/1\.1 (\d+)/)?.[1] ?? 0)
const odd = Buffer.concat([Buffer.from('a'.repeat(cfg.watchToken.length - 1)), Buffer.from([0xe9])])   // right length, one byte not ASCII
ok(status(await raw(cfg.publicPort, 'GET /v1/ping HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ', odd, '\r\nConnection: close\r\n\r\n')) === 401,
   'public door: a token with a byte that isn\'t ASCII is refused')
ok([400, 404].includes(status(await raw(cfg.publicPort, 'GET // HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n'))), 'public door: a URL that doesn\'t parse is refused')
ok(status(await raw(cfg.port, 'GET // HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n')) === 400, 'local door: the same')
ok((await call(P, '/v1/../channel/next?sessionId=x', null, cfg.watchToken)).status === 404, 'public door: /v1/.. doesn\'t reach the session endpoints')
ok((await call(P, '/hook', { event: 'Stop' }, cfg.watchToken)).status === 404, 'public door: the hooks\' endpoint doesn\'t exist')
await new Promise(r => setTimeout(r, 300))
ok(!exited && (await call(P, '/v1/ping', null, cfg.watchToken)).status === 200, 'the hub is still up after all of them')
// limits on what the watch token can send
const big = await raw(cfg.publicPort, `POST /v1/upload?name=big.bin HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ${cfg.watchToken}\r\nContent-Length: ${25 * 1024 * 1024 + 1}\r\n\r\n`, 'x')
ok(status(big) === 413, 'an upload over 25 MB is refused with 413, before it is read')
const notJSON = await fetch(`${P}/v1/say`, { method: 'POST', headers: { authorization: `Bearer ${cfg.watchToken}` }, body: '{not json' })
ok(notJSON.status === 400, 'a body that isn\'t JSON is a 400')
// the apps' event log: one line per event, a new file past 10 MB, nothing of it in the hub's own log
const events = path.join(home, '.chums/watch-events.log')
await call(P, '/v1/event', { text: 'launch\nfake line' }, cfg.watchToken)
ok(/ launch fake line\n$/.test(fs.readFileSync(events, 'utf8')), 'an event with a line break is written as one line')
fs.appendFileSync(events, 'x'.repeat(10e6 + 1))
await call(P, '/v1/event', { text: 'after' }, cfg.watchToken)
ok(fs.existsSync(events + '.1') && fs.statSync(events).size < 100, 'past 10 MB the event log starts a new file')
// a second hub on the same ports says so and stops, and the first one keeps running
const second = spawnSync('node', [path.join(import.meta.dirname, '../hub/hub.mjs')], { env: { ...process.env, HOME: home, CHUMS_NO_WHISPER: '1' }, encoding: 'utf8', timeout: 10_000 })
ok(second.status === 1 && /is in use/.test(second.stderr) && (await call(H, '/v1/ping')).status === 200, 'a second hub on the same ports stops with a message; the first is still up')
// an agent written by hand without a folder or a session ID gets them (a Claude Code agent can't start without either)
const byHand = await startPrivateHub({ agents: [{ id: 'noodle', name: 'Noodle' }, { id: 'ray', runtime: 'codex', cwd: '/tmp/ray', command: ['/nonexistent/codex'] }] })
const written = JSON.parse(fs.readFileSync(path.join(byHand.home, '.chums/agents.json'), 'utf8'))
const nd = written.find(a => a.id === 'noodle'), rd = written.find(a => a.id === 'ray')
ok(/^[0-9a-f-]{36}$/.test(nd?.sessionId ?? '') && nd.cwd === path.join(byHand.home, '.chums/agents/noodle') && !rd?.sessionId && rd?.cwd === '/tmp/ray',
   'an agent written by hand gets a folder, and a Claude Code one a session ID (a Codex one gets its thread from Codex)')
byHand.stop()
// a soul change said on a Mac without Claude Code (the editor is claude -p) is an error on the watch, not a stopped hub
const noClaude = await startPrivateHub({ env: { CHUMS_CLAUDE_BIN: '/nonexistent/claude' } })
const said = await fetch(`http://127.0.0.1:${noClaude.cfg.publicPort}/v1/say`, { method: 'POST', headers: { authorization: `Bearer ${noClaude.cfg.watchToken}`, 'content-type': 'application/json' }, body: JSON.stringify({ soul: MAC, text: 'talk more casually' }) }).then(r => r.json())
const alive = await fetch(`http://127.0.0.1:${noClaude.cfg.port}/v1/ping`, { headers: { authorization: `Bearer ${noClaude.cfg.token}` } }).then(r => r.status, () => 0)
ok(said.kind === 'soul' && /Claude Code/.test(said.error ?? '') && alive === 200, `without Claude Code a soul change says why (${said.error}) and the hub stays up`)
noClaude.stop()
// a settings file that doesn't parse stops the hub, untouched, with a message that doesn't quote it (it holds the tokens)
for (const [file, text] of [['config.json', '{"token": "secret-token-1", "port": 1'], ['agents.json', '[{"id": "noodle", "sessionId": "keep-me"']]) {
  const h2 = fs.mkdtempSync(path.join(os.tmpdir(), 'chums-test-'))
  fs.mkdirSync(path.join(h2, '.chums'))
  if (file === 'agents.json') fs.writeFileSync(path.join(h2, '.chums/config.json'), JSON.stringify({ port: cfg.port + 2, publicPort: cfg.port + 3, token: 'a', watchToken: 'b' }))
  fs.writeFileSync(path.join(h2, '.chums', file), text)
  const r = spawnSync('node', [path.join(import.meta.dirname, '../hub/hub.mjs')], { env: { ...process.env, HOME: h2, CHUMS_NO_WHISPER: '1' }, encoding: 'utf8', timeout: 10_000 })
  ok(r.status === 1 && fs.readFileSync(path.join(h2, '.chums', file), 'utf8') === text && r.stderr.includes(file) && !r.stderr.includes('secret-token') && !r.stderr.includes('keep-me'),
     `a ${file} that isn't valid JSON stops the hub and is left as it was`)
  fs.rmSync(h2, { recursive: true, force: true })
}
console.log(fails ? `${fails} FAILED` : 'all passed'); stop(); process.exit(fails ? 1 : 0)
