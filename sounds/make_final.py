#!/usr/bin/env python3
"""Two-part bubbles (low then high) + warms flipped to low then high."""
import numpy as np, wave, os

sr = 44100
HERE = os.path.dirname(os.path.abspath(__file__))


def lp(x, c):
    dt = 1.0 / sr; rc = 1.0 / (2 * np.pi * c); a = dt / (rc + dt)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc); y[i] = acc
    return y


def hp(x, c):
    return x - lp(x, c)


def atk(t, a):
    return np.clip(t / a, 0.0, 1.0)


def clack(dur, freq, tone_amp, click_amp, tau, locut, hicut, h2, seed):
    n = int(sr * dur); t = np.arange(n) / sr
    tone = (np.sin(2 * np.pi * freq * t) + h2 * np.sin(2 * np.pi * 2 * freq * t))
    tone *= np.exp(-t / tau) * atk(t, 0.0008) * tone_amp
    rng = np.random.default_rng(seed)
    noise = hp(rng.standard_normal(n) * np.exp(-t / (tau * 0.5)) * click_amp, hicut)
    return lp(tone + noise, locut)


def bubble(dur, f0, f1, glide_tau, amp_tau, pop, seed):
    n = int(sr * dur); t = np.arange(n) / sr
    f = f0 + (f1 - f0) * (1 - np.exp(-t / glide_tau))
    phase = 2 * np.pi * np.cumsum(f) / sr
    x = np.sin(phase) * np.exp(-t / amp_tau) * atk(t, 0.0010)
    rng = np.random.default_rng(seed)
    x += pop * hp(rng.standard_normal(n) * np.exp(-t / 0.002), 1500)
    return lp(x, 6500)


def two(c1, c2, gap):
    g = int(sr * gap); total = max(len(c1), g + len(c2)) + int(sr * 0.005)
    buf = np.zeros(total); buf[:len(c1)] += c1; buf[g:g + len(c2)] += c2
    buf = buf / np.max(np.abs(buf)) * 0.85
    fo = int(sr * 0.004); buf[-fo:] *= np.linspace(1, 0, fo)
    return buf


def write(name, x):
    x16 = np.int16(np.clip(x, -1, 1) * 32767)
    with wave.open(os.path.join(HERE, name + ".wav"), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(x16.tobytes())


# --- warm, flipped: low first (slow) then high ---
write("clack-warm-lowhigh", two(
    clack(.075, 175, .70, .42, .030, 3000, 380, .35, 1),   # low + slow
    clack(.060, 340, .60, .42, .022, 4000, 550, .22, 2),   # high
    .17))
write("clack-warm-lowhigh2", two(
    clack(.085, 160, .72, .40, .034, 2800, 340, .40, 1),   # lower + slower
    clack(.058, 380, .58, .42, .020, 4400, 600, .20, 2),   # higher
    .19))

# --- two-part bubbles: low bloop then high bloop ---
write("bubble-two-a", two(
    bubble(.060, 200, 520, .014, .026, .10, 3),
    bubble(.050, 320, 820, .011, .020, .12, 4),
    .10))
write("bubble-two-b", two(
    bubble(.055, 230, 560, .012, .022, .12, 5),
    bubble(.045, 400, 980, .009, .017, .14, 6),
    .085))
write("bubble-two-deep", two(
    bubble(.070, 160, 430, .016, .030, .09, 7),
    bubble(.055, 260, 640, .012, .022, .11, 8),
    .11))
print("done")
