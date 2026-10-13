"""Real end-to-end: start chums-claude in a pty, accept startup prompts, send an order as the watch
would, and wait for Claude to answer through chums_reply."""
import json, os, pty, re, select, subprocess, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = sys.argv[1]
os.makedirs(WORK, exist_ok=True)
cfg = json.load(open(os.path.expanduser("~/.chums/config.json")))
HUB = f"http://127.0.0.1:{cfg['port']}"

def hub(path, body=None):
    req = urllib.request.Request(HUB + path, data=json.dumps(body).encode() if body else None,
                                 headers={"authorization": f"Bearer {cfg['token']}", "content-type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=30))

existing = {x["id"] for x in hub("/v1/state?since=0")["sessions"]}
pid, fd = pty.fork()
if pid == 0:
    os.chdir(WORK)
    os.environ.update(CHUMS_NO_RC="1", TERM="xterm-256color")
    os.execvp("zsh", ["zsh", "-c", f"{ROOT}/bin/chums-claude e2e --permission-mode default"])

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
DOWN = b"\x1b[B"
for _ in range(40):
    pump(1)
    p = plain(screen).replace(" ", "").lower()
    tail = p[-1500:]
    if "itrustthisfolder" in tail and "trust" not in answered:
        answered.add("trust"); os.write(fd, DOWN); pump(0.3); os.write(fd, b"\r"); screen = ""; pump(2)
        continue
    if ("developmentchannel" in tail or "dangerously" in tail) and "entertoconfirm" in tail and "dev" not in answered:
        print("--- dev-channel prompt ---\n" + plain(screen)[-1200:])
        answered.add("dev")
        # pick the option that keeps the session running, not "Exit"
        if re.search(r"❯\s*(\d\.)?\s*(no|exit|cancel)", plain(screen)[-1200:], re.I):
            os.write(fd, DOWN); pump(0.3)
        os.write(fd, b"\r"); screen = ""; pump(2)
        continue
    if any(s["name"] == "e2e" and s["id"] not in existing for s in hub("/v1/state?since=0")["sessions"]):
        break
state = hub("/v1/state?since=0")
print("sessions:", [s["name"] for s in state["sessions"]], "| prompts answered:", sorted(answered))
if not any(s["name"] == "e2e" for s in state["sessions"]):
    print(plain(screen)[-3000:]); os.kill(pid, 9); sys.exit(1)

t0 = time.time()
old = {s["id"] for s in state["spoken"]}
r = hub("/v1/say", {"text": "e2e, what is seven times six? Just answer through Chums."})
print("echo:", r.get("echo"))
reply = None
while time.time() - t0 < 120 and not reply:
    pump(1)
    reply = next((s for s in hub("/v1/state?since=0")["spoken"] if s["session"] == "e2e" and s["id"] not in old), None)
print(f"reply after {time.time()-t0:.1f}s:", reply and reply["text"])

# Permission relay with a real prompt: a shell command needs approval; answer it "from the watch".
target = os.path.join(WORK, "chums-proof.txt")
if os.path.exists(target): os.remove(target)
seen = {s["id"] for s in hub("/v1/state?since=0")["spoken"]}
t1 = time.time()
hub("/v1/say", {"text": "e2e, use the Bash tool to run: echo approved-from-watch > chums-proof.txt"})
approval = None
while time.time() - t1 < 90 and not approval:
    pump(1)
    ap = hub("/v1/state?since=0")["approvals"]
    approval = ap[0] if ap else None
print(f"approval card after {time.time()-t1:.1f}s:", approval and {k: approval[k] for k in ("tool", "description", "preview")})
if approval:
    v = hub("/v1/say", {"text": "yes"})
    print("verdict:", v.get("echo"))
    done = None
    while time.time() - t1 < 150 and not done:
        pump(1)
        done = next((s for s in hub("/v1/state?since=0")["spoken"] if s["session"] == "e2e" and s["id"] not in seen), None)
    print("file written:", os.path.exists(target) and open(target).read().strip(), "| reply:", done and done["text"])
os.write(fd, b"\x03"); pump(0.5); os.write(fd, b"\x03"); pump(1)
try: os.kill(pid, 9)
except ProcessLookupError: pass
if not reply:
    print(plain(screen)[-3000:]); sys.exit(1)
