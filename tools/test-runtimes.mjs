// Agents the hub runs itself (hub/runtimes.mjs), against stand-ins: an Agent Client Protocol agent
// (tools/fake-acp-agent.mjs, as `copilot --acp` would be) and a Codex app-server (tools/fake-codex.mjs). The watch's
// side is the hub's API, as in tools/test-hub.mjs. No real Codex or Copilot: tools/e2e-runtimes.mjs runs those.
// node tools/test-runtimes.mjs
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { startPrivateHub } from './test-hub-private.mjs'
import { spokenLine } from '../hub/runtimes.mjs'

const work = fs.mkdtempSync(path.join(os.tmpdir(), 'chums-rt-'))
const LOG = path.join(work, 'fake.log')
const agents = [
  { id: 'acpy', name: 'Acpy', character: 'ray', runtime: 'acp', command: [process.execPath, path.join(import.meta.dirname, 'fake-acp-agent.mjs')], cwd: path.join(work, 'acpy') },
  { id: 'codey', name: 'Codey', character: 'squint', runtime: 'codex', command: [process.execPath, path.join(import.meta.dirname, 'fake-codex.mjs')], cwd: path.join(work, 'codey'), model: 'gpt-6-astra' },
]
const { cfg, home, stop } = await startPrivateHub({ agents, env: { FAKE_LOG: LOG } })
const H = `http://127.0.0.1:${cfg.port}`
const call = async (p, body) => {
  const r = await fetch(H + p, { method: body ? 'POST' : 'GET', headers: { authorization: `Bearer ${cfg.token}`, 'content-type': 'application/json' }, body: body && JSON.stringify(body) })
  return { status: r.status, body: await r.json().catch(() => null) }
}
const state = async () => (await call('/v1/state?since=0')).body
const sleep = ms => new Promise(r => setTimeout(r, ms))
const until = async (what, f, ms = 8000) => {
  const end = Date.now() + ms
  for (;;) { const v = await f(); if (v) return v; if (Date.now() > end) { console.log('  (timed out waiting for', what + ')'); return null } await sleep(100) }
}
const noted = () => fs.existsSync(LOG) ? fs.readFileSync(LOG, 'utf8').trim().split('\n').map(l => JSON.parse(l)) : []
let fails = 0; const ok = (c, m) => { console.log(c ? 'PASS' : 'FAIL', m); if (!c) fails++ }
const agentOf = async id => (await state()).agents.find(a => a.id === id)
const spokenBy = async (id, text) => until(`"${text}"`, async () => (await state()).spoken.find(l => l.agent === id && (text instanceof RegExp ? text.test(l.text) : l.text === text)))
const cardFor = async id => until(`a card for ${id}`, async () => (await state()).approvals.find(a => a.session === id))
const say = (agent, text) => call('/v1/say', { text, agent })

// ---------- the spoken line a hub-run agent's answer becomes ----------
ok(spokenLine('Tests pass: all `12` of them, in **3 seconds**. More here.') === 'Tests pass: all 12 of them, in 3 seconds.', 'an answer is said as its first sentence, without markdown')
ok(spokenLine('Saved it to /Users/x/Developer/app/notes.md for you.') === 'Saved it to notes.md for you.', 'paths are said as file names')
ok(spokenLine('See https://example.com/a/b for it.') === 'See a link for it.', 'links are "a link"')
ok(spokenLine('one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen').split(' ').length === 15, 'and it is 15 words at most')

// ---------- an Agent Client Protocol agent ----------
ok(await until('acpy up', async () => (await agentOf('acpy'))?.status === 'idle'), 'the ACP agent starts with the hub and shows as idle')
ok((await agentOf('acpy')).runtime === 'acp', 'the watch is told which runtime it is')
const savedAcp = JSON.parse(fs.readFileSync(path.join(home, '.chums/agents.json'), 'utf8')).find(a => a.id === 'acpy').sessionId
ok(/^fake-/.test(savedAcp ?? ''), `its session id is kept in agents.json (${savedAcp})`)
const mcp = noted().find(n => n.agent === 'acp' && n.method === 'session/new')?.params.mcpServers?.[0]
ok(mcp?.name === 'chums' && mcp.args[0].endsWith('channel/chums-channel.mjs') && mcp.env.some(e => e.name === 'CHUMS_SESSION'), 'its session gets the Chums MCP server, bound to its hub session')

const o1 = (await say('acpy', 'run the tool please')).body
ok(o1.kind === 'order' && o1.target === 'acpy', `an order to it is routed like any other (${o1.echo})`)
const said1 = await spokenBy('acpy', 'Tests pass: all 12 of them, in 3 seconds.')
ok(said1?.kind === 'done', "a turn that didn't call chums_reply is answered with its last message's first sentence")
const p1 = noted().find(n => n.agent === 'acp' && n.method === 'session/prompt')?.text ?? ''
ok(/^\[Standing instructions from Chums/.test(p1) && /chums_reply/.test(p1) && /\[From the watch\] \[Your soul/.test(p1) && /run the tool please$/.test(p1),
  'the first prompt carries the standing instructions, then the watch mark, its soul and the order')
const st1 = await state()
const t1 = st1.tools.filter(t => t.session === 'acpy')
ok(t1.some(t => t.type === 'test' && /npm test/.test(t.text) && t.ok === true) && t1.some(t => t.type === 'read' && t.text === 'Read package.json'),
  `its tool calls are events on the watch (${t1.map(t => `${t.text}:${t.ok}`).join(', ')})`)
ok(t1.some(t => t.type === 'stop') && (await agentOf('acpy')).status === 'idle', 'the end of the turn is a stop, and it is idle again')
ok(!st1.spoken.some(l => /replayed/.test(l.text)), 'nothing it replays is news')

await say('acpy', 'approve the cleanup')
const c1 = await cardFor('acpy')
ok(c1?.summary === 'rm -rf build' && c1.tool === 'Bash', `its permission request is an approval card (${c1?.summary})`)
ok((await agentOf('acpy')).status === 'waiting' && (await agentOf('acpy')).needs, 'and it waits for him')
ok((await say('acpy', 'yes')).body.kind === 'verdict', 'a spoken yes answers it')
ok(await spokenBy('acpy', 'Deleted the build folder.'), 'the agent carries on')
ok(noted().filter(n => n.permission).pop()?.permission?.optionId === 'yes-once', 'yes is "allow once", never "always"')
await say('acpy', 'approve another one')
await until('the second card', async () => (await state()).approvals.length === 1)
await say('acpy', 'no')
ok(await spokenBy('acpy', 'Okay, I left it.'), 'a spoken no denies it')
ok(noted().filter(n => n.permission).pop()?.permission?.optionId === 'no', 'no is "reject once"')

await say('acpy', 'reply by the tool')
ok(await spokenBy('acpy', 'Replied through the tool.'), 'chums_reply from its MCP server speaks on the watch')
const chumsAsk = noted().find(n => n.chumsPermission)?.chumsPermission
ok(chumsAsk?.optionId === 'ok' && !(await state()).approvals.length, "Chums' own tools are allowed without a card")
await sleep(300)
ok(!(await state()).spoken.some(l => /long final message/.test(l.text)), "once it spoke, its final message isn't said too")
const tools = noted().find(n => n.mcpTools)?.mcpTools ?? []
ok(tools.length === 2 && tools.every(t => t.annotations?.readOnlyHint === true), 'the MCP server offers chums_reply and chums_show, marked read-only')

await say('acpy', 'refuse this')
ok(await until('blocked', async () => (await agentOf('acpy')).status === 'blocked'), 'a refusal leaves it blocked')
await say('acpy', 'limit please')
ok(await until('limited', async () => (await agentOf('acpy')).status === 'limited'), 'a rate limit leaves it limited')

await say('acpy', 'crash now')
ok(await until('offline', async () => (await agentOf('acpy')).status === 'offline'), 'when its process dies it goes offline')
ok(await until('back', async () => (await agentOf('acpy')).status === 'idle', 15000), 'and the hub starts it again')
ok(noted().filter(n => n.agent === 'acp' && n.method === 'session/load').pop()?.params.sessionId === savedAcp, 'carrying on the same session (session/load)')

// ---------- a Codex app-server ----------
ok(await until('codey up', async () => (await agentOf('codey'))?.status === 'idle'), 'the Codex agent starts with the hub and shows as idle')
const started = noted().find(n => n.agent === 'codex' && n.started)
ok(started?.started === 'app-server' && started.config.some(c => c.startsWith('mcp_servers.chums.command=')) && started.config.some(c => /CHUMS_SESSION = "/.test(c)),
  'it runs `codex app-server` with the Chums MCP server configured')
const ts = noted().find(n => n.agent === 'codex' && n.method === 'thread/start')?.params
ok(ts?.model === 'gpt-6-astra' && ts.approvalPolicy === 'on-request' && ts.sandbox === 'workspace-write' && /chums_reply/.test(ts.developerInstructions) && /id: codey/.test(ts.developerInstructions),
  'its thread gets the model, on-request approvals in the workspace sandbox, and the standing instructions as developer instructions')
const savedThread = JSON.parse(fs.readFileSync(path.join(home, '.chums/agents.json'), 'utf8')).find(a => a.id === 'codey').sessionId
ok(/^thr-/.test(savedThread ?? ''), `its thread id is kept in agents.json (${savedThread})`)
ok(noted().some(n => n.method === 'thread/name/set' && n.params.name === 'Chums: Codey' && n.params.threadId === savedThread), 'its thread is named after the agent, for Codex\'s own lists')
const rt = JSON.parse(fs.readFileSync(path.join(home, '.chums/agents/codey.runtime.json'), 'utf8'))
ok(rt.thread === savedThread && rt.socket.endsWith(`${cfg.port}-codey.sock`), 'and bin/chums-agents open can find its thread and socket')

await say('codey', 'run the tool')
ok(await spokenBy('codey', 'All tests pass.'), 'its final answer is said when it didn\'t call chums_reply')
const t2 = (await state()).tools.filter(t => t.session === 'codey')
ok(t2.some(t => t.text === 'Bash npm test' && t.type === 'test' && t.ok) && t2.some(t => t.text === 'Read package.json'),
  `its commands are events, read as what they do (${t2.map(t => t.text).join(', ')})`)
ok(/^\[From the watch\] \[Your soul/.test(noted().find(n => n.method === 'turn/start')?.params.input[0].text ?? ''), 'its turn carries the watch mark and its soul')

await say('codey', 'approve this')
const c2 = await cardFor('codey')
ok(c2?.summary === 'rm -rf build', `a command approval is a card (${c2?.summary})`)
await say('codey', 'yes')
ok(await spokenBy('codey', 'Deleted it.'), 'yes lets it run')
ok(noted().filter(n => n.decision).pop()?.decision === 'accept', 'as "accept"')
await say('codey', 'edit with approval')
const c3 = await cardFor('codey')
ok(c3?.summary === 'edit a.js', `a file change approval is a card (${c3?.summary})`)
await say('codey', 'no')
ok(await spokenBy('codey', 'Done with the edit.') && noted().filter(n => n.fileDecision).pop()?.fileDecision === 'decline', 'no declines it')

await say('codey', 'answered elsewhere')
ok(await cardFor('codey'), 'a card appears')
ok(await until('the card gone', async () => !(await state()).approvals.length), 'and goes when a Codex terminal on the thread answers first')
ok(await spokenBy('codey', 'Deployed.'), 'the turn carries on')

await say('codey', 'reply via the tool')
ok(await spokenBy('codey', 'Codex replied by tool.'), "chums_reply from Codex's MCP server speaks on the watch")
await sleep(300)
ok(!(await state()).spoken.some(l => /stays on the Mac/.test(l.text)), 'and its final message is not said too')
ok(!(await state()).tools.some(t => /chums/.test(t.text)), "Chums' own tool calls aren't events")

await say('codey', 'compact then go on')
ok(await spokenBy('codey', 'Compacted and carried on.'), 'it compacts and carries on')

await say('codey', 'steer a long one')
await until('working', async () => (await agentOf('codey')).status === 'working')
await sleep(200)
await say('codey', 'and one more thing')
ok(await spokenBy('codey', 'Steered.'), 'an order while it works joins the turn (turn/steer)')
ok(noted().some(n => n.method === 'turn/steer' && /and one more thing$/.test(n.params.input[0].text)), 'with what he said')

await say('codey', 'hit the limit')
ok(await until('limited', async () => (await agentOf('codey')).status === 'limited'), 'a usage limit leaves it limited')

// ---------- its model, chosen on its card on the iPhone ----------
fs.mkdirSync(path.join(home, '.codex'), { recursive: true })
fs.writeFileSync(path.join(home, '.codex/models_cache.json'), JSON.stringify({ models: [
  { slug: 'gpt-6-luna', display_name: 'GPT-6-Luna', description: 'Fast.', visibility: 'list', priority: 4 },
  { slug: 'gpt-6-astra', display_name: 'GPT-6-Astra', description: 'Frontier.', visibility: 'list', priority: 2 },
  { slug: 'gpt-hidden', display_name: 'Hidden', visibility: 'hide', priority: 1 },
] }))
fs.writeFileSync(path.join(home, '.codex/config.toml'), 'model = "gpt-6-astra"\n[profiles.x]\nmodel = "other"\n')
const models = (await call('/v1/models')).body
ok(models.codex.models.map(m => m.id).join() === 'gpt-6-astra,gpt-6-luna' && models.codex.default === 'GPT-6-Astra',
  `Codex offers the models its cache lists for the account, in its order, and says what it uses by default (${models.codex.default})`)
ok(models.claude.models.map(m => m.id).join() === 'fable,opus,sonnet,haiku', 'Claude Code offers its aliases')
ok((await call('/v1/agents/codey/model', { model: 'gpt-hidden' })).status === 400, "a model Codex doesn't list is refused")
const resumes = () => noted().filter(n => n.agent === 'codex' && n.method === 'thread/resume')
const before = resumes().length
ok((await call('/v1/agents/codey/model', { model: 'gpt-6-luna' })).body?.model === 'gpt-6-luna', 'an agent gets another model')
ok(await until('restarted on it', async () => resumes().length > before && resumes().pop().params.model === 'gpt-6-luna'),
  'it restarts on it, on the same thread')
ok(JSON.parse(fs.readFileSync(path.join(home, '.chums/agents.json'), 'utf8')).find(a => a.id === 'codey').model === 'gpt-6-luna' && (await agentOf('codey')).model === 'gpt-6-luna',
  'kept in agents.json, and the iPhone is told')
await call('/v1/agents/codey/model', { model: null })
ok(await until('back on the default', async () => resumes().pop()?.params.model === null && (await agentOf('codey')).model === null),
  "no model: Codex's own setting again")

// ---------- its permission mode, chosen on the watch or the iPhone ----------
ok((await call('/v1/permissions')).body.codex.default === 'Asks when it needs to', "without a mode of its own it asks when it needs to (on-request)")
ok((await call('/v1/agents/codey/permission', { mode: 'auto' })).status === 400, "a mode Codex doesn't have is refused")
let n = resumes().length
ok((await call('/v1/agents/codey/permission', { mode: 'untrusted' })).body?.mode === 'untrusted', 'an agent gets another approval policy')
ok(await until('restarted in it', async () => resumes().length > n && resumes().pop().params.approvalPolicy === 'untrusted'),
  'it restarts in it, on the same thread')
ok(JSON.parse(fs.readFileSync(path.join(home, '.chums/agents.json'), 'utf8')).find(a => a.id === 'codey').approvalPolicy === 'untrusted' && (await agentOf('codey')).permission === 'untrusted',
  'kept in agents.json as approvalPolicy, and the apps are told')
n = resumes().length
await call('/v1/agents/codey/permission', { mode: null })
ok(await until('back on the default', async () => resumes().length > n && resumes().pop().params.approvalPolicy === 'on-request' && (await agentOf('codey')).permission === null),
  'no mode: on-request again')
fs.writeFileSync(path.join(home, '.codex/config.toml'), 'model = "gpt-6-astra"\napproval_policy = "never"\n')
ok((await call('/v1/permissions')).body.codex.default === 'Never asks', "with approval_policy in Codex's config.toml, that is its default")
n = resumes().length
await call('/v1/agents/codey/model', { model: 'gpt-6-luna' })
ok(await until('restarted', async () => resumes().length > n && resumes().pop().params.approvalPolicy === 'never'), 'and what it runs in')

// ---------- and the Claude Code path is untouched: a channel session still registers and gets orders ----------
await call('/channel/register', { sessionId: 'cc-1', name: 'demo', cwd: '/tmp/demo' })
await say(null, 'tell demo to say hi')
const items = (await call('/channel/next?sessionId=cc-1')).body.items
ok(items.some(i => i.type === 'order' && /say hi$/.test(i.text)), 'a Claude Code session still gets its orders through the channel')

console.log(fails ? `${fails} FAILED` : 'all passed')
stop(); fs.rmSync(work, { recursive: true, force: true })
process.exit(fails ? 1 : 0)
