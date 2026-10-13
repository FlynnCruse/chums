# Shared by the bin/ scripts: where things are, and the per-machine settings that used to be hardcoded.
# Each setting comes from an environment variable, else from ~/.chums/config.json, else a default:
#   CHUMS_BUNDLE         config "bundleId"        the app's bundle ID (the watch app is <it>.watchkitapp)
#   CHUMS_TEAM           config "team"            the Apple developer team to sign with (else tools/pick-team.py picks)
#   CHUMS_LABEL_PREFIX   config "launchdPrefix"   LaunchAgent labels: <prefix>.hub, <prefix>.tailscaled, <prefix>.agent.<id>
#   CHUMS_NODE           config "node"            the node binary LaunchAgents run (they don't get your shell's PATH)
# Usage: source "${0:A:h:h}/tools/common.zsh"

CHUMS_ROOT="${${(%):-%x}:A:h:h}"
CHUMS_HOME=~/.chums
CHUMS_CONFIG=$CHUMS_HOME/config.json

# chums_cfg <key>: a value from ~/.chums/config.json, or nothing
chums_cfg() {
  [[ -f $CHUMS_CONFIG ]] || return 0
  python3 -c 'import json,sys
try: v = json.load(open(sys.argv[1])).get(sys.argv[2])
except Exception: v = None
print("" if v is None else v)' "$CHUMS_CONFIG" "$1"
}

: ${CHUMS_LABEL_PREFIX:=$(chums_cfg launchdPrefix)}
: ${CHUMS_LABEL_PREFIX:=dev.chums}
: ${CHUMS_NODE:=$(chums_cfg node)}
: ${CHUMS_NODE:=$(command -v node)}

# chums_die <message…>: print to stderr and stop
chums_die() { print -u2 -- "chums: $*"; exit 1 }

# chums_help "$@": with -h or --help, print the script's opening comment (what it does, its usage) and stop
chums_help() {
  [[ ${1:-} == (-h|--help) ]] || return 0
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$ZSH_ARGZERO"
  exit 0
}

# chums_need <command> <how to get it>: stop with a clear message when a command is missing
chums_need() { command -v "$1" >/dev/null 2>&1 || chums_die "$1 is not installed. $2" }

# chums_sim_udid [name]: the UDID of the watch simulator bin/chums-sim made ("Chums Watch"), or nothing
chums_sim_udid() {
  DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} xcrun simctl list devices -j 2>/dev/null |
    python3 -c 'import json,sys
try: devices = json.load(sys.stdin)["devices"].values()
except Exception: raise SystemExit
for devs in devices:
    for d in devs:
        if d["name"] == sys.argv[1] and d["isAvailable"]: print(d["udid"]); raise SystemExit' "${1:-Chums Watch}"
}

# chums_sim_app: the watch app's bundle ID in the Simulator (what bin/chums-sim installs)
chums_sim_app() { local b=${CHUMS_BUNDLE:-$(chums_cfg bundleId)}; echo "${b:-dev.chums}.watchkitapp" }

# chums_need_config: stop unless the hub has written ~/.chums/config.json (it does on its first start)
chums_need_config() {
  [[ -f $CHUMS_CONFIG ]] || chums_die "no $CHUMS_CONFIG yet. Start the hub once (bin/chums-hub), then run this again."
}

# chums_reload <label> <plist>: stop a LaunchAgent and start it again from its plist. launchctl bootout returns before
# the job is gone, and a bootstrap too soon fails ("Bootstrap failed: 5: Input/output error"), so wait, and retry.
chums_reload() {
  local d=gui/$(id -u) i
  launchctl bootout $d/$1 2>/dev/null
  for i in {1..20}; do launchctl print $d/$1 >/dev/null 2>&1 || break; sleep 0.25; done
  for i in {1..4}; do launchctl bootstrap $d "$2" 2>/dev/null && return 0; sleep 1; done
  launchctl bootstrap $d "$2"
}
