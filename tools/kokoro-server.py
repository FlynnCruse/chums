"""The agents' voices: Kokoro (82M, Apache-2.0) on the Mac's GPU through MLX, for the hub only (127.0.0.1).

    ~/.chums/kokoro/.venv/bin/python tools/kokoro-server.py --port 50062 --voices bf_lily,am_santa,...

It loads the model once and says a word in each voice it's given (so the first reply in a voice is as quick as any),
then answers POST /speak {"text": "...", "voice": "bf_lily", "speed": 1.0} with the speech as AAC in an .m4a (what the
watch plays), about 0.15 s for a one-sentence reply on an M-series Mac. GET /health says it's ready. One at a time:
MLX runs on one GPU queue, and replies are short. bin/chums-setup installs it (tools/kokoro-requirements.txt).
"""
import argparse
import ctypes
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

p = argparse.ArgumentParser()
p.add_argument('--port', type=int, default=50062)
p.add_argument('--voices', default='bf_lily')
p.add_argument('--model', default='mlx-community/Kokoro-82M-bf16')
p.add_argument('--once', action='store_true', help='download what it needs, say a sentence in each voice, and exit (bin/chums-setup)')
a = p.parse_args()

t0 = time.time()
from mlx_audio.tts.utils import load_model  # noqa: E402  (after argparse: --help stays fast)

model = load_model(a.model)
lock = threading.Lock()
RATE = 24000


_libc = ctypes.CDLL('/usr/lib/libSystem.dylib')


def interactive():
    """This thread runs at user-interactive priority: after a quiet while a render takes about half as long."""
    _libc.pthread_set_qos_class_self_np(0x21, 0)   # QOS_CLASS_USER_INTERACTIVE


def speak(text, voice, speed=1.0):
    """Float samples at 24 kHz. The voice's first letter is its language: a American English, b British."""
    with lock:
        parts = [np.array(r.audio) for r in model.generate(text=text, voice=voice, speed=speed, lang_code=voice[0])]
    return np.concatenate(parts) if parts else np.zeros(0, dtype=np.float32)


TARGET_RMS = 10 ** (-16 / 20)   # -16 dBFS: a bit louder than Apple's own speech (-19.6), for the watch's small speaker
LIMIT, CEIL = 0.62, 0.86          # above LIMIT, peaks are rounded off smoothly up to CEIL (-1.3 dBFS: AAC overshoots)


def loud(x):
    """Every voice as loud as the others, and louder than Kokoro makes them (-22 to -27 dBFS): gain to the target
    level, then a soft limiter on the few peaks that would clip."""
    rms = float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0
    if rms < 1e-5:
        return x
    y = x * (TARGET_RMS / rms)
    over = np.abs(y) > LIMIT
    y[over] = np.sign(y[over]) * (LIMIT + (CEIL - LIMIT) * np.tanh((np.abs(y[over]) - LIMIT) / (CEIL - LIMIT)))
    return y


def m4a(samples):
    """AAC in an .m4a, the way the watch plays it (about 20 KB for a sentence, encoded in about 30 ms)."""
    pcm = (np.clip(loud(samples), -1, 1) * 32767).astype('<i2').tobytes()
    with tempfile.TemporaryDirectory() as d:
        wav, out = os.path.join(d, 's.wav'), os.path.join(d, 's.m4a')
        with wave.open(wav, 'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(pcm)
        subprocess.run(['/usr/bin/afconvert', '-f', 'm4af', '-d', 'aac', '-b', '32000', wav, out], check=True)
        with open(out, 'rb') as f:
            return f.read()


ready = False
# Kokoro's English voices (a American, b British): "--voices english" is all of them (bin/chums-setup downloads them
# all, so any one can be picked on the watch while the hub runs offline)
ENGLISH = ('af_heart af_bella af_nicole af_aoede af_kore af_sarah af_alloy af_nova af_sky af_jessica af_river am_fenrir '
           'am_michael am_puck am_echo am_eric am_liam am_onyx am_santa am_adam bf_emma bf_isabella bf_alice bf_lily '
           'bm_fable bm_george bm_lewis bm_daniel').split()
voices = ENGLISH if a.voices == 'english' else [v for v in a.voices.split(',') if v]


def warm():
    global ready
    interactive()
    for v in voices:
        try:
            speak("I'm ready when you are. Tell me what you need.", v)   # a full sentence: the first real one isn't slower
        except Exception as e:  # a voice that won't load is skipped, the others still work
            print(f'kokoro: voice {v} failed to warm: {e}', file=sys.stderr, flush=True)
    ready = True
    print(f'kokoro: ready in {time.time() - t0:.1f} s with {", ".join(voices)}', file=sys.stderr, flush=True)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, code, body, kind='application/json'):
        self.send_response(code)
        self.send_header('content-type', kind)
        self.send_header('content-length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/health':
            return self.reply(200 if ready else 503, json.dumps({'ready': ready, 'voices': voices}).encode())
        self.reply(404, b'{}')

    def do_POST(self):
        interactive()
        if self.path != '/speak':
            return self.reply(404, b'{}')
        try:
            q = json.loads(self.rfile.read(int(self.headers.get('content-length', 0))) or b'{}')
            text, voice = str(q.get('text', '')).strip(), str(q.get('voice') or voices[0])
            if not text:
                return self.reply(400, b'{"error":"no text"}')
            t = time.time()
            samples = speak(text, voice, float(q.get('speed', 1.0)))
            gen = time.time() - t
            body = m4a(samples)
            self.send_response(200)
            self.send_header('content-type', 'audio/mp4')
            self.send_header('content-length', str(len(body)))
            self.send_header('x-kokoro-ms', f'{gen * 1000:.0f}')
            self.send_header('x-audio-seconds', f'{len(samples) / RATE:.2f}')
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            self.reply(500, json.dumps({'error': str(e)}).encode())


if a.once:
    warm()
    sys.exit(0)
threading.Thread(target=warm, daemon=True).start()
ThreadingHTTPServer(('127.0.0.1', a.port), Handler).serve_forever()
