"""Run a terminal program in a pseudo-terminal, act on it, and print what it drew, for tests of terminal UIs.

    python3 tools/pty-run.py '<steps as JSON>' <command> [args...]

Steps, in order: {"wait": seconds}, {"type": "text"} (typed a character at a time), {"key": "enter"}, {"mark": "name"}
(writes ###name### into the output, so a test can tell what was drawn before and after). The terminal is 140 x 60.
The output is the plain text drawn (escape sequences and all whitespace removed), with the marks; the program is
killed at the end.
"""
import fcntl, json, os, pty, re, select, struct, sys, termios, time

steps = json.loads(sys.argv[1])
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp(sys.argv[2], sys.argv[2:])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 140, 0, 0))
out = []


def pump(seconds):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if not r:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return
        out.append(chunk)
        if b"\x1b[6n" in chunk:                       # where's the cursor? (the UI waits for an answer)
            os.write(fd, b"\x1b[1;1R")


for step in steps:
    if "wait" in step:
        pump(step["wait"])
    elif "type" in step:
        for ch in step["type"]:
            os.write(fd, ch.encode())
            pump(0.03)
    elif step.get("key") == "enter":
        os.write(fd, b"\r")
        pump(0.2)
    elif "mark" in step:
        out.append(f"###{step['mark']}###".encode())
os.kill(pid, 9)
text = b"".join(out).decode(errors="ignore")
text = re.sub(r"\x1b\[[0-9;?<>=]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][A-Z0-9]|\x1b[=>78]", "", text)
print(re.sub(r"\s+", "", text))
