#!/usr/bin/env python3
"""Two-part 'modern shutter' sounds: a lower click then a higher click."""
import numpy as np, wave, os

sr = 44100
HERE = os.path.dirname(os.path.abspath(__file__))


def one_pole_lp(x, cutoff):
    dt = 1.0 / sr
    rc = 1.0 / (2 * np.pi * cutoff)
    alpha = dt / (rc + dt)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc); y[i] = acc
    return y


def attack(t, a):
    return np.clip(t / a, 0.0, 1.0)


def click(dur, freq, tone_amp, click_amp, tau, lp, h2, seed):
    n = int(sr * dur); t = np.arange(n) / sr
    tone = (np.sin(2 * np.pi * freq * t) + h2 * np.sin(2 * np.pi * 2 * freq * t))
    tone *= np.exp(-t / tau) * attack(t, 0.0010) * tone_amp
    rng = np.random.default_rng(seed)
    noise = click_amp * rng.standard_normal(n) * np.exp(-t / (tau * 0.4))
    return one_pole_lp(tone + noise, lp)


def shutter(low, high, gap):
    c1 = click(seed=1, **low)
    c2 = click(seed=2, **high)
    gap_n = int(sr * gap)
    total = max(len(c1), gap_n + len(c2)) + int(sr * 0.005)
    buf = np.zeros(total)
    buf[:len(c1)] += c1
    buf[gap_n:gap_n + len(c2)] += c2
    buf = buf / np.max(np.abs(buf)) * 0.82
    fo = int(sr * 0.004); buf[-fo:] *= np.linspace(1, 0, fo)
    return buf


def write(path, x):
    x16 = np.int16(np.clip(x, -1, 1) * 32767)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(x16.tobytes())


def C(dur, freq, tone_amp, click_amp, tau, lp, h2):
    return dict(dur=dur, freq=freq, tone_amp=tone_amp, click_amp=click_amp, tau=tau, lp=lp, h2=h2)

variants = {
    "shutter-soft":   (C(.045, 300, .9, .10, .022, 3200, .3), C(.035, 560, .9, .10, .016, 4200, .3), .055),
    "shutter-crisp":  (C(.038, 340, .8, .16, .018, 4200, .3), C(.030, 640, .8, .16, .013, 5200, .3), .046),
    "shutter-mech":   (C(.045, 250, .7, .22, .020, 3000, .25), C(.036, 500, .7, .22, .015, 4000, .25), .062),
    "shutter-snappy": (C(.032, 360, .85, .14, .015, 4600, .3), C(.026, 720, .85, .14, .011, 5600, .3), .040),
}

for name, (lo, hi, gap) in variants.items():
    write(os.path.join(HERE, name + ".wav"), shutter(lo, hi, gap))
    print("wrote", name + ".wav")
