"""Start a real chums-claude session in a pty and keep it alive (for demos and simulator testing).
Usage: python3 tools/demo-session.py <workdir> <name> [minutes] [extra claude args...]"""
import json, os, pty, re, select, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK, NAME = sys.argv[1], sys.argv[2]
MINUTES = float(sys.argv[3]) if len(sys.argv) > 3 else 20
EXTRA = " ".join(sys.argv[4:])
os.makedirs(WORK, exist_ok=True)
cfg = json.load(open(os.path.expanduser("~/.chums/config.json")))

def sessions():
    req = urllib.request.Request(f"http://127.0.0.1:{cfg['port']}/v1/state?since=0",
                                 headers={"authorization": f"Bearer {cfg['token']}"})
    return json.load(urllib.request.urlopen(req, timeout=10))["sessions"]

before = {s["id"] for s in sessions()}
pid, fd = pty.fork()
if pid == 0:
    os.chdir(WORK)
    os.environ.update(CHUMS_NO_RC="1", TERM="xterm-256color")
    os.execvp("zsh", ["zsh", "-c", f"{ROOT}/bin/chums-claude {NAME} {EXTRA}"])

screen = ""
def pump(sec):
    global screen
    end = time.time() + sec
    while time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            try: screen = (screen + os.read(fd, 65536).decode(errors="ignore"))[-20000:]
            except OSError: sys.exit(0)

plain = lambda s: re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07", "", s).replace(" ", "").lower()
done = set()
for _ in range(60):
    pump(1)
    tail = plain(screen)[-1500:]
    if "itrustthisfolder" in tail and "trust" not in done:
        done.add("trust"); os.write(fd, b"\x1b[B"); pump(0.3); os.write(fd, b"\r"); screen = ""
    elif "loadingdevelopmentchannels" in tail and "entertoconfirm" in tail and "dev" not in done:
        done.add("dev"); os.write(fd, b"\r"); screen = ""
    if any(s["name"] == NAME and s["id"] not in before for s in sessions()):
        break
print(f"session {NAME} ready", flush=True)
pump(MINUTES * 60)
os.write(fd, b"\x03"); pump(0.5); os.write(fd, b"\x03")
