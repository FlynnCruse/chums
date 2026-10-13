// JSON-RPC 2.0 for the hub's agent runtimes: the hub is the client of an agent that runs as a child process.
//   lines(child)     one JSON message per line on the child's stdin/stdout (Agent Client Protocol, `copilot --acp`)
//   wsUnix(path)     text frames of a WebSocket on a Unix socket (`codex app-server --listen unix://…`)
//   peer(transport)  requests with ids and answers, notifications, and the agent's own requests to the hub
// No dependencies: the WebSocket client is the few parts of RFC 6455 a local socket needs.
import net from 'node:net'
import crypto from 'node:crypto'
import readline from 'node:readline'
import { EventEmitter } from 'node:events'

/// A child's stdin/stdout, one message per line. Emits 'message' (parsed object) and 'close'.
export function lines(child) {
  const t = new EventEmitter()
  readline.createInterface({ input: child.stdout }).on('line', l => {
    if (!l.trim()) return
    let m; try { m = JSON.parse(l) } catch { t.emit('junk', l); return }
    t.emit('message', m)
  })
  child.on('exit', () => t.emit('close'))
  child.stdin.on('error', () => {})
  t.send = m => { if (child.stdin.writable) child.stdin.write(JSON.stringify(m) + '\n') }
  t.close = () => { try { child.stdin.end() } catch {} }
  return t
}

/// A WebSocket client on a Unix socket. Resolves once the upgrade is done; emits 'message' and 'close'.
export function wsUnix(socketPath, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const t = new EventEmitter()
    const c = net.createConnection(socketPath)
    let buf = Buffer.alloc(0), open = false, parts = []
    const timer = setTimeout(() => { c.destroy(); reject(new Error(`no answer on ${socketPath}`)) }, timeout)
    const frame = (op, data) => {
      const mask = crypto.randomBytes(4), n = data.length
      const head = n < 126 ? Buffer.from([0x80 | op, 0x80 | n])
        : n < 65536 ? Buffer.from([0x80 | op, 0x80 | 126, n >> 8, n & 255])
        : Buffer.concat([Buffer.from([0x80 | op, 0x80 | 127]), (() => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(n)); return b })()])
      const body = Buffer.alloc(n)
      for (let i = 0; i < n; i++) body[i] = data[i] ^ mask[i & 3]
      return Buffer.concat([head, mask, body])
    }
    c.on('connect', () => c.write(`GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n` +
      `Sec-WebSocket-Key: ${crypto.randomBytes(16).toString('base64')}\r\nSec-WebSocket-Version: 13\r\n\r\n`))
    c.on('data', d => {
      buf = Buffer.concat([buf, d])
      if (!open) {
        const end = buf.indexOf('\r\n\r\n')
        if (end < 0) return
        const status = buf.subarray(0, end).toString().split('\r\n')[0]
        buf = buf.subarray(end + 4)
        clearTimeout(timer)
        if (!/^HTTP\/1\.1 101/.test(status)) { c.destroy(); return reject(new Error(`WebSocket refused: ${status}`)) }
        open = true; resolve(t)
      }
      for (;;) {
        if (buf.length < 2) return
        const fin = buf[0] & 0x80, op = buf[0] & 15, masked = buf[1] & 0x80
        let n = buf[1] & 127, off = 2
        if (n === 126) { if (buf.length < 4) return; n = buf.readUInt16BE(2); off = 4 }
        else if (n === 127) { if (buf.length < 10) return; n = Number(buf.readBigUInt64BE(2)); off = 10 }
        const maskKey = masked ? buf.subarray(off, off + 4) : null
        if (masked) off += 4
        if (buf.length < off + n) return
        let data = Buffer.from(buf.subarray(off, off + n))
        if (maskKey) for (let i = 0; i < n; i++) data[i] ^= maskKey[i & 3]
        buf = buf.subarray(off + n)
        if (op === 8) { c.end(); continue }                                    // close
        if (op === 9) { c.write(frame(10, data)); continue }                   // ping -> pong
        if (op === 10) continue
        parts.push(data)
        if (!fin) continue
        const text = Buffer.concat(parts).toString('utf8'); parts = []
        let m; try { m = JSON.parse(text) } catch { t.emit('junk', text); continue }
        t.emit('message', m)
      }
    })
    c.on('error', e => { clearTimeout(timer); if (!open) reject(e) })
    c.on('close', () => { clearTimeout(timer); if (open) t.emit('close') })
    t.send = m => { if (!c.destroyed) c.write(frame(1, Buffer.from(JSON.stringify(m)))) }
    t.close = () => { try { c.write(frame(8, Buffer.alloc(0))) } catch {} c.end() }
  })
}

/// Requests both ways over a transport. `onRequest(method, params)` answers the agent's requests (throw to send an
/// error); `onNotification(method, params)` takes everything else. `jsonrpc: '2.0'` goes on every message (ACP needs
/// it; Codex's app-server accepts it).
export function peer(transport, { onRequest, onNotification, log = () => {} }) {
  let next = 1
  const waiting = new Map()
  const p = new EventEmitter()
  transport.on('message', async m => {
    if (m.method && m.id !== undefined && m.id !== null) {                    // the agent asks the hub (ids can be 0)
      try { transport.send({ jsonrpc: '2.0', id: m.id, result: (await onRequest(m.method, m.params ?? {}, m.id)) ?? null }) }
      catch (e) { transport.send({ jsonrpc: '2.0', id: m.id, error: { code: e.code ?? -32603, message: e.message ?? String(e) } }) }
    } else if (m.method) {
      try { await onNotification(m.method, m.params ?? {}) } catch (e) { log('notification handler:', m.method, e.message) }
    } else if (waiting.has(m.id)) {
      const w = waiting.get(m.id); waiting.delete(m.id)
      m.error ? w.reject(Object.assign(new Error(m.error.message ?? 'error'), { code: m.error.code, data: m.error.data })) : w.resolve(m.result)
    }
  })
  transport.on('close', () => {
    for (const w of waiting.values()) w.reject(Object.assign(new Error('the agent went away'), { code: 'closed' }))
    waiting.clear(); p.emit('close')
  })
  p.request = (method, params, timeout = 0) => new Promise((resolve, reject) => {
    const id = next++
    const t = timeout ? setTimeout(() => { waiting.delete(id); reject(new Error(`${method} took over ${timeout / 1000} s`)) }, timeout) : null
    waiting.set(id, { resolve: v => { clearTimeout(t); resolve(v) }, reject: e => { clearTimeout(t); reject(e) } })
    transport.send({ jsonrpc: '2.0', id, method, params })
  })
  p.notify = (method, params) => transport.send({ jsonrpc: '2.0', method, ...(params === undefined ? {} : { params }) })
  p.close = () => transport.close()
  return p
}
