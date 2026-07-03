#!/usr/bin/env python3
"""Slower, clackier two-part shutter: harder noise-driven clicks, wider gap."""
import numpy as np, wave, os

sr = 44100
HERE = os.path.dirname(os.path.abspath(__file__))


def one_pole_lp(x, cutoff):
    dt = 1.0 / sr; rc = 1.0 / (2 * np.pi * cutoff); alpha = dt / (rc + dt)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc); y[i] = acc
    return y


def one_pole_hp(x, cutoff):
    return x - one_pole_lp(x, cutoff)


def attack(t, a):
    return np.clip(t / a, 0.0, 1.0)


def clack(dur, freq, tone_amp, click_amp, tau, lp, hp, seed):
    n = int(sr * dur); t = np.arange(n) / sr
    tone = np.sin(2 * np.pi * freq * t) * np.exp(-t / tau) * attack(t, 0.0008) * tone_amp
    rng = np.random.default_rng(seed)
    # hard noise transient shaped short = the "clack"
    noise = rng.standard_normal(n) * np.exp(-t / (tau * 0.5)) * click_amp
    noise = one_pole_hp(noise, hp)          # brighten for clack
    return one_pole_lp(tone + noise, lp)


def shutter(low, high, gap):
    c1 = clack(seed=1, **low); c2 = clack(seed=2, **high)
    gap_n = int(sr * gap)
    total = max(len(c1), gap_n + len(c2)) + int(sr * 0.005)
    buf = np.zeros(total)
    buf[:len(c1)] += c1
    buf[gap_n:gap_n + len(c2)] += c2
    buf = buf / np.max(np.abs(buf)) * 0.85
    fo = int(sr * 0.004); buf[-fo:] *= np.linspace(1, 0, fo)
    return buf


def write(path, x):
    x16 = np.int16(np.clip(x, -1, 1) * 32767)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(x16.tobytes())


def C(dur, freq, tone_amp, click_amp, tau, lp, hp):
    return dict(dur=dur, freq=freq, tone_amp=tone_amp, click_amp=click_amp, tau=tau, lp=lp, hp=hp)

variants = {
    "clack-a": (C(.05, 260, .45, .55, .018, 5000, 600), C(.045, 480, .45, .55, .015, 6000, 900), .10),
    "clack-b": (C(.055, 230, .35, .70, .020, 5500, 500), C(.05, 430, .35, .70, .016, 6500, 800), .12),
    "clack-c": (C(.06, 280, .40, .60, .022, 4500, 700), C(.05, 540, .40, .60, .017, 5500, 1000), .14),
    "clack-wood": (C(.05, 300, .55, .48, .016, 4000, 500), C(.045, 560, .55, .48, .013, 5000, 800), .11),
}

for name, (lo, hi, gap) in variants.items():
    write(os.path.join(HERE, name + ".wav"), shutter(lo, hi, gap))
    print("wrote", name + ".wav")
