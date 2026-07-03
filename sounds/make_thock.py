#!/usr/bin/env python3
"""Synthesizes a few deep 'thock' screenshot sounds into sounds/*.wav."""
import numpy as np, wave, os

sr = 44100
HERE = os.path.dirname(os.path.abspath(__file__))


def one_pole_lp(x, cutoff):
    dt = 1.0 / sr
    rc = 1.0 / (2 * np.pi * cutoff)
    alpha = dt / (rc + dt)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def attack(t, a):
    return np.clip(t / a, 0.0, 1.0)


def make(dur, f0, f1, tau_f, tau_a, click_amp, click_tau,
         tock_f, tock_amp, tock_tau, lp_cut, h2):
    n = int(sr * dur)
    t = np.arange(n) / sr
    f = f1 + (f0 - f1) * np.exp(-t / tau_f)
    phase = 2 * np.pi * np.cumsum(f) / sr
    body = (np.sin(phase) + h2 * np.sin(2 * phase)) * np.exp(-t / tau_a) * attack(t, 0.0015)
    tock = tock_amp * np.sin(2 * np.pi * tock_f * t) * np.exp(-t / tock_tau) * attack(t, 0.0008)
    rng = np.random.default_rng(7)
    click = click_amp * rng.standard_normal(n) * np.exp(-t / click_tau)
    x = one_pole_lp(body + tock + click, lp_cut)
    x = x / np.max(np.abs(x)) * 0.8
    fo = int(sr * 0.004)
    x[-fo:] *= np.linspace(1, 0, fo)
    return x


def write(path, x):
    x16 = np.int16(np.clip(x, -1, 1) * 32767)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(x16.tobytes())


variants = {
    "thock-deep":  dict(dur=.16, f0=170, f1=76, tau_f=.020, tau_a=.060, click_amp=.12, click_tau=.0030, tock_f=380, tock_amp=.12, tock_tau=.012, lp_cut=2200, h2=.20),
    "thock-tight": dict(dur=.10, f0=200, f1=90, tau_f=.012, tau_a=.032, click_amp=.18, click_tau=.0025, tock_f=500, tock_amp=.15, tock_tau=.008, lp_cut=3000, h2=.25),
    "thock-click": dict(dur=.15, f0=160, f1=70, tau_f=.020, tau_a=.055, click_amp=.30, click_tau=.0035, tock_f=620, tock_amp=.10, tock_tau=.010, lp_cut=3600, h2=.20),
    "thock-thump": dict(dur=.18, f0=140, f1=60, tau_f=.025, tau_a=.070, click_amp=.05, click_tau=.0040, tock_f=300, tock_amp=.08, tock_tau=.015, lp_cut=1600, h2=.15),
}

for name, p in variants.items():
    write(os.path.join(HERE, name + ".wav"), make(**p))
    print("wrote", name + ".wav")
