// The command that starts one agent's Claude Code session (tools/agent-host.exp runs it): its folder on the first line,
// then one argument per line. The agent's own folder gets a CLAUDE.md with its role. Exits 3 (and prints why) when
// that thread is already running somewhere: one process per thread, always.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { standingFor } from '../hub/standing.mjs'

const HOME = os.homedir(), ROOT = path.join(import.meta.dirname, '..')
const id = process.argv[2]
const a = JSON.parse(fs.readFileSync(path.join(HOME, '.chums/agents.json'), 'utf8')).find(x => x.id === id)
if (!a) { console.error(`no agent ${id} in ~/.chums/agents.json`); process.exit(2) }
// Codex, Copilot and other Agent Client Protocol agents run inside the hub (hub/runtimes.mjs), not in a terminal
if (a.runtime && a.runtime !== 'claude') { console.error(`${id} runs on ${a.runtime}, inside the hub: no Claude Code session to start`); process.exit(2) }
if (!a.sessionId || !a.cwd) { console.error(`${id} has no ${a.cwd ? 'sessionId' : 'cwd'} in ~/.chums/agents.json: restart the hub, which fills it in`); process.exit(2) }

let running = ''
try { running = execFileSync('/usr/bin/pgrep', ['-f', a.sessionId], { encoding: 'utf8' }).trim() } catch {}
if (running) { console.error(`${id}'s thread is already running (pid ${running.split('\n').join(', ')})`); process.exit(3) }

fs.mkdirSync(a.cwd, { recursive: true })
// what stays fixed: that its soul comes with its owner's orders, and how to use its tools. Who it is lives in its soul
// (~/.chums/souls/<id>.md), which the owner shapes from the watch; the hub sends it with the next order after any change.
const standing = standingFor(a)
if (a.cwd.startsWith(path.join(HOME, '.chums/agents'))) fs.writeFileSync(path.join(a.cwd, 'CLAUDE.md'), `# Agent ${a.id}\n\n${standing}\n`)
// Claude Code keeps a folder's threads in ~/.claude/projects/<the folder, every other character a dash>
const thread = path.join(HOME, '.claude/projects', a.cwd.replace(/[^a-zA-Z0-9]/g, '-'), `${a.sessionId}.jsonl`)
// how it asks before acting (default, acceptEdits, auto…), set from the watch and the iPhone; without one, the
// defaultMode in ~/.claude/settings.json, which applies only to new sessions on its own, passed for a resumed one too
let mode = a.permissionMode
try { mode ??= JSON.parse(fs.readFileSync(path.join(HOME, '.claude/settings.json'), 'utf8')).permissions?.defaultMode } catch {}
const args = [
  '/usr/bin/env', `CHUMS_NAME=${a.id}`, `HOME=${HOME}`,
  // ~/.local/bin: Claude Code's native installer; ~/.npm-global/bin: an npm prefix install (a LaunchAgent has no shell PATH)
  `PATH=${path.dirname(process.execPath)}:${HOME}/.local/bin:${HOME}/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`,
  path.join(ROOT, 'bin/chums-claude'), a.id,
  fs.existsSync(thread) ? '--resume' : '--session-id', a.sessionId,
  '--append-system-prompt', standing,
  ...(a.addDirs ?? []).flatMap(d => ['--add-dir', d]),
  ...(a.model ? ['--model', a.model] : []),
  // a flag, so it holds when the session is resumed too
  ...(typeof mode === 'string' && mode ? ['--permission-mode', mode] : []),
]
console.log([a.cwd, ...args].join('\n'))
