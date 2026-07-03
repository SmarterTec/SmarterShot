#!/usr/bin/env python3
"""More clacky two-part shutter alternatives, different vibes."""
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


def shutter(low, high, gap):
    c1 = clack(seed=1, **low); c2 = clack(seed=2, **high)
    g = int(sr * gap); total = max(len(c1), g + len(c2)) + int(sr * 0.005)
    buf = np.zeros(total); buf[:len(c1)] += c1; buf[g:g + len(c2)] += c2
    buf = buf / np.max(np.abs(buf)) * 0.85
    fo = int(sr * 0.004); buf[-fo:] *= np.linspace(1, 0, fo)
    return buf


def write(path, x):
    x16 = np.int16(np.clip(x, -1, 1) * 32767)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(x16.tobytes())


def C(dur, freq, tone_amp, click_amp, tau, locut, hicut, h2=0.0):
    return dict(dur=dur, freq=freq, tone_amp=tone_amp, click_amp=click_amp,
                tau=tau, locut=locut, hicut=hicut, h2=h2)

variants = {
    # brighter, glassy/tech click
    "clack-glass": (C(.045, 330, .40, .60, .016, 7000, 1300), C(.04, 640, .40, .60, .013, 8000, 1600), .11),
    # softer, rounder, damped
    "clack-muted": (C(.06, 240, .55, .40, .022, 3000, 400, .15), C(.052, 450, .55, .40, .017, 3600, 600, .15), .12),
    # very tight snappy double-tap
    "clack-snap":  (C(.035, 300, .45, .62, .012, 6000, 1000), C(.03, 600, .45, .62, .010, 6800, 1300), .085),
    # warm, woody, slight body
    "clack-warm":  (C(.055, 210, .60, .45, .020, 3800, 450, .25), C(.048, 400, .60, .45, .016, 4600, 700, .25), .12),
}

for name, (lo, hi, gap) in variants.items():
    write(os.path.join(HERE, name + ".wav"), shutter(lo, hi, gap))
    print("wrote", name + ".wav")
