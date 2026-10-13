"""Live test for the watch: a real Claude Code session does real work (reads, edits, runs tests) while the
watch app shows it. Answers the Bash approval "from the watch" after a pause so the card can be seen.
usage: e2e-watch.py WORKDIR"""
import json, os, pty, re, select, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = sys.argv[1]
cfg = json.load(open(os.path.expanduser("~/.chums/config.json")))
HUB = f"http://127.0.0.1:{cfg['port']}"
def hub(path, body=None):
    req = urllib.request.Request(HUB + path, data=json.dumps(body).encode() if body else None,
                                 headers={"authorization": f"Bearer {cfg['token']}", "content-type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=30))

existing = {x["id"] for x in hub("/v1/state?since=0")["sessions"]}
pid, fd = pty.fork()
if pid == 0:
    os.chdir(WORK); os.environ.update(CHUMS_NO_RC="1", TERM="xterm-256color")
    os.execvp("zsh", ["zsh", "-c", f"{ROOT}/bin/chums-claude demo --permission-mode acceptEdits"])
screen = ""
def pump(sec):
    global screen
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try: screen += os.read(fd, 65536).decode(errors="ignore")
            except OSError: return
    screen = screen[-20000:]
plain = lambda s: re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07", "", s)
answered = set()
for _ in range(40):
    pump(1)
    tail = plain(screen).replace(" ", "").lower()[-1500:]
    if "itrustthisfolder" in tail and "trust" not in answered:
        answered.add("trust"); os.write(fd, b"\x1b[B"); pump(0.3); os.write(fd, b"\r"); screen = ""; pump(2); continue
    if ("developmentchannel" in tail or "dangerously" in tail) and "entertoconfirm" in tail and "dev" not in answered:
        answered.add("dev")
        if re.search(r"❯\s*(\d\.)?\s*(no|exit|cancel)", plain(screen)[-1200:], re.I): os.write(fd, b"\x1b[B"); pump(0.3)
        os.write(fd, b"\r"); screen = ""; pump(2); continue
    if any(s["name"] == "demo" and s["id"] not in existing for s in hub("/v1/state?since=0")["sessions"]): break
print("session up:", any(s["name"] == "demo" for s in hub("/v1/state?since=0")["sessions"]), flush=True)
pump(3)
seen = {s["id"] for s in hub("/v1/state?since=0")["spoken"]}
t0 = time.time()
r = hub("/v1/say", {"text": "demo, read math.js and test.js, add a square function to math.js with a test for it in test.js, then run npm test with the Bash tool and tell me the result through Chums."})
print("order:", r.get("echo"), flush=True)
reply, approved = None, 0
while time.time() - t0 < 240 and not reply:
    pump(1)
    st = hub("/v1/state?since=0")
    if st["approvals"]:
        a = st["approvals"][0]
        print(f"{time.time()-t0:5.1f}s approval: {a['tool']} {a['summary']}", flush=True)
        pump(5)                                     # leave the card on the watch for a moment
        print("   ->", hub("/v1/say", {"text": "yes"}).get("echo"), flush=True); approved += 1
    reply = next((s for s in st["spoken"] if s["session"] == "demo" and s["id"] not in seen and s["kind"] != "echo"), None)
print(f"{time.time()-t0:5.1f}s reply:", reply and reply["text"], flush=True)
print("tools seen:", [t["text"] + ("" if t["ok"] is None else (" ✓" if t["ok"] else " ✗")) for t in hub("/v1/state?since=0")["tools"] if t["session"] == "demo"], flush=True)
pump(8)
os.write(fd, b"\x03"); pump(0.5); os.write(fd, b"\x03"); pump(1)
try: os.kill(pid, 9)
except ProcessLookupError: pass
