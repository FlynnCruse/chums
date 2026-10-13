# Contributing

Thanks for helping. Bug reports, fixes and new characters are welcome.

## License of contributions

Chums is licensed under the [Apache License 2.0](LICENSE). By submitting a contribution you agree that it is licensed
under Apache-2.0, as section 5 of the license says, and that you have the right to submit it.

## Before you start

- For a bug, open an issue with the steps to reproduce, your macOS, watchOS and Xcode versions, the output of
  `bin/chums-doctor`, and the hub log (`~/.chums/hub.log` or the terminal running `bin/chums-hub`). Remove tokens and
  personal paths from logs first. Setup problems: [docs/troubleshooting.md](docs/troubleshooting.md) first.
- For a feature or a new character, open an issue first so we can agree on the shape before you build it.
- Security problems: see [SECURITY.md](SECURITY.md). Don't file them as public issues.

## Set up

```bash
git clone https://github.com/lcoutodemos/chums.git && cd chums
bin/chums-setup        # checks requirements, installs npm packages and the Whisper model
bin/chums-hub          # first start writes ~/.chums/config.json
bin/chums-sim          # the watch app in the watchOS Simulator, no signing
bin/chums-doctor       # read-only check of the whole chain
```

[docs/setup.md](docs/setup.md) covers a real watch, Tailscale Funnel and the background agents.

## Where things are

| Folder | What it is |
| --- | --- |
| `app/` | The apps (SwiftUI). `app/project.yml` is the XcodeGen spec; the `.xcodeproj` is generated |
| `app/ChumsWatch/` | The watchOS app, and the engine the iPhone app shares (watch-only parts are `#if os(watchOS)`) |
| `app/ChumsWatch/Rig/` | The characters: the shared rig and one `<Name>Stage.swift` per self-drawn character |
| `app/ChumsPhone/` | The iPhone app |
| `app/ChumsPhoneWidgets/`, `app/ChumsPhoneShared/` | The iPhone's widgets and the Talk control, and what they share with the app (hub calls, App Intents, widget views) |
| `app/ChumsWidget/` | The watch's widget (complications, Smart Stack) |
| `app/Shared/` | The characters' faces, used by every target |
| `hub/` | The hub on the Mac: `hub.mjs` (sessions, routing, approvals, speech, the watch API, artifacts), `runtimes.mjs` (the agents it runs itself: Codex; experimental: Copilot, ACP), `render.mjs` (Markdown, text and tables as HTML pages), `standing.mjs` (what every agent is told) |
| `channel/` | The Claude Code channel (MCP) and the hook script |
| `bin/` | The commands you run |
| `tools/` | Tests, build helpers, the doctor's checks (`doctor.py`), the background agents' launcher, the Mac app the hub and the agents run through (`mac-app/`), the agents' voices (`kokoro-server.py`) |
| `design/` | The state map (`STATES.md`), Crunch and Nana in JavaScript (`pix/`), Stretch's Blender sources (`noodle/`), Noodle's shape tools (`characters/coil3d/`), the watch mockup (`mockup/`) |
| `docs/` | Setup, troubleshooting, architecture, characters, other agents; `docs/media/` holds the README's pictures and the characters' loops (`tools/readme-loops.sh`) |

## Tests

```bash
npm test                                         # all four below, with no model calls
node tools/test-channel.mjs                      # hub + channel, no Claude Code needed
node tools/test-hub.mjs                          # hub routing, approvals, artifacts, agents, souls
CHUMS_TEST_NO_MODEL=1 node tools/test-hub.mjs    # the same without the soul-editor checks (they call a model)
node tools/test-artifacts.mjs                    # every kind of file shown as a picture, and the iPhone's routes to them
node tools/test-runtimes.mjs                     # the Codex, Copilot and ACP drivers against stand-ins
```

Every command in `bin/` prints what it does and its options with `--help`.

These start a private hub with its own temporary home folder and ports, so they never touch your real hub or
sessions. CI runs them on macOS and builds the watch and iPhone apps for the Simulator (`.github/workflows/ci.yml`).

The iPhone app has UI tests that drive it with real touches in the Simulator, against the hub on your Mac (they send
no orders): `cd app && xcodebuild test -project Chums.xcodeproj -scheme Chums -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
`app/ChumsPhoneUITests/ChumsPhoneUITests.swift` says which settings they read.

End-to-end checks with a real Claude Code session, against your running hub (they read `~/.chums/config.json`):
`python3 tools/e2e-claude.py <dir>` and `python3 tools/e2e-watch.py <dir>`. With the real Codex, in a private hub:
`node tools/e2e-runtimes.mjs codex` (about 14 turns on your Codex account).

## Pull requests

- Keep a pull request to one change. Say what it does and how you checked it.
- Run the Node tests. For watch changes, build with `bin/chums-sim` and include a short screen recording or
  screenshots of what changed (`xcrun simctl io booted recordVideo out.mp4`).
- For a character change, check every state: `design/STATES.md` lists them, and the Simulator's demo
  (`-demo YES`) plays them all.
- Don't commit generated files: `app/Chums.xcodeproj`, the Info.plists, `app/ChumsWatch/HubConfig.swift`,
  `channel/mcp.json`, `channel/hooks.json`. `.gitignore` covers them.
- Don't commit personal data: tokens, absolute paths under your home folder, device IDs, Apple team IDs.

## Writing

Code comments, docs and UI text are plain and literal: say what a thing is or does. No metaphors, no marketing.
