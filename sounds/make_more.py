#!/usr/bin/env python3
"""Warm variants (slower first clack, deeper second) + bubble-pop sounds."""
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


def two(c1, c2, gap):
    g = int(sr * gap); total = max(len(c1), g + len(c2)) + int(sr * 0.005)
    buf = np.zeros(total); buf[:len(c1)] += c1; buf[g:g + len(c2)] += c2
    buf = buf / np.max(np.abs(buf)) * 0.85
    fo = int(sr * 0.004); buf[-fo:] *= np.linspace(1, 0, fo)
    return buf


def bubble(dur, f0, f1, glide_tau, amp_tau, pop, seed):
    n = int(sr * dur); t = np.arange(n) / sr
    f = f0 + (f1 - f0) * (1 - np.exp(-t / glide_tau))   # pitch rises = "bloop"
    phase = 2 * np.pi * np.cumsum(f) / sr
    x = np.sin(phase) * np.exp(-t / amp_tau) * atk(t, 0.0010)
    rng = np.random.default_rng(seed)
    x += pop * hp(rng.standard_normal(n) * np.exp(-t / 0.002), 1500)  # tiny "p" transient
    x = lp(x, 6000)
    x = x / np.max(np.abs(x)) * 0.82
    fo = int(sr * 0.004); x[-fo:] *= np.linspace(1, 0, fo)
    return x


def write(name, x):
    x16 = np.int16(np.clip(x, -1, 1) * 32767)
    with wave.open(os.path.join(HERE, name + ".wav"), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(x16.tobytes())


# --- warm: slower first clack (longer decay + wider gap), deeper second ---
def C(dur, freq, tone_amp, click_amp, tau, locut, hicut, h2, seed):
    return clack(dur, freq, tone_amp, click_amp, tau, locut, hicut, h2, seed)

write("clack-warm-slowdeep", two(
    C(.075, 235, .60, .45, .030, 3800, 450, .22, 1),   # slower first
    C(.070, 175, .70, .38, .026, 3000, 350, .40, 2),   # deeper second
    .17))
write("clack-warm-slowdeep2", two(
    C(.085, 250, .58, .42, .034, 3600, 450, .20, 1),   # even slower first
    C(.075, 150, .75, .34, .028, 2600, 300, .45, 2),   # even deeper second
    .20))

# --- bubble pops ---
write("bubble-a", bubble(.055, 360, 900, .012, .020, .12, 3))
write("bubble-b", bubble(.070, 220, 620, .016, .028, .10, 4))
write("bubble-pop", bubble(.045, 300, 1050, .009, .015, .18, 5))
print("done")
