# Troubleshooting

Start with `bin/chums-doctor`. It checks the whole chain read-only and prints the fix for each failure; fix the first
`FAIL` first, since later checks often fail because of it. The problems below are the ones seen while building and
using Chums, each as symptom, cause and fix. Setup itself: [setup.md](setup.md).

Logs:

| Log | What's in it |
| --- | --- |
| The terminal running `bin/chums-hub`, or `~/.chums/hub.log` under launchd | The hub: sessions, each clip and its transcript, approvals, errors |
| `~/.chums/watch-events.log` | What the watch reports: launches with their build stamp, keyring mode, screen, network |
| `~/.chums/agents/<id>.host.log` | One agent: how it started, its runtime's errors |
| `~/.chums/tailscale/tailscaled.log` | Chums' `tailscaled` |
| The path `bin/chums-install` prints | The full build or install log after a failure |

Contents:

- Installing on the watch: [the watch isn't in Xcode](#the-watch-isnt-in-xcode) ·
  [no Developer Mode switch](#the-developer-mode-switch-is-missing-on-the-watch) ·
  [developer disk image](#the-developer-disk-image-could-not-be-mounted) ·
  [device locked](#cant-launch-when-device-is-locked-passcode-locked-or-blocked) ·
  [connection could not be established](#a-connection-to-this-device-could-not-be-established) ·
  [team has no devices](#your-team-has-no-devices) ·
  [no team can sign](#no-account-for-team-or-no-developer-team-can-sign) ·
  [bundle ID or App ID limit](#the-bundle-id-is-taken-or-the-app-id-limit-is-reached) ·
  [a coordinated install exists](#a-coordinated-install-exists-for-this-identity) ·
  [two copies of Chums](#two-copies-of-chums-on-the-watch) ·
  [stopped opening after 7 days](#chums-stopped-opening-after-7-days) ·
  [xcrun can't find devicectl](#xcrun-cant-find-devicectl) ·
  [Xcode license](#xcodes-license-or-first-launch)
- The watch and the Mac: [HUB OFFLINE](#the-watch-shows-hub-offline-and-cant-reach-your-mac) ·
  [Hub refused the token](#the-watch-shows-hub-refused-the-token) ·
  [Funnel's name doesn't resolve](#funnels-name-doesnt-resolve-yet) ·
  [bin/chums-tunnel waits at a link](#binchums-tunnel-waits-at-a-link) ·
  [Not running on your Mac](#an-agent-shows-not-running-on-your-mac)
- Talking: [slow first message](#the-first-thing-you-say-after-the-hub-starts-is-slow) ·
  [nothing recorded](#holding-the-screen-records-nothing) · [screenshots fail](#screenshots-fail) ·
  [the watch's voice](#replies-are-read-in-the-watchs-voice-not-the-agents) ·
  [keyring mode](#keyring-mode-doesnt-stay-on)
- The Mac: [a permission dialog stops an agent](#a-permission-dialog-on-the-mac-stops-an-agent) ·
  [switched on but still refused](#chums-is-switched-on-but-still-refused) ·
  [monthly screen recording question](#macos-asks-once-a-month-whether-chums-may-keep-recording-the-screen) ·
  [address already in use](#the-hub-wont-start-address-already-in-use) ·
  [a settings file isn't valid JSON](#the-hub-stops-at-start-a-settings-file-isnt-valid-json) ·
  [whisperkit-cli didn't start](#whisperkit-cli-didnt-start-in-the-hub-log) ·
  [a Codex agent doesn't start](#a-codex-agent-doesnt-start) ·
  [a background Claude Code agent doesn't start](#a-background-claude-code-agent-doesnt-start) ·
  [a ding keeps playing](#the-mac-keeps-playing-a-ding)

## Installing on the watch

### The watch isn't in Xcode

**Symptom:** `bin/chums-install` says "Xcode doesn't know any Apple Watch yet", `bin/chums-doctor` fails "Xcode does not
know any Apple Watch yet", or Window › Devices and Simulators lists the iPhone but not the watch.

**Cause:** Xcode finds an Apple Watch only through its paired iPhone, and the first time only through an iPhone
connected by USB cable (Xcode's device service lists a watch through the iPhone's USB connection). An iPhone that Xcode
reaches over Wi-Fi alone never brings its watch in. A locked watch, or one that hasn't trusted the Mac, doesn't show
either.

**Fix:**

1. Connect the iPhone to the Mac with a USB cable, unlock it, and tap **Trust** if it asks.
2. Unlock the watch, keep it near the iPhone, and tap **Trust** on the watch if it asks.
3. Keep Xcode › Window › Devices and Simulators open and wait. The watch appears under the iPhone or on its own;
   "Preparing Apple Watch for development" can take 10 minutes or more the first time.
4. The Mac, the iPhone and the watch must be on the same Wi-Fi network for installs after that.

### The Developer Mode switch is missing on the watch

**Symptom:** Settings › Privacy & Security on the watch has no Developer Mode.

**Cause:** watchOS shows the switch only after Xcode has asked it to, which Xcode does once it lists the watch. When the
watch never appeared in Xcode (see above), the switch never appears.

**Fix:**

1. Get the watch listed in Devices and Simulators: [the watch isn't in Xcode](#the-watch-isnt-in-xcode). Then look again.
2. If it is listed and the switch is still missing, ask the watch to show it with `tools/watch_devmode.py reveal`
   (iPhone on USB, both unlocked; setup: [setup.md, step 8](setup.md#8-turn-on-developer-mode)).
3. Turn the switch on, then restart the watch **from the prompt it shows**. A restart done another way can clear the
   revealed switch, and you start over. After the restart, unlock the watch and confirm **Turn On**.

### "The developer disk image could not be mounted"

**Symptom:** an install attempt fails with "The developer disk image could not be mounted on this device" (in the log:
`kAMDMobileImageMounterDeviceLocked`), or Xcode shows it in Devices and Simulators.

**Cause:** Xcode mounts a developer disk image on the watch before it installs, and the watch refuses while it is
locked. It also fails while Xcode is still preparing the watch, and when the watch runs a watchOS version this Xcode
doesn't support (a newer watchOS, or a beta, needs the matching Xcode).

**Fix:**

1. Unlock the watch and keep it awake (tap the screen), then run `bin/chums-install` again.
2. Open Window › Devices and Simulators and wait until Xcode has finished preparing the watch.
3. Compare the watch's watchOS version (`bin/chums-doctor` shows it) with your Xcode; update Xcode if the watch is newer.
4. Still failing: restart the watch, then the iPhone, and try again.

### "Can't launch when device is locked, passcode locked or blocked"

**Symptom:** `bin/chums-install` installs the app, then says "Chums is installed, but it didn't open" with this error.

**Cause:** the install worked; watchOS doesn't open an app on a locked watch.

**Fix:** unlock the watch and open Chums from its app list. Nothing needs to be installed again. With keyring mode,
turning off Wrist Detection (Settings › Passcode) keeps the watch unlocked off a wrist.

### "A connection to this device could not be established"

**Symptom:** install attempts fail with "A connection to this device could not be established", "Failed to allocate
RSD device", or another tunnel or timeout error. `bin/chums-install` prints `install attempt N failed` and retries.

**Cause:** Xcode reaches the watch over a wireless tunnel on the local network (CoreDevice's remote service discovery,
RSD). The tunnel drops when the watch sleeps or locks, moves away from the iPhone or the Wi-Fi, or changes network. The
first attempt or two often fail, which is why `bin/chums-install` tries 5 times, 6 seconds apart.

**Fix:**

1. Keep the watch unlocked and awake while it installs: tap the screen every few seconds, or put it on its charger.
2. Keep the watch near the iPhone, and the Mac, iPhone and watch on the same Wi-Fi network, with Bluetooth on.
3. Run `bin/chums-install` again.
4. If it keeps failing: open Window › Devices and Simulators and wait until the watch shows as connected; turn the
   watch's Wi-Fi off and on; restart the watch; connect the iPhone by USB.

### Your team has no devices

**Symptom:** the build stops with "Your team has no devices from which to generate a provisioning profile".
`bin/chums-install` then prints how to register the devices.

**Cause:** automatic signing makes a provisioning profile only for devices registered with the team. Xcode registers a
device when you run an app on it from Xcode. `bin/chums-install` builds without a run destination, so on a team with no
registered devices (often a new free Personal Team) there is nothing to make a profile for.

**Fix:** register the devices once from Xcode, then go back to the script:

1. Open `app/Chums.xcodeproj` (the first `bin/chums-install` run generated it, with your team and bundle ID).
2. Choose the **Chums** scheme and your iPhone as the destination, and press Run (⌘R).
3. Choose the **ChumsWatch** scheme and your watch as the destination, and press Run.
4. If Xcode asks to download the watchOS platform first, accept (several GB).
5. Run `bin/chums-install` again.

A free Personal Team can register 3 devices.

### "No Account for Team", or no developer team can sign

**Symptom:** `bin/chums-install` says "Xcode isn't signed in to the Apple ID for team …" or "No developer team can sign".

**Cause:** Xcode has no signed-in Apple ID with that team. Xcode also lists no team for an account while Apple converts
its membership (for example from individual to organization), even though the Apple ID is signed in.

**Fix:** Xcode › Settings › Apple Accounts › + › Apple ID, and sign in. Any Apple ID works: it has a free Personal Team.
During a membership conversion, wait for Apple to finish, or sign in a second Apple ID and use its Personal Team. To
force a team: `"team": "<team ID>"` in `~/.chums/config.json`, or `CHUMS_TEAM=<team ID> bin/chums-install`.

### The bundle ID is taken, or the App ID limit is reached

**Symptom:** the build fails with "cannot be registered to your development team because it is not available", or with
"the '10' App ID limit in '7' days has been exceeded".

**Cause:** a bundle ID belongs to the team that registered it first. A free Personal Team can register 10 App IDs in 7
days, and each Chums bundle ID uses 4 (the iPhone app, its widgets, the watch app and the watch's widget), so trying a few bundle IDs or teams
uses them up.

**Fix:** for a taken ID, set one of your own, such as `"bundleId": "com.<you>.chums"`, in `~/.chums/config.json`. For
the limit, wait until the oldest App IDs expire (7 days after they were made), then keep one bundle ID from then on.

### "A coordinated install exists for this identity"

**Symptom:** installing on the watch fails with `IXErrorDomain error 48`: "A coordinated install exists for this
identity, but it's scoped to a different process."

**Cause:** the iPhone app carries the watch app. When the iPhone app was installed before the watch had the same
copy, the iPhone started installing it on the watch itself, and the direct install waits for that one.

**Fix:** unlock the watch, keep it near the iPhone, and wait until the iPhone's install finishes (the Watch app on the
iPhone › My Watch shows Chums installing). Then run `bin/chums-install` again: it installs the watch first, so this
doesn't happen again.

### Two copies of Chums on the watch

**Symptom:** the watch has two Chums apps. One works; the other shows "HUB OFFLINE", "Hub refused the token", or doesn't
open.

**Cause:** the bundle ID changed between two installs, and each bundle ID is a separate app. The default bundle ID is
`dev.chums.<team ID>`, so it changes when you sign with another team (for example from a free Personal Team to a paid
one, or with another Apple ID), or when an earlier install used `CHUMS_BUNDLE` and a later one didn't. The old copy keeps
the token and address it was built with, and on a free team it stops opening after 7 days.

**Fix:**

1. See which apps are on the watch: `xcrun devicectl device info apps --device "<watch name>"`.
2. Pin the one to keep in `~/.chums/config.json`: `"bundleId": "<that ID without .watchkitapp>"`.
3. Run `bin/chums-install`.
4. Delete the other copy: on the watch, touch and hold the app list, tap Edit Apps, then the delete button. Or:
   `xcrun devicectl device uninstall app --device "<watch name>" <old bundle ID>.watchkitapp`.
5. If the app you kept doesn't show after that, step 1 says whether it is installed; run `bin/chums-install` again.

### Chums stopped opening after 7 days

**Symptom:** Chums worked, and a week later it doesn't open.

**Cause:** an app signed with a free Personal Team has a provisioning profile that expires 7 days after the install.
`bin/chums-install` prints the date.

**Fix:** run `bin/chums-install` again (same Apple ID, same bundle ID): the app is replaced and works for another 7
days. A paid Apple Developer Program membership signs for a year ([setup.md](setup.md#apple-developer-account)).

### xcrun can't find devicectl

**Symptom:** running `xcrun devicectl …` yourself prints `unable to find utility "devicectl"`.

**Cause:** `xcode-select` points at the Command Line Tools, which don't include `devicectl`. Chums' scripts set
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` themselves, so they aren't affected.

**Fix:** put `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in front of the command, or switch for good with
`sudo xcode-select -s /Applications/Xcode.app`.

### Xcode's license or first launch

**Symptom:** builds fail with "You have not agreed to the Xcode license agreements", or `bin/chums-doctor` says Xcode
hasn't finished its first launch.

**Cause:** Xcode needs its license accepted and its components installed once.

**Fix:** open Xcode once and follow its prompts, or run `sudo xcodebuild -license accept` and
`sudo xcodebuild -runFirstLaunch`.

## The watch and the Mac

### The watch shows HUB OFFLINE and "Can't reach your Mac"

**Symptom:** the character sleeps, the top says HUB OFFLINE, and the line under it says "Can't reach your Mac". Talking
gives "Can't reach your Mac".

**Cause:** the watch can't get an answer from the hub's public URL. One of these is down:

- the hub (not started, stopped, or the Mac is asleep: on battery a sleeping Mac is offline);
- Chums' `tailscaled` or Funnel (not running after a restart of the Mac, signed out, or Funnel turned off);
- public DNS for the Funnel name (a new name: [see below](#funnels-name-doesnt-resolve-yet));
- the watch's own network (no iPhone nearby, no Wi-Fi or cellular).

**Fix:** run `bin/chums-doctor`; sections 4 and 5 say which link fails. Then:

- hub: `bin/chums-hub`, or `bin/chums-setup --launchd` to run it at login (it keeps the Mac awake while on power);
- tunnel: `bin/chums-tunnel` (it starts `tailscaled`, and turns Funnel on again);
- the watch retries on its own; a touch or raising the wrist retries at once.

### The watch shows "Hub refused the token"

**Symptom:** HUB OFFLINE with "Hub refused the token".

**Cause:** the watch reaches a hub, and that hub doesn't accept the token built into the app. The hub's `watchToken`
changed after the app was built: `~/.chums/config.json` was deleted or rotated, the app was built on another Mac or
user account, or an old copy of the app is open ([two copies](#two-copies-of-chums-on-the-watch)).

**Fix:** run `bin/chums-install` again: it builds the hub's current token into the app. `bin/chums-doctor` says whether
the last build matches ("the watch app (built …) has the hub's current token and address").

### Funnel's name doesn't resolve yet

**Symptom:** right after `bin/chums-tunnel`, `bin/chums-doctor` fails "does not resolve in public DNS yet",
`curl https://chums-hub.<tailnet>.ts.net/v1/ping` says "Could not resolve host", and the watch can't reach the Mac.

**Cause:** Tailscale publishes the DNS record for a new Funnel name some time after Funnel is turned on: up to 10
minutes, by Tailscale's documentation; it has taken about 25. A resolver that asked before the name existed (the Mac,
the iPhone, a router or a carrier) can keep the "no such name" answer for a while after that.

**Fix:** wait, and check with a public resolver: `dig +short chums-hub.<tailnet>.ts.net @1.1.1.1`. Once that prints
addresses and the Mac still fails, flush its cache: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.
On the iPhone, turn airplane mode on and off.

### bin/chums-tunnel waits at a link

**Symptom:** `bin/chums-tunnel` prints a `login.tailscale.com` link and doesn't finish.

**Cause:** the first link (`…/a/…`) signs Chums' `tailscaled` in to your tailnet. The second (`…/f/funnel?…`) appears
when the tailnet doesn't allow Funnel yet: Funnel needs HTTPS certificates on and the `funnel` node attribute in the
tailnet's access policy.

**Fix:** open the link, sign in or approve, and the script continues. If a policy change isn't allowed from that link
(an organization's tailnet), an admin turns on HTTPS Certificates (DNS page) and adds the `funnel` node attribute
(Access controls) in the admin console.

### An agent shows "Not running on your Mac"

**Symptom:** in the watch's agents list, an agent is gray and says "Not running on your Mac".

**Cause:** the hub is reachable, but no session for that agent is connected to it.

**Fix:**

- A Claude Code agent: `bin/chums-agents status`, then `bin/chums-agents start <id>` (or `install`), or start it in a
  terminal with `bin/chums-claude <id>` in its folder. Its log: `~/.chums/agents/<id>.host.log`.
- A Codex agent: the hub runs it, so restart the hub. If it still doesn't start:
  [a Codex agent doesn't start](#a-codex-agent-doesnt-start).

## Talking

### The first thing you say after the hub starts is slow

**Symptom:** after starting or restarting the hub, the first clip takes 15–25 seconds to transcribe; later ones take
a fraction of a second.

**Cause:** `whisperkit-cli serve` loads the speech model on its first transcription. The hub now sends it a second of
silence as it starts, so the model is loaded before you speak, and logs `whisper warm in … s` when it's done.

**Fix:** nothing, unless the hub logs `whisper did not warm up in 90 s` or `whisper model missing at …`. Then run
`bin/chums-setup` (it downloads the model) and restart the hub. A clip sent in the first seconds after a restart still
waits for the warm-up.

### Holding the screen records nothing

**Symptom:** you hold the screen and talk, and nothing is sent, or the transcript is empty.

**Cause:** Chums has no microphone permission on the watch (it was refused when Chums first opened; the watch then
says "Allow the microphone for Chums in Settings."), or Whisper heard no speech: the hub drops what Whisper marks as
non-speech, such as `[BLANK_AUDIO]`. A hold shorter than about a third of a second isn't sent.

**Fix:** on the watch, Settings › Privacy & Security › Microphone › Chums on. Hold, speak, then let go; the hub log
shows each clip with its transcript.

### Screenshots fail

**Symptom:** you ask for a screenshot and the agent says macOS refused it, or the picture shows only the desktop
background.

**Cause:** `chums_show` takes screenshots with `screencapture` from inside the agent's process, and macOS allows that only
for apps with Screen Recording permission. Which app needs it depends on how the agent runs:

| Agent | The app that needs Screen Recording |
| --- | --- |
| Claude Code in a terminal (`bin/chums-claude`) | That terminal app: Terminal, iTerm, Visual Studio Code… |
| Claude Code in the background (`bin/chums-agents`) | Chums (`~/Applications/Chums.app`) |
| Codex (run by the hub) | Chums, when the hub runs as a LaunchAgent (`bin/chums-setup --launchd`); the terminal app, when it runs in a terminal (`bin/chums-hub`) |

**Fix:** for Chums, open Chums from `~/Applications` and click Allow All ([Permissions on the Mac](setup.md#permissions-on-the-mac)). For a
terminal app: System Settings › Privacy & Security › Screen & System Audio Recording › +, and add it. Then restart the
agent (or the hub): macOS applies the permission to processes started after it.

### A permission dialog on the Mac stops an agent

**Symptom:** something you asked for from the watch doesn't happen, and the Mac shows a dialog such as "expect would
like to access files in your Documents folder" or "node wants access to control Finder". It comes back after Claude
Code or Node.js updates.

**Cause:** macOS asks on behalf of the program launchd started. Before Chums.app, that was `/usr/bin/expect` (background
Claude Code agents) and `/usr/bin/caffeinate` with `node` (the hub and its Codex agents), and permissions given to a
versioned Claude Code binary are lost when it updates.

**Fix:** run `bin/chums-setup --launchd` and `bin/chums-agents install` (both restart what they install, so the watch's
conversation is cut for a moment). Then, at the Mac, open Chums from `~/Applications` and click Allow All. From then on
every dialog says "Chums" and is asked once. `bin/chums-doctor` shows what's still missing.

### Chums is switched on but still refused

**Symptom:** Chums's window shows Allow for Accessibility or Screen Recording, but in System Settings Chums is already
in the list and switched on.

**Cause:** Chums.app was signed again since (ad hoc after a rebuild, or with your Apple Development certificate once
Xcode made one), and macOS keeps the switch of the old signature. `bin/chums-setup --launchd` and
`bin/chums-agents install` say so when it happens.

**Fix:** in that list, switch Chums off and on again (or select it, click −, then open Chums and click Allow All).

### macOS asks once a month whether Chums may keep recording the screen

**Symptom:** "Chums is requesting to bypass the system private window picker and directly access your screen and
audio", or "Chums has been accessing your screen… Continue to Allow", on macOS 15 and later.

**Cause:** macOS asks this of any app that takes screenshots without its window picker, which `screencapture`
(screenshots for the watch) does: the first time one is taken (Allow All takes one, so it comes during setup), then
about once a month. It doesn't stop the screenshot; the dialog waits on the Mac.

**Fix:** click Allow (or Continue to Allow) when you're at the Mac. There is no setting to turn it off.

### Replies are read in the watch's voice, not the agent's

**Symptom:** the watch reads replies in its robotic voice, and every agent sounds the same.

**Cause:** the agents' voices (Kokoro) aren't installed or aren't running: the hub then sends no audio and the watch
uses its own voice. Kokoro needs Apple Silicon, and `uv` to install.

**Fix:** run `bin/chums-setup` (it installs Kokoro; `brew install uv` first if it asks), then restart the hub.
`bin/chums-doctor` says whether Kokoro answers; the hub log says why it stopped (`kokoro exited`).

### Keyring mode doesn't stay on

**Symptom:** with "Keyring: stay on" in the watch app's settings, Chums still goes back to the watch face when the screen
dims, and the settings show "Keyring mode failed: …". `~/.chums/watch-events.log` has `keyring error: …` or
`keyring health after asking: denied`.

**Cause:** keyring mode runs a workout session, which needs Health › Workouts permission. watchOS asks once per install;
if it was refused, or the first request came from a build without the HealthKit entitlement, it keeps the answer.
watchOS can also report "denied" for an app that was allowed: the session starting is the real test (`keyring running`
in the log).

**Fix:** delete Chums from the watch, restart the watch, run `bin/chums-install`, and allow Workouts when Chums asks.

## The Mac

### The hub won't start: address already in use

**Symptom:** `bin/chums-hub` stops with `chums: 127.0.0.1:7717 is in use, most likely by a hub that is already
running` (or `:7718`).

**Cause:** another hub is already running: usually the LaunchAgent from `bin/chums-setup --launchd`, plus one started by
hand.

**Fix:** `lsof -nP -iTCP:7717 -sTCP:LISTEN` shows which process holds the port. Keep one hub: stop the extra one, or use
`launchctl kickstart -k gui/$UID/dev.chums.hub` to restart the LaunchAgent's instead of starting another.

### The hub stops at start: a settings file isn't valid JSON

**Symptom:** the hub stops with `chums: /Users/you/.chums/config.json is not a valid JSON object` or `… agents.json is not a
valid JSON list of agents`.

**Cause:** the file was edited by hand and has a typo. The hub stops instead of writing over it, so nothing is lost.

**Fix:** fix the JSON (`bin/chums-doctor` says where it fails) and start the hub again. Moving the file away also works,
at a cost: a new `config.json` has new tokens, so run `bin/chums-install` again; a new `agents.json` starts every
agent's conversation over.

### "whisperkit-cli didn't start" in the hub log

**Cause:** the Whisper model is there but `whisperkit-cli` isn't on the hub's PATH: not installed, or the LaunchAgent
was written before it was.

**Fix:** `brew install whisperkit-cli`, then `bin/chums-setup --launchd` (it writes the LaunchAgent's PATH again), or
start the hub from a shell that has it.

### A Codex agent doesn't start

**Symptom:** a Codex agent stays "Not running on your Mac"; `~/.chums/agents/<id>.host.log` says "not started".

**Cause and fix**, by what the log says:

- `codex app-server didn't open …` or a spawn error: the hub didn't find `codex`. It looks on its own PATH plus
  `~/.npm-global/bin`, `/opt/homebrew/bin` and `/usr/local/bin`. Install Codex in one of those, or set
  `"command": ["/path/to/codex"]` on the agent in `agents.json`.
- A sign-in error: run `codex login`, then restart the hub.
- A model error: the default model isn't on your plan. Set `"model"` on the agent (`gpt-6-astra` works on Plus).
- After a Codex update, run `node tools/e2e-runtimes.mjs codex`: OpenAI labels the app-server experimental, and its
  methods can change between releases.

### A background Claude Code agent doesn't start

**Symptom:** `bin/chums-agents status` shows an agent `not running`, or its `host.log` repeats `not started: …`.

**Cause and fix**, by what the log says:

- `…'s thread is already running (pid …)`: the same agent is open in another terminal (`bin/chums-agents open`, or a
  `claude --resume` of its thread). One process per thread: quit that one.
- `ended while starting`, or the session exits at once: Claude Code isn't found or isn't signed in. A LaunchAgent has no
  shell PATH; agents look in the node folder, `~/.local/bin`, `~/.npm-global/bin`, `/opt/homebrew/bin` and
  `/usr/local/bin`. Run `claude` once in a terminal to sign in.
- `running (no development-channel screen seen in its first minute)`: the session started without the screen that
  confirms the development channel. If orders from the watch don't reach it, check that channels are allowed for the
  account: on Team and Enterprise plans an Owner enables them (Organization settings › Claude Code › Channels).
  `bin/chums-agents open <id>` shows the session's screen.

### The Mac keeps playing a ding

**Symptom:** the Mac plays a short sound again and again, with no window explaining it.

**Cause:** a watchOS Simulator is still running Chums without a Simulator window, and plays the watch's taps as sounds.

**Fix:** `xcrun simctl shutdown all`.
