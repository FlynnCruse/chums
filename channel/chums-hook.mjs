#!/usr/bin/env node
// Claude Code hook -> Chums hub. Runs on the hook events chums-claude registers (tool calls and failures,
// permission requests, notifications, prompts, stops and stop failures, compaction, subagents, session start/end),
// so the watch shows what the session is doing as it happens.
// It never blocks Claude Code: it prints nothing, always exits 0, and gives up after 800 ms.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const done = () => process.exit(0)
setTimeout(done, 800).unref()

// The last assistant text in a transcript: read from its end only, since a long session's file runs to megabytes.
function lastAssistantText(file) {
  try {
    const fd = fs.openSync(file, 'r'), size = fs.fstatSync(fd).size, len = Math.min(size, 256 * 1024)
    const buf = Buffer.alloc(len)
    fs.readSync(fd, buf, 0, len, size - len)
    fs.closeSync(fd)
    for (const line of buf.toString('utf8').split('\n').reverse()) {
      if (!line.includes('"assistant"')) continue
      let d; try { d = JSON.parse(line) } catch { continue }
      if (d.type !== 'assistant') continue
      const text = (d.message?.content ?? []).filter(c => c.type === 'text').map(c => c.text).join('\n').trim()
      if (text) return text
    }
  } catch {}
  return null
}

let input = ''
process.stdin.on('data', c => { input += c })
process.stdin.on('end', async () => {
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.chums/config.json'), 'utf8'))
    const ev = JSON.parse(input || '{}')
    const cwd = ev.cwd || process.cwd()
    const body = {
      name: process.env.CHUMS_NAME || path.basename(cwd),
      cwd,
      event: ev.hook_event_name,
      tool: ev.tool_name ?? null,
      input: ev.tool_input ?? null,
      // enough of the result to tell a passing test run from a failing one
      result: ev.tool_response ? JSON.stringify(ev.tool_response).slice(-1500) : null,
      // what the other events carry: why it stopped, what it needs, which subagent, which compaction
      notification: ev.notification_type ?? null, message: ev.message ?? null,
      error: ev.error_type ?? ev.error ?? null, trigger: ev.trigger ?? null,
      agent: ev.agent_id ?? null, agentType: ev.agent_type ?? null,
      source: ev.source ?? null, reason: ev.reason ?? null, mode: ev.permission_mode ?? null,
      // the turn's final answer, spoken by the hub when a turn from the watch ended without chums_reply
      lastMessage: ev.hook_event_name === 'Stop' ? (ev.last_assistant_message ?? lastAssistantText(ev.transcript_path)) : null,
    }
    await fetch(`http://127.0.0.1:${cfg.port}/hook`, {
      method: 'POST', body: JSON.stringify(body),
      headers: { authorization: `Bearer ${cfg.token}`, 'content-type': 'application/json' },
      signal: AbortSignal.timeout(700),
    })
  } catch {}
  done()
})
