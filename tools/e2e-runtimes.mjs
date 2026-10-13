// Real end to end, for the agents the hub runs itself: a private hub runs a real Codex or Copilot agent in a fresh
// folder, and this plays the watch: a question, a command that needs approval (allowed), another one (denied), the
// chums_reply tool. Codex also: a file edit, chums_show, an order while it works (steering), a Codex terminal on the
// same thread (bin/chums-codex: the watch's orders show in it, and what's typed in it reaches the agent), another app's
// app-server on the thread, its app-server dying, and the hub itself killed and started again. Its thread is archived
// at the end (CHUMS_E2E_KEEP=1 keeps it).
// It uses your Codex / Copilot logins and spends a few model calls (Codex: about 14 turns).
//   node tools/e2e-runtimes.mjs codex [model]          codex app-server        (default model gpt-6-astra)
//   node tools/e2e-runtimes.mjs copilot [model]        the Copilot SDK         (default model gpt-5-mini)
//   node tools/e2e-runtimes.mjs copilot-acp [model]    `copilot --acp`         (default model gpt-5-mini)
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { startPrivateHub } from './test-hub-private.mjs'

const [which = 'codex', model] = process.argv.slice(2)
const work = fs.mkdtempSync(path.join(os.tmpdir(), `chums-e2e-${which}-`))
const cwd = path.join(work, 'project')
fs.mkdirSync(cwd)
const agent = {
  codex: { runtime: 'codex', model: model ?? 'gpt-6-astra', approvalPolicy: 'untrusted' },   // untrusted: every command asks
  copilot: { runtime: 'copilot', model: model ?? 'gpt-5-mini' },
  'copilot-acp': { runtime: 'acp', command: ['copilot', '--acp', '--no-auto-update', '--model', model ?? 'gpt-5-mini'] },
}[which]
if (!agent) { console.error('codex, copilot or copilot-acp'); process.exit(2) }
const ID = 'e2e'
const logFile = path.join(work, 'hub.log')
let { cfg, home, hub, stop } = await startPrivateHub({ agents: [{ id: ID, name: 'Tester', character: 'ray', cwd, ...agent }], logFile, env: { CHUMS_RUNTIME_DEBUG: '1' } })
const H = `http://127.0.0.1:${cfg.port}`
const call = async (p, body, again = true) => {
  try { return await (await fetch(H + p, { method: body ? 'POST' : 'GET', headers: { authorization: `Bearer ${cfg.token}`, 'content-type': 'application/json' }, body: body && JSON.stringify(body) })).json() }
  catch (e) { if (!again) throw e; await new Promise(r => setTimeout(r, 500)); return call(p, body, false) }    // a kept-alive socket the hub closed
}
const state = () => call('/v1/state?since=0')
const sleep = ms => new Promise(r => setTimeout(r, ms))
let fails = 0; const ok = (c, m) => { console.log(c ? 'PASS' : 'FAIL', m); if (!c) fails++ }
const t0 = Date.now(), at = () => `${((Date.now() - t0) / 1000).toFixed(1)}s`

// every status the watch would have shown, in order
const seen = []
let watching = true
;(async () => { while (watching) { const a = (await state().catch(() => null))?.agents?.find(x => x.id === ID); const st = a?.status; if (st && st !== seen.at(-1)) seen.push(st); await sleep(250) } })()
const until = async (what, f, ms) => { const end = Date.now() + ms; for (;;) { const v = await f(); if (v) return v; if (Date.now() > end) { console.log(`  (no ${what} after ${ms / 1000} s)`); return null } await sleep(300) } }
const newLine = async (since, ms = 180_000) => until('spoken line', async () => (await state()).spoken.find(l => l.agent === ID && l.at > since && l.kind !== 'echo' && l.kind !== 'verdict'), ms)

console.log(`${which}: ${JSON.stringify(agent)} in ${cwd}`)
ok(await until('agent', async () => (await state()).agents.find(a => a.id === ID)?.status === 'idle', 120_000), `${at()} the agent is up (idle)`)

let since = Date.now()
await call('/v1/say', { agent: ID, text: 'What is seven times six? Just answer.' })
const a1 = await newLine(since)
ok(a1 && /42|forty.two/i.test(a1.text), `${at()} a question gets a spoken answer: "${a1?.text}"`)

since = Date.now()
await call('/v1/say', { agent: ID, text: 'Use the shell to run exactly this command: echo approved-from-watch > chums-proof.txt' })
const card = await until('approval card', async () => (await state()).approvals.find(x => x.session === ID), 180_000)
ok(card, `${at()} the command asks for approval on the watch: ${card?.tool} "${card?.summary}"`)
if (card) await call('/v1/say', { agent: ID, text: 'yes', approval: card.requestId })
const proof = path.join(cwd, 'chums-proof.txt')
ok(await until('proof file', async () => fs.existsSync(proof), 120_000), `${at()} allowed from the watch, it ran: chums-proof.txt exists`)
const a2 = await newLine(since)
ok(a2, `${at()} and it said so: "${a2?.text}"`)

since = Date.now()
await call('/v1/say', { agent: ID, text: 'Use the shell to run exactly this command: rm chums-proof.txt' })
const card2 = await until('second card', async () => (await state()).approvals.find(x => x.session === ID), 180_000)
ok(card2, `${at()} a second command asks too: "${card2?.summary}"`)
if (card2) await call('/v1/say', { agent: ID, text: 'no', approval: card2.requestId })
// after a no, the agent may say so, or just end its turn (the watch has already said "Denied")
const stopped = () => state().then(st => st.tools.some(t => t.session === ID && t.type === 'stop' && t.at > since))
const a3 = await until('spoken line or the end of the turn', async () => (await state()).spoken.find(l => l.agent === ID && l.at > since && !['echo', 'verdict'].includes(l.kind)) ?? (await stopped() && { text: null }), 180_000)
ok(fs.existsSync(proof), `${at()} denied from the watch, it didn't run: the file is still there`)
ok(a3, `${at()} and its turn ended: ${a3?.text ? `it said "${a3.text}"` : 'it said nothing more'}`)

// the Chums MCP server's own tool, asked for by name (the agents above may simply have answered in their final message)
const spokenForIt = () => (fs.readFileSync(logFile, 'utf8').match(/spoken for e2e/g) ?? []).length
await sleep(1500)
const before = spokenForIt()
since = Date.now()
await call('/v1/say', { agent: ID, text: 'Call the chums_reply tool now with the text "Tool check passed." and status done.' })
const a4 = await newLine(since)
await sleep(1500)
const toolSpoke = a4 && /tool check/i.test(a4.text) && spokenForIt() === before
// Copilot CLI 1.0.32 over ACP doesn't start a session's stdio MCP servers, so there the hub speaks for it
if (agent.runtime === 'acp' && !toolSpoke) console.log(`NOTE ${at()} no chums_reply tool over ACP with this agent; the hub said its final message: "${a4?.text}"`)
else ok(toolSpoke, `${at()} chums_reply, the MCP tool, speaks on the watch: "${a4?.text}"`)

const toolsSeen = (await state()).tools.filter(t => t.session === ID)
if (agent.runtime === 'codex') {
  const hostLog = () => fs.readFileSync(path.join(home, '.chums/agents', `${ID}.host.log`), 'utf8')
  const status = async () => (await state()).agents.find(a => a.id === ID)?.status
  // answers yes to every card for a while: the steps below are about something else
  const allowAll = async (done, ms = 240_000) => until('the step', async () => {
    const cards = (await state()).approvals.filter(x => x.session === ID)
    for (const c of cards) await call('/v1/say', { agent: ID, text: 'yes', approval: c.requestId })
    return cards.length ? null : done()                          // never done with a card still up
  }, ms)

  // a file edit with Codex's own patch tool is an edit event
  since = Date.now()
  await call('/v1/say', { agent: ID, text: 'Use your file editing tool, apply_patch, not the shell, to create notes.txt containing the word hello.' })
  await allowAll(async () => fs.existsSync(path.join(cwd, 'notes.txt')) && (await state()).tools.some(t => t.session === ID && t.type === 'stop' && t.at > since))
  const edits = (await state()).tools.filter(t => t.session === ID && t.at > since && t.type === 'edit')
  ok(fs.existsSync(path.join(cwd, 'notes.txt')) && edits.some(t => /notes\.txt/.test(t.text)), `${at()} a file it writes is an edit event: ${edits.map(t => t.text).join(', ') || 'none'}`)

  // chums_show: a picture on the watch
  since = Date.now()
  await call('/v1/say', { agent: ID, text: 'Write circle.svg, a 200 by 200 SVG with one red circle, then call the chums_show tool with file set to its absolute path and title Red circle.' })
  const shown = await allowAll(async () => (await state()).spoken.find(l => l.agent === ID && l.at > since && l.artifact), 300_000)
  let thumb = null
  if (shown) { const r = await fetch(`${H}/v1/artifact/${shown.artifact.id}/thumb`, { headers: { authorization: `Bearer ${cfg.watchToken}` } }); const b = Buffer.from(await r.arrayBuffer()); thumb = r.ok && b[0] === 0xFF && b[1] === 0xD8 }
  ok(shown && thumb, `${at()} chums_show puts a picture on the watch: "${shown?.artifact?.title}" ${shown?.artifact?.w}×${shown?.artifact?.h}, "${shown?.text}"`)

  // an order said while it works joins the turn in progress (turn/steer): one turn, one stop, both answered
  const stops = after => state().then(st => st.tools.filter(t => t.session === ID && t.type === 'stop' && t.at > after).length)
  since = Date.now()
  await call('/v1/say', { agent: ID, text: 'Run the shell command sleep 8, then tell me it finished.' })
  await allowAll(async () => (await state()).tools.some(t => t.session === ID && t.at > since && /sleep 8/.test(t.text)), 120_000)
  await sleep(1500)
  const during = await status()
  const since2 = Date.now()
  await call('/v1/say', { agent: ID, text: 'Also, what is two plus three?' })
  await allowAll(async () => (await state()).tools.some(t => t.session === ID && t.type === 'stop' && t.at > since2), 180_000)
  const lines = (await state()).spoken.filter(l => l.agent === ID && l.at > since && !['echo', 'verdict'].includes(l.kind)).map(l => l.text)
  const n = await stops(since)
  const refused = hostLog().split('\n').filter(l => /steer refused|order waits/.test(l)).pop()
  ok(during === 'working' && n === 1 && lines.some(l => /\b5\b|five/i.test(l)) && !refused,
    `${at()} an order while it works joins that turn (status then: ${during}; ${n} turn${refused ? `; ${refused.slice(20)}` : ''}; said: ${lines.map(l => `"${l}"`).join(', ')})`)

  // a Codex terminal on the agent's thread (bin/chums-codex): what the watch says shows in it as it happens, and what
  // is typed in it goes to the same agent; the watch sees that turn's work and doesn't speak it
  const steps = [{ wait: 7 }, { mark: 'A' }, { wait: 16 }, { mark: 'B' }, { type: 'What is nine plus ten? Just the number.' }, { key: 'enter' }, { wait: 25 }]
  const T0 = Date.now()
  const term = new Promise(resolve => {
    const p = spawn('python3', [path.join(import.meta.dirname, 'pty-run.py'), JSON.stringify(steps), '/bin/zsh', path.join(import.meta.dirname, '../bin/chums-codex'), ID], { env: { ...process.env, HOME: home } })
    let out = ''; p.stdout.on('data', d => { out += d }); p.on('close', () => resolve(out))
  })
  await sleep(8000)
  since = Date.now()
  await call('/v1/say', { agent: ID, text: 'What is the capital of France? One word.' })
  const a7 = await newLine(since)
  const [before = '', live = '', typed = ''] = (await term).split(/###[AB]###/)
  const typedAt = T0 + 23_000
  ok(/OpenAICodex/.test(before) && !/capitalofFrance/i.test(before) && /capitalofFrance/i.test(live) && /Paris/.test(live) && /Paris/.test(a7?.text ?? ''),
    `${at()} chums-codex: a Codex terminal on the thread shows the watch's order and answer as they happen`)
  ok(/nineplusten/i.test(typed) && /19/.test(typed), `${at()} what is typed in it goes to the agent, which answers there`)
  const st5 = await state()
  ok(st5.tools.some(t => t.session === ID && t.type === 'stop' && t.at > typedAt) && !st5.spoken.some(l => l.agent === ID && l.at > typedAt && !['echo', 'verdict'].includes(l.kind)),
    `${at()} the watch sees that turn, and doesn't speak it`)
  ok(await status() === 'idle', `${at()} quitting the terminal leaves the agent on the watch`)

  // another app-server process on the thread (the desktop app's or the IDE extension's own): it can read the thread,
  // not continue it while the hub runs it (one writer per thread)
  const other = spawn('codex', ['app-server'], { stdio: ['pipe', 'pipe', 'ignore'], cwd })
  const answers = new Map(); let n2 = 0
  other.stdout.on('data', d => { for (const l of String(d).split('\n').filter(Boolean)) { try { const m = JSON.parse(l); if (m.id != null && !m.method) answers.get(m.id)?.(m) } catch {} } })
  const ask2 = (method, params) => new Promise(r => { const i = ++n2; answers.set(i, r); other.stdin.write(JSON.stringify({ id: i, method, params }) + '\n'); setTimeout(() => r({ error: { message: 'no answer' } }), 60_000) })
  await ask2('initialize', { clientInfo: { name: 'chums-e2e', title: null, version: '0' }, capabilities: null }); other.stdin.write('{"method":"initialized"}\n')
  const thread = JSON.parse(fs.readFileSync(path.join(home, '.chums/agents', `${ID}.runtime.json`), 'utf8')).thread
  const read = await ask2('thread/read', { threadId: thread, includeTurns: false }), resume = await ask2('thread/resume', { threadId: thread, excludeTurns: true })
  other.kill()
  ok(!read.error && /^Chums: /.test(read.result.thread.name ?? '') && /active writer/.test(resume.error?.message ?? ''),
    `${at()} another Codex app (its own app-server) can read the thread ("${read.result?.thread?.name}") but not continue it while the hub runs it: ${resume.error?.message ?? 'it could!'}`)

  // its app-server dies: the hub starts it again on the same thread, which remembers the conversation
  const rt = JSON.parse(fs.readFileSync(path.join(home, '.chums/agents', `${ID}.runtime.json`), 'utf8'))
  process.kill(rt.pid)
  ok(await until('offline', async () => await status() === 'offline', 20_000), `${at()} its app-server killed, it goes offline`)
  ok(await until('back', async () => await status() === 'idle', 60_000), `${at()} and comes back`)
  const rt2 = JSON.parse(fs.readFileSync(path.join(home, '.chums/agents', `${ID}.runtime.json`), 'utf8'))
  ok(rt2.thread === rt.thread && rt2.pid !== rt.pid, `${at()} on the same thread (${rt2.thread})`)
  since = Date.now()
  await call('/v1/say', { agent: ID, text: 'What number did you answer to my first question today?' })
  const a5 = await newLine(since)
  ok(a5 && /42|forty.two/i.test(a5.text), `${at()} and remembers it: "${a5?.text}"`)

  // the hub itself is killed (as launchd might), leaving its app-server behind; the next hub stops that one and
  // carries on the thread
  hub.kill('SIGKILL')
  await sleep(1000)
  const alive = pid => { try { process.kill(pid, 0); return true } catch { return false } }
  const orphan = rt2.pid, orphanWasAlive = alive(orphan)
  ;({ cfg, home, hub, stop } = await startPrivateHub({ home, logFile, env: { CHUMS_RUNTIME_DEBUG: '1' } }))
  ok(await until('back after the hub', async () => await status() === 'idle', 60_000), `${at()} a new hub on the same folder brings it back`)
  const rt3 = JSON.parse(fs.readFileSync(path.join(home, '.chums/agents', `${ID}.runtime.json`), 'utf8'))
  ok(orphanWasAlive && !alive(orphan) && rt3.thread === rt.thread, `${at()} the app-server the killed hub left (pid ${orphan}) is stopped, the thread is the same`)
  since = Date.now()
  await call('/v1/say', { agent: ID, text: 'What file did you create with apply_patch earlier? Just the name.' })
  const a6 = await newLine(since)
  ok(a6 && /notes/i.test(a6.text), `${at()} and remembers: "${a6?.text}"`)
}

await sleep(1000)
watching = false
ok(toolsSeen.some(t => t.type === 'bash' || t.type === 'test'), `tool calls were events: ${toolsSeen.map(t => `${t.text}${t.ok === false ? ' ✗' : ''}`).join(' | ')}`)
ok(seen.includes('working') && seen.includes('waiting') && seen.at(-1) === 'idle', `statuses on the watch: ${seen.join(' → ')}`)
const log = fs.readFileSync(logFile, 'utf8')
const viaTool = (log.match(/reply <- e2e/g) ?? []).length, spokenFor = (log.match(/spoken for e2e/g) ?? []).length
console.log(`replies: ${viaTool} spoken, ${viaTool - spokenFor} by chums_reply, ${spokenFor} from the final message`)
console.log(`agent log: ${path.join(home, '.chums/agents', `${ID}.host.log`)}`)
console.log(fs.readFileSync(path.join(home, '.chums/agents', `${ID}.host.log`), 'utf8').split('\n').slice(-12).join('\n'))
console.log(fails ? `${fails} FAILED` : 'all passed', `(${at()})`)
const sessionId = JSON.parse(fs.readFileSync(path.join(home, '.chums/agents.json'), 'utf8'))[0].sessionId
stop()
// a test's thread shouldn't stay in your Codex history (archived, not deleted: `codex unarchive <id>` brings it back)
if (agent.runtime === 'codex' && sessionId && !process.env.CHUMS_E2E_KEEP) { await sleep(1500); spawn('codex', ['archive', sessionId], { stdio: 'ignore' }).on('close', c => { console.log(`archived its thread ${sessionId}${c ? ` (codex archive exited ${c})` : ''}`); process.exit(fails ? 1 : 0) }) }
else process.exit(fails ? 1 : 0)
