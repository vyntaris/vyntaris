#!/usr/bin/env python3
import math, struct, wave, sys, time
t_start = time.time()
SR = 44100; dur = 2.4; n = int(SR * dur)
buf = [0.0] * n
notes = [(784.0, 0.00), (987.8, 0.09), (1174.7, 0.18), (1568.0, 0.30)]
tw = 2 * math.pi
for f, t0 in notes:
    s0 = int(t0 * SR)
    for i in range(n - s0):
        t = i / SR
        env = (1 - math.exp(-t / 0.006)) * math.exp(-t / 0.55)
        if env < 1e-4 and t > 0.1: break
        v = (math.sin(tw * f * t)
             + 0.28 * math.sin(tw * f * 2.0 * t) * math.exp(-t / 0.25)
             + 0.10 * math.sin(tw * f * 3.01 * t) * math.exp(-t / 0.12))
        buf[s0 + i] += 0.22 * env * v
print("tones", round(time.time() - t_start, 1), file=sys.stderr)
out = buf[:]
for d, g in ((0.043, 0.28), (0.071, 0.2), (0.113, 0.14), (0.167, 0.09), (0.241, 0.05)):
    k = int(d * SR)
    for i in range(k, n):
        out[i] += g * buf[i - k]
print("echo", round(time.time() - t_start, 1), file=sys.stderr)
peak = max(abs(x) for x in out); fade = int(0.25 * SR)
frames = bytearray()
for i, x in enumerate(out):
    x = x / peak * 0.7
    if i > n - fade: x *= (n - i) / fade
    frames += struct.pack("<h", int(max(-1, min(1, x)) * 32767))
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(frames))
print("done", round(time.time() - t_start, 1), file=sys.stderr)
