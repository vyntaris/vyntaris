#!/usr/bin/env python3
import math, os, struct, sys, wave

SR = 44100
TW = 2 * math.pi

def tone(buf, t0, f, amp, attack, decay, partials=((1, 1, 1),), length=None):
    s0 = int(t0 * SR)
    end = len(buf) if length is None else min(len(buf), s0 + int(length * SR))
    for i in range(end - s0):
        t = i / SR
        env = (1 - math.exp(-t / attack)) * math.exp(-t / decay)
        if env < 1e-4 and t > attack * 5:
            break
        v = 0.0
        for r, g, d in partials:
            v += g * math.sin(TW * f * r * t) * (math.exp(-t / (decay * d)) if d != 1 else 1)
        buf[s0 + i] += amp * env * v

def echo(buf, taps):
    out = buf[:]
    for d, g in taps:
        k = int(d * SR)
        for i in range(k, len(buf)):
            out[i] += g * buf[i - k]
    return out

def write(path, buf, level=0.7, fade=0.3):
    n = len(buf)
    peak = max(abs(x) for x in buf) or 1
    fade_n = int(fade * SR)
    frames = bytearray()
    for i, x in enumerate(buf):
        x = x / peak * level
        if i > n - fade_n:
            x *= (n - i) / fade_n
        frames += struct.pack("<h", int(max(-1, min(1, x)) * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("wrote", path, file=sys.stderr)

ROOM = ((0.043, 0.28), (0.071, 0.2), (0.113, 0.14), (0.167, 0.09), (0.241, 0.05))

SOFT = ((1, 1, 1), (2.0, 0.22, 0.5), (3.01, 0.08, 0.3))

def notification():
    buf = [0.0] * int(SR * 1.0)
    tone(buf, 0.00, 1318.5, 0.25, 0.003, 0.22, SOFT)
    tone(buf, 0.09, 1760.0, 0.22, 0.003, 0.30, SOFT)
    return echo(buf, ROOM[:3])

def notification_urgent():
    buf = [0.0] * int(SR * 1.2)
    tone(buf, 0.00, 1174.7, 0.26, 0.002, 0.14, SOFT)
    tone(buf, 0.11, 1174.7, 0.26, 0.002, 0.14, SOFT)
    tone(buf, 0.22, 1568.0, 0.28, 0.002, 0.36, SOFT)
    return echo(buf, ROOM[:3])

def sweep(buf, t0, f0, f1, glide, amp, decay, partials=((1, 1),)):
    s0 = int(t0 * SR)
    phase = 0.0
    for i in range(len(buf) - s0):
        t = i / SR
        env = (1 - math.exp(-t / 0.002)) * math.exp(-t / decay)
        if env < 1e-4 and t > 0.01:
            break
        k = min(1.0, t / glide)
        f = f0 * (f1 / f0) ** k
        phase += TW * f / SR
        buf[s0 + i] += amp * env * sum(g * math.sin(phase * r) for r, g in partials)

def whoosh(buf, t0, length, f0, f1, amp, q=4.0, seed=7):
    import random
    rnd = random.Random(seed)
    s0, n = int(t0 * SR), int(length * SR)
    x1 = x2 = y1 = y2 = 0.0
    b0 = b2 = a1 = a2 = 0.0
    for i in range(min(n, len(buf) - s0)):
        if i % 32 == 0:
            k = i / n
            fc = f0 * (f1 / f0) ** k
            w = TW * fc / SR
            alpha = math.sin(w) / (2 * q)
            a0 = 1 + alpha
            b0, b2 = alpha / a0, -alpha / a0
            a1, a2 = -2 * math.cos(w) / a0, (1 - alpha) / a0
        x = rnd.uniform(-1, 1)
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        k = i / n
        env = math.sin(math.pi * min(1.0, k * 1.15)) ** 1.5
        buf[s0 + i] += amp * env * y

def bell(buf, t0, f, amp=0.22, decay=0.55, bright=0.28, attack=0.006, inharm=3.01):
    s0 = int(t0 * SR)
    for i in range(len(buf) - s0):
        t = i / SR
        env = (1 - math.exp(-t / attack)) * math.exp(-t / decay)
        if env < 1e-4 and t > 0.1:
            break
        v = (math.sin(TW * f * t)
             + bright * math.sin(TW * f * 2.0 * t) * math.exp(-t / (decay * 0.45))
             + 0.10 * math.sin(TW * f * inharm * t) * math.exp(-t / (decay * 0.22)))
        buf[s0 + i] += amp * env * v

def pad(buf, t0, f, amp, rise, length):
    s0, n = int(t0 * SR), int(length * SR)
    for i in range(min(n, len(buf) - s0)):
        t = i / SR
        env = min(1, t / rise) * math.exp(-max(0, t - rise) / (length * 0.35))
        v = math.sin(TW * f * t) + 0.5 * math.sin(TW * f * 1.003 * t) + 0.25 * math.sin(TW * f * 2 * t)
        buf[s0 + i] += amp * env * v

def bloom():
    buf = [0.0] * int(SR * 3.2)
    for f in (261.6, 329.6, 392.0, 587.3):
        pad(buf, 0.0, f, 0.035, 0.45, 2.6)
    bell(buf, 0.38, 1046.5, amp=0.22, decay=0.7)
    bell(buf, 0.52, 1568.0, amp=0.12, decay=0.6)
    return echo(buf, ROOM)

def halo():
    buf = [0.0] * int(SR * 3.0)
    for k, f in enumerate((392.0, 493.9, 587.3, 784.0)):
        bell(buf, k * 0.025, f, amp=0.16, decay=0.95, bright=0.2)
    bell(buf, 0.25, 1568.0, amp=0.07, decay=0.8)
    return echo(buf, ROOM)

def notification_pop():
    buf = [0.0] * int(SR * 0.5)
    sweep(buf, 0.0, 520.0, 1180.0, 0.05, 0.4, 0.06, ((1, 1), (2, 0.15)))
    return echo(buf, ROOM[:2])

def notification_drop():
    buf = [0.0] * int(SR * 0.7)
    sweep(buf, 0.0, 1760.0, 880.0, 0.03, 0.3, 0.1, ((1, 1),))
    sweep(buf, 0.045, 990.0, 1480.0, 0.06, 0.18, 0.12, ((1, 1),))
    return echo(buf, ROOM[:3])

def notification_tick():
    buf = [0.0] * int(SR * 0.5)
    wood = ((1, 1, 1), (2.7, 0.4, 0.4), (5.1, 0.2, 0.25))
    tone(buf, 0.0, 2200.0, 0.3, 0.001, 0.025, wood)
    tone(buf, 0.085, 2900.0, 0.26, 0.001, 0.03, wood)
    return echo(buf, ROOM[:2])

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, make in (("bloom", bloom), ("halo", halo), ("notification", notification),
                       ("notification-pop", notification_pop), ("notification-drop", notification_drop),
                       ("notification-tick", notification_tick), ("notification-urgent", notification_urgent)):
        write(os.path.join(out, name + ".wav"), make(), fade=0.3 if name in ("bloom", "halo") else 0.2)
