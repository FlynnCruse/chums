// A stand-in `codex app-server --listen unix://…` for tools/test-runtimes.mjs: a WebSocket on a Unix socket speaking
// the app-server's JSON-RPC. What a turn does depends on words in it (tool, approve, edit, elsewhere, limit, compact,
// reply, steer); every request is noted in $FAKE_LOG, one JSON line each.
import fs from 'node:fs'
import net from 'node:net'
import crypto from 'node:crypto'
import readline from 'node:readline'
import { spawn } from 'node:child_process'

const args = process.argv.slice(2)
const sock = args[args.indexOf('--listen') + 1].replace(/^unix:\/\//, '')
const config = args.flatMap((a, i) => a === '-c' ? [args[i + 1]] : [])
const note = o => process.env.FAKE_LOG && fs.appendFileSync(process.env.FAKE_LOG, JSON.stringify({ agent: 'codex', ...o }) + '\n')
note({ started: args[0], config })

// the MCP server the hub configured with -c mcp_servers.chums.* (TOML values: strings, arrays, an inline table)
function chumsServer() {
  const get = k => config.find(c => c.startsWith(`mcp_servers.chums.${k}=`))?.slice(`mcp_servers.chums.${k}=`.length)
  const env = Object.fromEntries([...get('env').matchAll(/(\w+) = ("(?:[^"\\]|\\.)*")/g)].map(m => [m[1], JSON.parse(m[2])]))
  return { command: JSON.parse(get('command')), args: JSON.parse(get('args')), env }
}
let mcp = null
async function chumsReply(text) {
  if (!mcp) {
    const s = chumsServer()
    const p = spawn(s.command, s.args, { env: { ...process.env, ...s.env }, stdio: ['pipe', 'pipe', 'inherit'] })
    const pending = new Map(); let id = 0
    readline.createInterface({ input: p.stdout }).on('line', l => { const m = JSON.parse(l); pending.get(m.id)?.(m); pending.delete(m.id) })
    mcp = (method, params) => new Promise(r => { const i = ++id; pending.set(i, r); p.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: i, method, params }) + '\n') })
    await mcp('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'fake-codex', version: '0' } })
    p.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n')
  }
  return mcp('tools/call', { name: 'chums_reply', arguments: { text, status: 'done' } })
}

// ---- a WebSocket server, the few parts of it the hub's client uses ----
function serve(conn, onMessage) {
  let buf = Buffer.alloc(0), open = false
  const out = text => {
    const data = Buffer.from(text), n = data.length
    const head = n < 126 ? Buffer.from([0x81, n]) : n < 65536 ? Buffer.from([0x81, 126, n >> 8, n & 255])
      : Buffer.concat([Buffer.from([0x81, 127]), (() => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(n)); return b })()])
    conn.write(Buffer.concat([head, data]))
  }
  conn.on('data', d => {
    buf = Buffer.concat([buf, d])
    if (!open) {
      const end = buf.indexOf('\r\n\r\n'); if (end < 0) return
      const key = buf.subarray(0, end).toString().match(/Sec-WebSocket-Key: (\S+)/i)[1]
      const accept = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')
      conn.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`)
      buf = buf.subarray(end + 4); open = true
    }
    while (buf.length >= 2) {
      let n = buf[1] & 127, off = 2
      if (n === 126) { n = buf.readUInt16BE(2); off = 4 } else if (n === 127) { n = Number(buf.readBigUInt64BE(2)); off = 10 }
      if (buf.length < off + 4 + n) return
      const mask = buf.subarray(off, off + 4), data = Buffer.from(buf.subarray(off + 4, off + 4 + n))
      for (let i = 0; i < n; i++) data[i] ^= mask[i & 3]
      const op = buf[0] & 15
      buf = buf.subarray(off + 4 + n)
      if (op === 8) { conn.end(); return }
      if (op === 1) onMessage(JSON.parse(data.toString()))
    }
  })
  return m => out(JSON.stringify(m))
}

let thread = null, turnN = 0, active = null, steered = null
const known = new Set(['thr-known'])
const server = net.createServer(conn => {
  let nextId = 0
  const waiting = new Map()
  const send = serve(conn, m => handle(m))
  const notify = (method, params) => send({ method, params })
  const ask = (method, params) => new Promise(r => { const id = nextId++; waiting.set(id, r); send({ id, method, params }) })
  const item = (kind, it) => notify(`item/${kind}`, { item: it, threadId: thread.id, turnId: active, [kind === 'started' ? 'startedAtMs' : 'completedAtMs']: Date.now() })
  const sleep = ms => new Promise(r => setTimeout(r, ms))
  const message = text => { const it = { type: 'agentMessage', id: `m${Math.random()}`, text, phase: 'final_answer' }; item('started', { ...it, text: '' }); item('completed', it) }
  const done = (status = 'completed', error = null) => { notify('turn/completed', { threadId: thread.id, turn: { id: active, items: [], status, error } }); active = null }

  async function turn(text) {
    if (/limit/.test(text)) return done('failed', { message: 'You hit your usage limit.', codexErrorInfo: 'usageLimitExceeded' })
    if (/tool/.test(text)) {
      const cmd = { type: 'commandExecution', id: 'c1', command: "/bin/zsh -lc 'npm test'", cwd: '/tmp', status: 'inProgress', commandActions: [{ type: 'unknown', command: 'npm test' }], exitCode: null }
      item('started', cmd); await sleep(50); item('completed', { ...cmd, status: 'completed', exitCode: 0 })
      const rd = { type: 'commandExecution', id: 'c2', command: "/bin/zsh -lc 'cat package.json'", cwd: '/tmp', status: 'inProgress', commandActions: [{ type: 'read', command: 'cat package.json', name: 'package.json', path: '/tmp/x/package.json' }] }
      item('started', rd); item('completed', { ...rd, status: 'completed', exitCode: 0 })
      message('All tests pass. Twelve of them, in three seconds.')
    }
    if (/approve/.test(text)) {
      const cmd = { type: 'commandExecution', id: 'c3', command: "/bin/zsh -lc 'rm -rf build'", status: 'inProgress', commandActions: [{ type: 'unknown', command: 'rm -rf build' }] }
      item('started', cmd)
      const r = await ask('item/commandExecution/requestApproval', { kind: 'command', threadId: thread.id, turnId: active, itemId: 'c3', command: cmd.command, commandActions: cmd.commandActions, reason: null })
      note({ decision: r.result?.decision })
      const ok = r.result?.decision === 'accept'
      item('completed', { ...cmd, status: ok ? 'completed' : 'declined', exitCode: ok ? 0 : null })
      message(ok ? 'Deleted it.' : 'Left it alone.')
    }
    if (/edit/.test(text)) {
      const fc = { type: 'fileChange', id: 'f1', changes: [{ path: '/tmp/x/a.js', kind: { type: 'update', move_path: null }, diff: '' }], status: 'inProgress' }
      item('started', fc)
      const r = await ask('item/fileChange/requestApproval', { threadId: thread.id, turnId: active, itemId: 'f1', reason: null })
      note({ fileDecision: r.result?.decision })
      item('completed', { ...fc, status: r.result?.decision === 'accept' ? 'completed' : 'declined' })
      message('Done with the edit.')
    }
    if (/elsewhere/.test(text)) {
      // a Codex terminal on the same thread answers first: the hub hears serverRequest/resolved and drops its card
      const id = nextId++
      send({ id, method: 'item/commandExecution/requestApproval', params: { kind: 'command', threadId: thread.id, turnId: active, itemId: 'c4', command: 'make deploy', commandActions: [{ type: 'unknown', command: 'make deploy' }] } })
      await sleep(Number(process.env.FAKE_ELSEWHERE_MS ?? 1500))
      notify('serverRequest/resolved', { threadId: thread.id, requestId: id })
      message('Deployed.')
    }
    if (/compact/.test(text)) {
      item('started', { type: 'contextCompaction', id: 'k1' }); await sleep(50); item('completed', { type: 'contextCompaction', id: 'k1' })
      message('Compacted and carried on.')
    }
    if (/reply/.test(text)) {
      const r = await chumsReply('Codex replied by tool.')
      note({ chumsReply: r.result?.content?.[0]?.text })
      item('started', { type: 'mcpToolCall', id: 'x1', server: 'chums', tool: 'chums_reply', status: 'inProgress', arguments: {} })
      item('completed', { type: 'mcpToolCall', id: 'x1', server: 'chums', tool: 'chums_reply', status: 'completed', arguments: {} })
      message('A long final message that stays on the Mac, because the agent already spoke on the watch.')
    }
    if (/steer/.test(text)) {
      await new Promise(r => { steered = r })                       // waits for turn/steer
      message('Steered.')
    }
    done()
  }

  async function handle(m) {
    if (m.id !== undefined && !m.method) { waiting.get(m.id)?.(m); waiting.delete(m.id); return }
    if (m.method !== 'initialized') note({ method: m.method, params: m.params })
    const reply = result => send({ id: m.id, result })
    switch (m.method) {
      case 'initialize': return reply({ userAgent: 'fake-codex/0', codexHome: '/tmp', platformFamily: 'unix', platformOs: 'macos' })
      case 'initialized': return
      case 'thread/start':
        thread = { id: `thr-${Date.now()}`, status: { type: 'idle' } }
        return reply({ thread, model: m.params.model ?? 'fake' })
      case 'thread/resume':
        if (!known.has(m.params.threadId) && m.params.threadId !== thread?.id) return send({ id: m.id, error: { code: -32600, message: `no rollout found for thread id ${m.params.threadId}` } })
        thread = { id: m.params.threadId, status: { type: 'idle' } }
        return reply({ thread })
      case 'turn/start': {
        active = `turn-${++turnN}`
        reply({ turn: { id: active, items: [], status: 'inProgress', error: null } })
        notify('turn/started', { threadId: thread.id, turn: { id: active, items: [], status: 'inProgress' } })
        return turn(m.params.input.map(i => i.text).join('').split('\n').pop())   // his words: the last line
      }
      case 'thread/name/set': return reply({})
      case 'turn/steer':
        if (m.params.expectedTurnId !== active) return send({ id: m.id, error: { code: -32600, message: 'no such turn' } })
        reply({ turnId: active }); steered?.(); steered = null; return
      default: return send({ id: m.id, error: { code: -32601, message: `no ${m.method}` } })
    }
  }
})
fs.rmSync(sock, { force: true })
server.listen(sock)
process.on('SIGTERM', () => { server.close(); process.exit(0) })
