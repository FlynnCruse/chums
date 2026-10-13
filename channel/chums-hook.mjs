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
    }
    await fetch(`http://127.0.0.1:${cfg.port}/hook`, {
      method: 'POST', body: JSON.stringify(body),
      headers: { authorization: `Bearer ${cfg.token}`, 'content-type': 'application/json' },
      signal: AbortSignal.timeout(700),
    })
  } catch {}
  done()
})
