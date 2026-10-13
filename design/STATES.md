# Chums states

What the watch shows is driven by what Claude Code and Codex actually report. This maps every signal to a **state**
(persists until something else is true), a **reaction** (a one-shot over the current state), a **detail** of a state,
or nothing. Verified on 2026-10-02 against the
[Claude Code hooks reference](https://code.claude.com/docs/en/hooks) (33 hook events) and the
[Agent Client Protocol schema](https://github.com/agentclientprotocol/agent-client-protocol/blob/main/schema/v1/schema.json) (v1);
the Codex column on 2026-10-10 against Codex 0.160's own app-server schema (`codex app-server generate-ts`). The hub
turns Codex's (and ACP agents') signals into the Claude Code hook events of the same row (`hub/runtimes.mjs`), so
everything below them is shared.

Character names in the tables below predate the October 2026 rename: Eyes is now Peeps, the Blender Noodle is
Stretch, and Pix is Crunch (apple) and Nana (banana).

The hub computes everything below. The watch app (`app/ChumsWatch/Controller.swift`) shows less of it today:

- Thinking shows while what you said is sent and transcribed, and while an agent compacts. From a prompt to the first
  tool call the hub reports `working`, and the watch shows Working.
- Waiting (rate limited) shows as Blocked, and Compacting as Thinking.
- Sleep shows when the agent has no session on the Mac or the watch can't reach the hub. Nothing puts an agent to
  sleep after 10 minutes without activity; `SessionEnd` makes it idle.
- Of the reactions, Tool call and Poke play. Tool failed, Interrupted and Wake don't: the watch doesn't read the hub's
  `reactions`.
- Done follows a turn in which the agent used tools. Its *approved* variant follows any approval you allowed, with no
  5 s window. Approval has no *plan* variant on the watch.

## States

Priority decides which state wins when several sessions disagree (highest first). Only Needs you, Approval and
Blocked interrupt you with a haptic you can't miss.

| State | Priority | Claude Code hooks | Codex app-server | Agent Client Protocol | Watch-side |
| --- | --- | --- | --- | --- | --- |
| Approval | 10 | `PermissionRequest`; `Notification` `permission_prompt` | `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/permissions/requestApproval` | `session/request_permission` (options `allow_once`, `allow_always`, `reject_once`, `reject_always`) | variant *plan*: `ExitPlanMode` asks you to approve a plan |
| Needs you | 9 | `Notification` `idle_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input`; `Elicitation` | `thread/status/changed` `waitingOnUserInput`; `item/tool/requestUserInput` | — | variant *question*: it asked something |
| Blocked | 8 | `StopFailure` `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `cloud_credential_error`, `unknown` | `turn/completed` `failed` (any other error) | stop reason `refusal`, `max_tokens`, `max_turn_requests` | |
| Listening | 7 | — | — | — | you hold the screen |
| Waiting **(new)** | 6 | `StopFailure` `rate_limit`, `overloaded`; ends on `Notification` `quota_auto_resume_fired` | `turn/completed` `failed` with `usageLimitExceeded`, `rateLimitExceeded`, `serverOverloaded`, `sessionBudgetExceeded` | — | resumes by itself; shows when |
| Speaking | 6 | `MessageDisplay`; the `chums_reply` channel tool | the `chums_reply` MCP tool; else the turn's `final_answer`, said by the hub | `agent_message_chunk` | |
| Done | 6 | `Stop`; `Notification` `agent_completed` | `turn/completed` `completed` | stop reason `end_turn` | variant *approved*: you allowed it within 5 s |
| Thinking | 5 | from `UserPromptSubmit` until the first tool call or message | from `turn/started` until the first item | `agent_thought_chunk` | also while your words are transcribed |
| Compacting **(new)** | 5 | `PreCompact` (`manual`, `auto`) until `PostCompact` | `item/started` … `item/completed` `contextCompaction` | — | |
| Working | 4 | `PreToolUse` … `PostToolUse` | `item/started` … `item/completed` (`commandExecution`, `fileChange`, `mcpToolCall`, `webSearch`) | `tool_call` / `tool_call_update` (`pending`, `in_progress`) | detail: the kind of tool, below |
| Subagents | 4 | `SubagentStart` / `SubagentStop` (count of live `agent_id`s); `TeammateIdle` | `subAgentActivity`; `collabAgentToolCall` `spawnAgent` / `closeAgent` | — | |
| Dizzy | 3 | — | — | — | you shake your keys |
| Idle | 2 | `SessionStart` `startup`, `resume`, `clear`, `fork` | `thread/start`, `thread/resume` (the hub starts its app-server) | — | |
| Sleep | 1 | `SessionEnd` (`clear`, `resume`, `logout`, `prompt_input_exit`, `other`); 10 min without activity | its app-server exits (offline) | — | variant *offline*: the Mac or the hub is unreachable |

### Working, by kind of tool

| Kind (ACP `ToolKind`) | Claude Code tools | Stretch | Peeps | Crunch, Nana |
| --- | --- | --- | --- | --- |
| `read` | Read, NotebookRead | reads lines, eyes sweeping | reads the page | +1 READ |
| `search` / `fetch` | Grep, Glob, WebSearch, WebFetch | looks around | reads the page | +1 GREP |
| `edit` / `delete` / `move` | Edit, Write, MultiEdit, NotebookEdit | pecks along like typing | a line is rewritten | +1 EDIT |
| `execute` | Bash | leans in and watches the output scroll | a command and its output | +1 BASH |
| `think` / `other` / `switch_mode` | Task, Skill, everything else | reads | reads | +1 tool name |

## Reactions

One-shot, played over whatever state is current.

| Reaction | Signal | What it looks like |
| --- | --- | --- |
| Tool call | `PreToolUse`; Codex `item/started`; ACP `tool_call` | Noodle: a card drops on its head and it bonks it away. Eyes: a new line. Pix: +1 TOOL floats up |
| Tool failed | `PostToolUseFailure`; `PermissionDenied`; Codex `item/completed` `failed` (a command that couldn't run; one that exits non-zero is only marked failed); ACP `tool_call_update` `failed` | a flinch, then a guilty look at you |
| Interrupted | you stopped it: a tool result with `interrupted`, a new prompt while it works; Codex `turn/completed` `interrupted`; ACP stop reason `cancelled` | it freezes mid-move, then looks at you |
| Wake | `SessionStart` | pops up |
| Poke, pet | your finger | |

## Not acted (planned for the status row, not built yet)

| Signal | Where it will show |
| --- | --- |
| Permission mode (`default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`; ACP `current_mode_update`) | the status row, as a badge |
| Plan and tasks (`TaskCreated`, `TaskCompleted`; ACP `plan` entries `pending`, `in_progress`, `completed`) | the status row, as 3 / 5 |
| Context use (ACP `usage_update`) | Compacting is the state that matters; usage itself isn't shown |

## Ignored on purpose

`Setup`, `UserPromptExpansion`, `PostToolBatch`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `DirectoryAdded`,
`FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreModelSwitch`, `PostModelSwitch`, `ElicitationResult`,
`Notification` `auth_success`, `elicitation_complete`, `elicitation_response`, `quota_auto_resume_stale`,
`quota_auto_resume_disabled`; ACP `user_message_chunk`, `available_commands_update`, `config_option_update`,
`session_info_update`. None of them changes what you need to know from your keys.

## Where it's implemented

- `bin/chums-claude` registers the hooks; `channel/chums-hook.mjs` forwards each event; `hub/hub.mjs` (`onHook`) turns
  them into session statuses (`idle`, `working`, `waiting`, `blocked`, `limited`, `compacting`) and reactions.
- `hub/runtimes.mjs` does the same for agents the hub runs (Codex; experimental: Copilot, ACP agents): it puts their
  events into hook events for `onHook`. `docs/other-agents.md` has the details.
- `app/ChumsWatch/Rig/` acts every state out for every character; `design/noodle/animate.py` renders Stretch's.
- `app/ChumsWatch/Controller.swift` maps hub statuses onto the watch rig. Waiting and Compacting show as Blocked and
  Thinking there; the rig has no Waiting or Compacting state yet (`Rig/Pix.swift` already draws both for Crunch and
  Nana).
