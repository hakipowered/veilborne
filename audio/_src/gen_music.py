"""Procedurally composes and renders Veilborne's music (original compositions) to audio/music/*.ogg.
Loops are rendered with their reverb/release tails wrapped back onto the start, so the
file loops seamlessly from end to start (loop_offset 0).
Run:  python3 audio/_src/gen_music.py [track ...]"""
import os, sys
import numpy as np
from scipy.ndimage import maximum_filter1d, uniform_filter1d
sys.path.insert(0, os.path.dirname(__file__))
from synth import *

OUT = os.path.join(os.path.dirname(__file__), '..', 'music')
R = np.random.default_rng(2024)
_cache = {}


def N(d):
    return int(d * SR)


def f_(m):
    return float(mtof(m))


# ======================= instruments (mono) =======================
def strings(m, dur, vel=1.0, bright=1.0, attack=0.25, rel=0.6, vib=True):
    key = ('str', m, round(dur, 3), bright, attack, rel, vib)
    if key not in _cache:
        n = N(dur + rel)
        f = f_(m)
        y = np.zeros(n)
        t = np.arange(n) / SR
        vibr = (1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.6, 0, 1)) if vib else 1.0
        for det in (-0.007, -0.002, 0.003, 0.008):
            y += saw(f * (1 + det) * vibr, n, ph0=R.random())
        y = lp(y, min(1200 + f * 2.5 * bright, 9000), order=2)
        y = y * adsr(n, attack, 0.2, 0.85, rel, hold=max(dur - attack - 0.2, 0))
        _cache[key] = y * 0.25
    return _cache[key] * vel


def stacc(m, dur=0.16, vel=1.0, bright=1.0):
    key = ('stc', m, round(dur, 3), bright)
    if key not in _cache:
        n = N(dur + 0.12)
        f = f_(m)
        y = sum(saw(f * (1 + d), n, ph0=R.random()) for d in (-0.006, 0.0, 0.007))
        t = np.arange(n) / SR
        y = sweep_filter(y, min(4500 * bright + f, 12000), 900 + f, 'low', blocks=8)
        y *= adsr(n, 0.006, dur * 0.6, 0.35, 0.1, hold=dur * 0.3)
        _cache[key] = y * 0.3
    return _cache[key] * vel


def choir(m, dur, vowel='a', vel=1.0, attack=0.45, rel=0.8, voices=4, breath=0.08):
    key = ('ch', m, round(dur, 3), vowel, attack, rel, voices)
    if key not in _cache:
        n = N(dur + rel)
        f = f_(m)
        t = np.arange(n) / SR
        y = np.zeros(n)
        for v in range(voices):
            vr = 1 + 0.006 * np.sin(2 * np.pi * (4.8 + R.random()) * t + R.random() * 6)
            y += saw(f * (1 + R.uniform(-0.009, 0.009)) * vr, n, ph0=R.random())
        y += breath * hp(R.standard_normal(n), 2000) * voices
        sh = 1.12 if m >= 64 else 1.0
        y = formant(y, vowel, sh) + 0.12 * lp(y, 3500)
        y = lp(y, 8000)
        y *= adsr(n, attack, 0.3, 0.9, rel, hold=max(dur - attack - 0.3, 0))
        _cache[key] = y * 0.22 / voices ** 0.5
    return _cache[key] * vel


def chant(m, dur, vowel, vel=1.0):
    return choir(m, dur, vowel, vel, attack=0.02, rel=0.12, voices=5, breath=0.12)


def cello(m, dur, vel=1.0, attack=0.12, rel=0.5):
    key = ('cel', m, round(dur, 3), attack)
    if key not in _cache:
        n = N(dur + rel)
        f = f_(m)
        t = np.arange(n) / SR
        vr = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.2) / 0.5, 0, 1)
        y = saw(f * vr, n) + 0.5 * saw(f * 1.003 * vr, n, ph0=0.3)
        y += 0.05 * bp(R.standard_normal(n), 1500, 5000)
        y = peak(y, 300, 2) * 0.6 + peak(y, 1100, 3) * 0.4 + lp(y, 2500) * 0.5
        y *= adsr(n, attack, 0.2, 0.85, rel, hold=max(dur - attack - 0.2, 0))
        _cache[key] = y * 0.3
    return _cache[key] * vel


def flute(m, dur, vel=1.0, rel=0.25):
    key = ('fl', m, round(dur, 3))
    if key not in _cache:
        n = N(dur + rel)
        f = f_(m)
        t = np.arange(n) / SR
        vr = 1 + 0.005 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.25) / 0.4, 0, 1)
        y = sine(f * vr, n) + 0.18 * sine(2 * f * vr, n) + 0.06 * sine(3 * f * vr, n)
        br = bp(R.standard_normal(n), f * 0.8, min(f * 3, 15000)) * 0.12
        y = y + br
        y *= adsr(n, 0.06, 0.1, 0.85, rel, hold=max(dur - 0.16, 0))
        _cache[key] = y * 0.35
    return _cache[key] * vel


def pluck(m, dur, vel=1.0, bright=1.0, decay=1.4, nh=26, pos=0.22, key_extra=''):
    key = ('pl', m, round(dur, 3), bright, decay, nh, pos, key_extra)
    if key not in _cache:
        n = N(dur)
        f = f_(m)
        t = np.arange(n) / SR
        y = np.zeros(n)
        for k in range(1, nh + 1):
            fk = f * k * (1 + 0.0003 * k * k)
            if fk > SR * 0.45: break
            amp = abs(np.sin(np.pi * k * pos)) / k ** (1.0 + 0.6 / bright)
            tau = decay / (1 + 0.08 * k * k / bright)
            y += amp * np.sin(2 * np.pi * fk * t + R.random() * 6) * np.exp(-t / tau)
        L = N(0.004)
        y[:L] += lp(R.standard_normal(L), 4000) * 0.2 * bright
        y = fade(y, 0.0008, min(0.05, dur * 0.3))
        _cache[key] = y * 0.5
    return _cache[key] * vel


def harp(m, dur=2.5, vel=1.0):
    return pluck(m, dur, vel, bright=0.7, decay=1.8, nh=14, pos=0.5)


def lute(m, dur=1.5, vel=1.0):
    return pluck(m, dur, vel, bright=1.4, decay=1.0, nh=28, pos=0.15)


def bellv(m, dur=3.0, vel=1.0):
    key = ('bell', m, dur)
    if key not in _cache:
        n = N(dur)
        f = f_(m)
        y = np.zeros(n)
        for r_, a_, tau in [(1, 1, 2.0), (2.0, .4, 1.2), (2.76, .35, .8), (5.4, .2, .4), (8.93, .12, .25), (0.5, .3, 2.5)]:
            y += a_ * sine(f * r_, n, ph0=R.random()) * expdecay(n, tau)
        _cache[key] = fade(y, 0.001, 0.2) * 0.25
    return _cache[key] * vel


def brass(m, dur, vel=1.0, rel=0.25):
    key = ('br', m, round(dur, 3))
    if key not in _cache:
        n = N(dur + rel)
        f = f_(m)
        y = sum(saw(f * (1 + d), n, ph0=R.random()) for d in (-0.004, 0.0, 0.005))
        y = sweep_filter(y, 400 + f, 2600 + f * 2, 'low', blocks=16, curve='exp')
        y = soft_clip(y * 0.8, 1.5)
        y *= adsr(n, 0.04, 0.15, 0.75, rel, hold=max(dur - 0.19, 0))
        _cache[key] = y * 0.28
    return _cache[key] * vel


def guitar(ms, dur, vel=1.0, mute=True, drive=10.0):
    key = ('gt', tuple(ms), round(dur, 3), mute)
    if key not in _cache:
        y = sum(pluck(m, dur + 0.05, 1.0, bright=2.2, decay=(0.12 if mute else 1.2), nh=30, pos=0.12, key_extra='g') for m in ms)
        y = soft_clip(y * drive, 1.0)
        y = hp(y, 90)
        y = lp(peak(y, 1600, 1.2) * 0.4 + y * 0.6, 4200, order=4)
        y *= adsr(len(y), 0.002, 0.05, 0.9, 0.04)
        _cache[key] = y * 0.35
    return _cache[key] * vel


def bass(m, dur, vel=1.0):
    key = ('bs', m, round(dur, 3))
    if key not in _cache:
        n = N(dur + 0.08)
        f = f_(m)
        y = lp(saw(f, n), 500) * 0.6 + sine(f, n) * 0.8
        y = soft_clip(y * 1.5)
        y *= adsr(n, 0.004, 0.1, 0.7, 0.07, hold=max(dur - 0.1, 0))
        _cache[key] = y * 0.45
    return _cache[key] * vel


def drone(m, dur, vel=1.0):
    n = N(dur)
    f = f_(m)
    y = sine(f, n) + 0.3 * sine(2 * f * 1.001, n) + 0.15 * lp(saw(f, n), 300)
    return y * adsr(n, 2.0, 0.5, 0.9, 2.0) * vel * 0.3


# ---------------- drums ----------------
def _drum(key, fn):
    if key not in _cache:
        _cache[key] = fn()
    return _cache[key]


def kick(vel=1.0):
    def mk():
        n = N(0.5)
        f = 45 + 90 * np.exp(-np.arange(n) / (0.025 * SR))
        y = sine(f, n) * expdecay(n, 0.16)
        y[:N(0.004)] += lp(R.standard_normal(N(0.004)), 5000) * 0.5
        return fade(soft_clip(y * 1.4), 0.0005, 0.05) * 0.9
    return _drum('kick', mk) * vel


def taiko(vel=1.0, big=False):
    def mk():
        n = N(1.6 if big else 1.0)
        f0 = 62 if big else 85
        f = f0 + f0 * 0.9 * np.exp(-np.arange(n) / (0.03 * SR))
        y = sine(f, n) * expdecay(n, 0.45 if big else 0.28)
        skin = lp(R.standard_normal(n), 700) * expdecay(n, 0.06) * 0.6
        slap = bp(R.standard_normal(N(0.02)), 1000, 4000) * expdecay(N(0.02), 0.004) * 0.3
        y = y + skin
        y[:len(slap)] += slap
        return fade(soft_clip(y * 1.3), 0.0005, 0.2) * 0.9
    return _drum(('taiko', big), mk) * vel


def tom(m, vel=1.0):
    def mk():
        n = N(0.5)
        f0 = f_(m)
        f = f0 + f0 * 0.6 * np.exp(-np.arange(n) / (0.02 * SR))
        y = sine(f, n) * expdecay(n, 0.18) + lp(R.standard_normal(n), 1500) * expdecay(n, 0.04) * 0.4
        return fade(y, 0.0005, 0.08) * 0.6
    return _drum(('tom', m), mk) * vel


def snare(vel=1.0):
    def mk():
        n = N(0.35)
        y = bp(R.standard_normal(n), 1200, 9000) * expdecay(n, 0.09) * 0.7
        y += sine(190 + 60 * np.exp(-np.arange(n) / (0.01 * SR)), n) * expdecay(n, 0.05) * 0.6
        return fade(soft_clip(y * 1.4), 0.0005, 0.05) * 0.55
    return _drum('snare', mk) * vel


def hat(vel=1.0, open_=False):
    def mk():
        n = N(0.3 if open_ else 0.06)
        y = hp(R.standard_normal(n), 7000) * expdecay(n, 0.12 if open_ else 0.018)
        return fade(y, 0.0005, 0.02) * 0.25
    return _drum(('hat', open_), mk) * vel


def shaker(vel=1.0):
    def mk():
        n = N(0.09)
        y = bp(R.standard_normal(n), 4500, 11000) * adsr(n, 0.012, 0.02, 0.4, 0.05)
        return y * 0.2
    return _drum('shaker', mk) * vel


def doum(vel=1.0):
    def mk():
        n = N(0.5)
        f = 80 + 50 * np.exp(-np.arange(n) / (0.015 * SR))
        y = sine(f, n) * expdecay(n, 0.2) + lp(R.standard_normal(n), 800) * expdecay(n, 0.03) * 0.5
        return fade(y, 0.0005, 0.1) * 0.75
    return _drum('doum', mk) * vel


def tek(vel=1.0):
    def mk():
        n = N(0.12)
        y = bp(R.standard_normal(n), 1800, 7000) * expdecay(n, 0.025) + sine(620, n) * expdecay(n, 0.02) * 0.4
        return fade(y, 0.0005, 0.03) * 0.4
    return _drum('tek', mk) * vel


def crash(vel=1.0):
    def mk():
        n = N(2.5)
        y = hp(R.standard_normal(n), 3500) * expdecay(n, 0.7) * 0.5
        for k in range(10):
            y += sine(R.uniform(3000, 9000), n, ph0=R.random()) * expdecay(n, R.uniform(0.3, 1.0)) * 0.04
        y[:N(0.01)] *= np.linspace(0.3, 1, N(0.01))
        return fade(y, 0.0005, 0.5) * 0.35
    return _drum('crash', mk) * vel


def timpani(vel=1.0, m=38):
    def mk():
        n = N(2.0)
        f = f_(m)
        y = sine(f, n) * expdecay(n, 0.9) + 0.5 * sine(f * 1.5, n) * expdecay(n, 0.5) + 0.3 * sine(f * 1.98, n) * expdecay(n, 0.4)
        y += lp(R.standard_normal(n), 600) * expdecay(n, 0.04) * 0.5
        return fade(y, 0.0005, 0.3) * 0.7
    return _drum(('timp', m), mk) * vel


def boom(vel=1.0):
    def mk():
        n = N(3.0)
        f = 30 + 40 * np.exp(-np.arange(n) / (0.08 * SR))
        y = sine(f, n) * expdecay(n, 0.9) + lp(R.standard_normal(n), 150) * expdecay(n, 0.5) * 0.6
        return fade(soft_clip(y * 1.5), 0.001, 0.5) * 0.9
    return _drum('boom', mk) * vel


# ======================= song container =======================
class Song:
    def __init__(self, bpm, bars, bpb=4, tail=7.0, loop=True):
        self.beat = 60.0 / bpm
        self.bar = self.beat * bpb
        self.bars = bars
        self.L = N(bars * self.bar) if loop else None
        self.loop = loop
        self.n = N(bars * self.bar + tail)
        self.buses = {}

    def T(self, bar, beat=0.0):
        return bar * self.bar + beat * self.beat

    def add(self, bus, x, t, p=0.0, g=1.0, human=0.0):
        if human:
            t += R.uniform(-human, human)
        st = max(int(t * SR), 0)
        if st >= self.n: return
        if x.ndim == 1:
            x = pan(x, p)
        b = self.buses.setdefault(bus, np.zeros((self.n, 2)))
        e = min(st + len(x), self.n)
        b[st:e] += x[:e - st] * g

    def render(self, mixcfg, irs, path, rms_db=-17.0, q=3, fade_end=0.0, low_db=0.0, high_db=0.0, hpf=28):
        """mixcfg: {bus: (gain, {ir_name: send})}"""
        dry = np.zeros((self.n, 2))
        sends = {k: np.zeros((self.n, 2)) for k in irs}
        for name, buf in self.buses.items():
            g, snd = mixcfg.get(name, (1.0, {}))
            dry += buf * g
            for k, s in snd.items():
                sends[k] += buf * g * s
        out = np.zeros((self.n + max(len(i) for i in irs.values()), 2))
        out[:self.n] += dry
        for k, ir in irs.items():
            if np.abs(sends[k]).max() == 0: continue
            w = reverb(sends[k], ir, wet=1.0, dry=0.0)
            out[:len(w)] += w
        out = hp(out, hpf)  # filter before wrapping so the loop seam stays continuous
        if low_db:   # low shelf (~150 Hz)
            out = out + (10 ** (low_db / 20) - 1) * lp(out, 150)
        if high_db:  # high shelf (~2.5 kHz)
            out = out + (10 ** (high_db / 20) - 1) * hp(out, 2500)
        if self.loop:
            L = self.L
            rest = out[L:]
            k = 0
            while k < len(rest):  # wrap tail(s) onto start
                seg = rest[k:k + L]
                out[:len(seg)] += seg
                k += L
            out = out[:L]
        else:
            out = trim(out, -70, pad=0.05)
            if fade_end:
                m = N(fade_end)
                out[-m:] *= np.linspace(1, 0, m)[:, None] ** 2
        # loudness: normalize rms then peak-limit
        rms = np.sqrt(np.mean(out ** 2))
        out *= 10 ** (rms_db / 20) / max(rms, 1e-9)
        out = soft_clip(out * 0.9, 1.1) / 0.9 if np.abs(out).max() > 0.9 else out
        ceil = 10 ** (-1.0 / 20)
        w = N(0.006)
        env = maximum_filter1d(np.abs(out).max(axis=1), size=4 * w + 1)
        env = uniform_filter1d(env, size=2 * w + 1)
        g = np.minimum(1.0, ceil / np.maximum(env, 1e-9))
        out = np.clip(out * g[:, None], -ceil, ceil)
        write_ogg(path, out, q=q)
        print(f'{os.path.basename(path):16s} {len(out) / SR:6.2f}s  {os.path.getsize(path) / 1024:.0f} KB')


def triad(root, minor=True, inv=0):
    t = [root, root + (3 if minor else 4), root + 7]
    for _ in range(inv):
        t = t[1:] + [t[0] + 12]
    return t


def voice_near(chord_pcs, center):
    """chord pitch classes -> 3-4 notes closest above/below center"""
    out = []
    for pc in chord_pcs:
        m = center - ((center - pc) % 12)
        if center - m > 6: m += 12
        out.append(m)
    return sorted(out)


IR_HALL = make_ir(3.6, 1.4, seed=11, damp=6500)
IR_CHAMBER = make_ir(2.4, 0.8, seed=12, damp=7000)
IR_ROOM = make_ir(1.2, 0.4, seed=13, damp=8000)

# chord helpers: name -> (bass midi, pitch classes)
PC = {'C': 0, 'Db': 1, 'D': 2, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7, 'Ab': 8, 'A': 9, 'Bb': 10, 'B': 11}


def chord(name):
    q = 'm' if name.endswith('m') and not name.endswith('dim') else ''
    if name.endswith('dim'):
        r = PC[name[:-3]]; ints = [0, 3, 6]
    elif name.endswith('maj7'):
        r = PC[name[:-4]]; ints = [0, 4, 7, 11]
    elif name.endswith('m7'):
        r = PC[name[:-2]]; ints = [0, 3, 7, 10]
    elif q:
        r = PC[name[:-1]]; ints = [0, 3, 7]
    else:
        r = PC[name]; ints = [0, 4, 7]
    return r, [(r + i) % 12 for i in ints]


def bass_note(r, lo=31):
    m = 24 + r
    while m < lo: m += 12
    return m


# ======================= TITLE =======================
def title():
    s = Song(66, 24)
    prog = ['Dm', 'Dm', 'Bb', 'Bb', 'Gm', 'Gm', 'A', 'A',
            'Dm', 'Bb', 'Gm', 'A', 'Dm', 'F', 'C', 'A',
            'Bb', 'F', 'Gm', 'Dm', 'Bb', 'C', 'A', 'A']
    for b, c in enumerate(prog):
        r, pcs = chord(c)
        bn = bass_note(r, 33)
        L = s.bar
        s.add('low', strings(bn, L, 0.9, bright=0.6, attack=0.6, rel=1.0), s.T(b), -0.1)
        s.add('low', strings(bn + 7, L, 0.5, bright=0.6, attack=0.6, rel=1.0), s.T(b), 0.2)
        s.add('low', strings(bn + 12, L, 0.4, bright=0.7, attack=0.8, rel=1.0), s.T(b), -0.3)
        vow = 'a' if b < 8 else 'o'
        for i, m in enumerate(voice_near(pcs, 62)):
            s.add('choir', choir(m, L, vow, 0.8, attack=0.9, rel=1.2), s.T(b), [-0.5, 0.0, 0.5, 0.2][i % 4])
        if b % 2 == 0:
            s.add('bell', bellv(74 if b % 4 == 0 else 69, 4.0, 0.5), s.T(b), 0.3)
        s.add('drone', drone(26, L + 2.0, 0.7), s.T(b))
        if b >= 8:
            s.add('drums', taiko(0.8, big=True), s.T(b), 0.0)
            if b >= 16:
                s.add('drums', taiko(0.45), s.T(b, 2.5), -0.2)
                s.add('drums', taiko(0.55), s.T(b, 3.0), 0.2)
    # rolls into sections
    for rb in (7, 15, 23):
        for k in range(8):
            s.add('drums', taiko(0.15 + 0.08 * k), s.T(rb, 2 + k * 0.25), (-1) ** k * 0.2)
    # cello melody (B)
    mel = [(8, 0, 50, 2), (8, 2, 53, 1), (8, 3, 57, 1), (9, 0, 58, 3), (9, 3, 57, 1),
           (10, 0, 55, 2), (10, 2, 53, 1), (10, 3, 50, 1), (11, 0, 52, 2), (11, 2, 49, 2),
           (12, 0, 50, 1.5), (12, 1.5, 52, 0.5), (12, 2, 53, 2), (13, 0, 57, 2), (13, 2, 60, 2),
           (14, 0, 55, 2), (14, 2, 60, 1), (14, 3, 58, 1), (15, 0, 57, 4)]
    for b, bt, m, d in mel:
        s.add('cello', cello(m, d * s.beat, 0.9, attack=0.15, rel=0.6), s.T(b, bt), 0.1)
    # soprano choir melody (C) + harp arps
    sop = [(16, 0, 74, 2), (16, 2, 77, 2), (17, 0, 72, 3), (17, 3, 69, 1), (18, 0, 70, 2), (18, 2, 74, 2),
           (19, 0, 69, 4), (20, 0, 77, 2), (20, 2, 74, 2), (21, 0, 76, 2), (21, 2, 79, 2),
           (22, 0, 73, 2), (22, 2, 76, 2), (23, 0, 69, 4)]
    for b, bt, m, d in sop:
        s.add('sop', choir(m, d * s.beat, 'a', 0.9, attack=0.25, rel=0.9, voices=3), s.T(b, bt), -0.15)
        s.add('cello', cello(m - 24, d * s.beat, 0.5), s.T(b, bt), 0.2)
    for b in range(16, 24):
        r, pcs = chord(prog[b])
        notes = voice_near(pcs, 67) + [voice_near(pcs, 67)[0] + 12]
        seq = notes + notes[::-1][1:3]
        for k in range(8):
            m = seq[k % len(seq)]
            s.add('harp', harp(m, 2.5, 0.5 + 0.1 * (k % 2 == 0)), s.T(b, k * 0.5), 0.4 - 0.1 * (k % 4), human=0.01)
    s.render({'low': (0.9, {'hall': 0.35}), 'choir': (0.8, {'hall': 0.6}), 'bell': (0.7, {'hall': 0.6}),
              'drone': (0.6, {}), 'drums': (1.0, {'hall': 0.45}), 'cello': (0.9, {'hall': 0.4}),
              'sop': (0.6, {'hall': 0.6}), 'harp': (0.5, {'hall': 0.5})},
             {'hall': IR_HALL}, os.path.join(OUT, 'title.ogg'), rms_db=-19.0, low_db=-4, high_db=9)


# ======================= SANCTUM =======================
def sanctum():
    s = Song(84, 32)
    phrase = ['Dm7', 'G', 'Fmaj7', 'C', 'Dm7', 'G', 'Am7', 'Am7']
    prog = phrase * 4
    mel = [(0, 0, 81, 1.5), (0, 1.5, 79, .5), (0, 2, 77, 1), (0, 3, 76, 1),
           (1, 0, 74, 1.5), (1, 1.5, 76, .5), (1, 2, 71, 2),
           (2, 0, 72, 1), (2, 1, 76, 1), (2, 2, 81, 2),
           (3, 0, 79, 3), (3, 3, 76, 1),
           (4, 0, 77, 1.5), (4, 1.5, 76, .5), (4, 2, 74, 1), (4, 3, 69, 1),
           (5, 0, 71, 1), (5, 1, 74, 1), (5, 2, 79, 2),
           (6, 0, 76, 2), (6, 2, 72, 1), (6, 3, 74, 1),
           (7, 0, 76, 4)]
    for b, c in enumerate(prog):
        r, pcs = chord(c)
        bn = bass_note(r, 38)
        ph = b // 8
        # lute fingerpicking
        tones = sorted(voice_near(pcs[:3], 57))
        pat = [bn, tones[0] + 12 if tones[0] < 52 else tones[0], tones[1], tones[2], tones[0] + 12, tones[2], tones[1], tones[2]]
        for k, m in enumerate(pat):
            v = 0.85 if k == 0 else 0.5 + 0.12 * (k % 2 == 0)
            s.add('lute', lute(m, 1.4, v * R.uniform(0.9, 1.05)), s.T(b, k * 0.5), -0.25 + 0.05 * (k % 3), human=0.008)
        # strings pad
        for i, m in enumerate(voice_near(pcs, 60)):
            s.add('pad', strings(m, s.bar, 0.55, bright=0.4, attack=0.9, rel=1.2), s.T(b), [-0.4, 0.1, 0.4, -0.1][i % 4])
        s.add('pad', strings(bn - 12 if bn - 12 >= 28 else bn, s.bar, 0.6, bright=0.3, attack=0.6, rel=1.0), s.T(b), 0.0)
        # harp rolls every 2 bars in phrases 2 and 3
        if ph in (1, 2) and b % 2 == 0:
            ns = voice_near(pcs, 72) + [voice_near(pcs, 72)[0] + 12]
            for k, m in enumerate(ns):
                s.add('harp', harp(m, 3.0, 0.45), s.T(b, 0.0 + k * 0.18), 0.45)
        # hand drum heartbeat
        if ph in (1, 3):
            s.add('perc', doum(0.4), s.T(b, 0), 0.0, human=0.005)
            s.add('perc', doum(0.25), s.T(b, 2.5), 0.0, human=0.005)
            for k in range(8):
                s.add('perc', shaker(0.35 if k % 2 else 0.2), s.T(b, k * 0.5), 0.3, human=0.006)
    for ph in (1, 3):
        for b, bt, m, d in mel:
            mm = m if ph == 1 else m - 12 if bt == 0 and b in (2, 3) else m
            s.add('flute', flute(mm, d * s.beat * 0.97, 0.75), s.T(ph * 8 + b, bt), 0.2, human=0.006)
    # counter-melody on strings in phrase 3
    for b, bt, m, d in mel[::2]:
        s.add('pad', cello(m - 24, d * s.beat * 1.8, 0.4), s.T(16 + b, bt), -0.2)
    s.render({'lute': (0.8, {'room': 0.4}), 'pad': (0.55, {'room': 0.5}), 'harp': (0.6, {'room': 0.6}),
              'perc': (0.7, {'room': 0.35}), 'flute': (0.7, {'room': 0.5})},
             {'room': IR_CHAMBER}, os.path.join(OUT, 'sanctum.ogg'), rms_db=-20.0, low_db=-2, high_db=8)


# ======================= CATACOMBS (combat) =======================
def catacombs():
    s = Song(140, 56)
    cyc = ['Em', 'Em', 'C', 'B', 'Am', 'Em', 'F', 'B']
    prog = cyc * 7
    st = s.beat / 4  # 16th
    gt_mask = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1]
    for b, c in enumerate(prog):
        r, pcs = chord(c)
        bn = bass_note(r, 33)
        sec = 0 if b < 8 else 1 if b < 24 else 2 if b < 40 else 3 if b < 48 else 4
        breakdown = sec == 3
        # ---- drums ----
        if not breakdown:
            for k in (0, 6, 8, 11):
                s.add('drums', kick(0.95 if k in (0, 8) else 0.75), s.T(b, k / 4))
            if sec >= 2 or (sec == 1 and b % 2 == 1):
                s.add('drums', snare(0.85), s.T(b, 1), 0.05)
                s.add('drums', snare(0.9), s.T(b, 3), 0.05)
            for k in range(16):
                s.add('drums', hat(0.9 if k % 4 == 2 else 0.5 if k % 2 == 0 else 0.3), s.T(b, k / 4), 0.3, human=0.003)
            for k, tm in [(2, 50), (7, 45), (13, 43), (14, 43)]:
                s.add('drums', tom(tm, 0.55), s.T(b, k / 4), -0.3 if tm > 45 else 0.3)
            for k in (0, 6, 10):
                s.add('perc', doum(0.7), s.T(b, k / 4), -0.1)
            for k in (3, 4, 9, 12, 15):
                s.add('perc', tek(0.6), s.T(b, k / 4), 0.35, human=0.003)
        else:
            s.add('drums', taiko(1.0, big=True), s.T(b, 0))
            s.add('drums', taiko(0.7), s.T(b, 1.5), -0.2)
            s.add('drums', taiko(0.8), s.T(b, 2.0), 0.2)
            for k in range(8):
                s.add('perc', shaker(0.6), s.T(b, k / 2), 0.4)
        if b % 8 == 0 and b in (8, 24, 48):
            s.add('drums', crash(0.9), s.T(b), 0.2)
        if b in (23, 39, 55):  # snare roll fills
            for k in range(8, 16):
                s.add('drums', snare(0.3 + 0.07 * (k - 8)), s.T(b, k / 4), 0.0)
        # ---- bass ----
        if not breakdown:
            for k in range(8):
                m = bn + (12 if k in (3, 7) else 0)
                s.add('bass', bass(m, s.beat * 0.45, 0.9), s.T(b, k / 2))
        else:
            s.add('bass', bass(bn, s.bar * 0.95, 0.8), s.T(b))
        # ---- string ostinato ----
        tones = voice_near(pcs[:3], 64)
        pat = [tones[0] + 12, tones[2], tones[1] + 12, tones[2]] if sec != 0 else [tones[0], tones[2], tones[1], tones[2]]
        for k in range(16 if sec >= 1 else 8):
            stepdur = st if sec >= 1 else st * 2
            m = pat[k % 4]
            s.add('str', stacc(m, stepdur * 0.8, 0.9 if k % 4 == 0 else 0.6, bright=0.9), s.T(b) + k * stepdur, -0.35 + 0.15 * (k % 2))
        # ---- guitars ----
        if sec in (1, 2, 4):
            pc = [bn, bn + 7, bn + 12]
            for k in range(16):
                if gt_mask[k]:
                    alt = pc
                    if c in ('Em', 'Am') and k in (13, 15):
                        alt = [bn + 1, bn + 8, bn + 13]  # b2 phrygian push
                    accent = k in (0, 6, 10)
                    g = guitar(alt, st * (2.5 if accent else 0.9), 0.9 if accent else 0.65, mute=not accent)
                    s.add('gtrL', g, s.T(b, k / 4), -0.7, human=0.002)
                    s.add('gtrR', g, s.T(b, k / 4) + 0.012, 0.7)
        # ---- choir pad in breakdown & final ----
        if sec in (3, 4):
            for i, m in enumerate(voice_near(pcs, 60)):
                s.add('choir', choir(m, s.bar, 'o', 0.7, attack=0.3, rel=0.6), s.T(b), [-0.4, 0.4, 0.0][i % 3])
    # ---- lead melody (distorted plucked lead) ----
    mel = [(0, 0, 76, 1), (0, 1, 75, .5), (0, 1.5, 76, .5), (0, 2, 71, 1), (0, 3, 67, 1),
           (1, 0, 66, 1), (1, 1, 67, 1), (1, 2, 69, 1), (1, 3, 71, 1),
           (2, 0, 72, 1.5), (2, 1.5, 71, .5), (2, 2, 69, 1), (2, 3, 67, 1),
           (3, 0, 66, 1), (3, 1, 63, 1), (3, 2, 59, 2),
           (4, 0, 69, 1), (4, 1, 72, 1), (4, 2, 76, 1), (4, 3, 74, .5), (4, 3.5, 72, .5),
           (5, 0, 71, 2), (5, 2, 67, 1), (5, 3, 64, 1),
           (6, 0, 65, 1), (6, 1, 69, 1), (6, 2, 72, 1), (6, 3, 71, 1),
           (7, 0, 75, 2), (7, 2, 71, 1), (7, 3, 78, 1)]
    for start in (24, 32, 48):
        up = 12 if start == 32 else 0
        for b, bt, m, d in mel:
            T0 = s.T(start + b, bt)
            dur = d * s.beat
            if d >= 1.5:  # tremolo picking on long notes
                k = 0
                while k * st < dur - 1e-6:
                    s.add('lead', guitar([m + up - 12], st * 1.1, 0.75 if k else 0.95, mute=False, drive=6.0), T0 + k * st, 0.1)
                    k += 1
            else:
                s.add('lead', guitar([m + up - 12], dur * 0.95, 0.95, mute=False, drive=6.0), T0, 0.1)
            if start == 48:
                s.add('str', strings(m, dur, 0.5, bright=1.2, attack=0.03, rel=0.2), T0, -0.1)
    s.render({'drums': (1.0, {'room': 0.12}), 'perc': (0.7, {'room': 0.2}), 'bass': (0.8, {}),
              'str': (0.6, {'room': 0.3}), 'gtrL': (0.45, {'room': 0.08}), 'gtrR': (0.45, {'room': 0.08}),
              'choir': (0.6, {'room': 0.5}), 'lead': (0.5, {'room': 0.25})},
             {'room': IR_ROOM}, os.path.join(OUT, 'catacombs.ogg'), rms_db=-16.5, low_db=-3, high_db=2, hpf=40)


# ======================= BOSS =======================
def boss():
    s = Song(152, 56)
    cyc = ['Cm', 'Cm', 'Ab', 'Ab', 'Db', 'Db', 'G', 'G']
    prog = cyc * 7
    st = s.beat / 4
    gt_mask = [1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1]
    vowels = ['a', 'o', 'a', 'e', 'o', 'a', 'u', 'o']
    for b, c in enumerate(prog):
        r, pcs = chord(c)
        bn = bass_note(r, 31)
        sec = 0 if b < 8 else 1 if b < 24 else 2 if b < 40 else 3 if b < 48 else 4
        half = sec == 3
        # war drums
        if not half:
            for k in (0, 3, 6, 8, 11, 14):
                s.add('drums', taiko(1.0 if k in (0, 8) else 0.75, big=k == 0), s.T(b, k / 4), 0.0)
            for k in (0, 2, 3, 8, 10, 11):
                s.add('drums', kick(0.9), s.T(b, k / 4))
            if sec >= 1:
                s.add('drums', snare(1.0), s.T(b, 1))
                s.add('drums', snare(1.0), s.T(b, 3))
                for k in range(8):
                    s.add('drums', hat(0.6 if k % 2 else 0.35, open_=k == 7), s.T(b, k / 2), 0.3)
            for k, tm in [(13, 47), (15, 43)]:
                s.add('drums', tom(tm, 0.7), s.T(b, k / 4), 0.25)
        else:
            s.add('drums', taiko(1.0, big=True), s.T(b, 0))
            s.add('drums', boom(0.7), s.T(b, 0))
            s.add('drums', taiko(1.0, big=True), s.T(b, 2))
            for k in range(4):
                s.add('drums', tom(43 + k * 2, 0.4 + 0.1 * k), s.T(b, 3 + k / 4), 0.2)
        if b in (8, 24, 40, 48):
            s.add('drums', crash(1.0), s.T(b), 0.0)
            s.add('drums', boom(1.0), s.T(b), 0.0)
        if b in (23, 39, 55):
            for k in range(16):
                s.add('drums', snare(0.25 + 0.045 * k), s.T(b, k / 4))
        # bass
        if not half:
            for k in range(16):
                if gt_mask[k]:
                    s.add('bass', bass(bn, st * 0.9, 0.85), s.T(b, k / 4))
        else:
            s.add('bass', bass(bn, s.bar * 0.95, 0.9), s.T(b))
        # tremolo strings
        top = voice_near(pcs, 70)
        for k in range(16):
            for i, m in enumerate(top[:2]):
                s.add('str', stacc(m, st * 0.9, 0.55 if k % 4 else 0.8, bright=1.2), s.T(b, k / 4), -0.4 if i == 0 else 0.4)
        s.add('low', strings(bn + 12, s.bar, 0.8, bright=0.8, attack=0.2, rel=0.6), s.T(b), 0.0)
        # choir chant
        cv = voice_near(pcs, 62)
        if sec in (0, 3):
            for i, m in enumerate(cv):
                s.add('choir', choir(m, s.bar, 'o', 0.9, attack=0.2, rel=0.6), s.T(b), [-0.4, 0, 0.4, 0.2][i % 4])
        else:
            for k, (bt, d) in enumerate([(0, .75), (1, .5), (1.5, .5), (2, .75), (3, .5), (3.5, .5)]):
                v = vowels[(b * 6 + k) % len(vowels)]
                for i, m in enumerate(cv):
                    s.add('choir', chant(m, d * s.beat * 0.85, v, 0.9 if k in (0, 3) else 0.7), s.T(b, bt), [-0.4, 0, 0.4, 0.2][i % 4])
        # guitars
        if sec in (1, 2, 4):
            pc = [bn, bn + 7, bn + 12]
            for k in range(16):
                if gt_mask[k]:
                    accent = k in (0, 8)
                    g = guitar(pc, st * (3 if accent else 0.9), 0.9 if accent else 0.7, mute=not accent, drive=14)
                    s.add('gtrL', g, s.T(b, k / 4), -0.75, human=0.002)
                    s.add('gtrR', g, s.T(b, k / 4) + 0.011, 0.75)
        # brass stabs
        if sec in (1, 4) and b % 2 == 0:
            for bt in (0, 2.5):
                for m in voice_near(pcs, 58):
                    s.add('brass', brass(m, s.beat * 0.4, 0.9), s.T(b, bt), 0.0)
    # lead melody: brass + soprano
    mel = [(0, 0, 67, 2), (0, 2, 72, 1), (0, 3, 75, 1), (1, 0, 74, 1.5), (1, 1.5, 72, .5), (1, 2, 71, 1), (1, 3, 72, 1),
           (2, 0, 68, 2), (2, 2, 72, 1), (2, 3, 75, 1), (3, 0, 77, 2), (3, 2, 75, 1), (3, 3, 72, 1),
           (4, 0, 73, 2), (4, 2, 77, 1), (4, 3, 80, 1), (5, 0, 77, 2), (5, 2, 73, 1), (5, 3, 72, 1),
           (6, 0, 71, 2), (6, 2, 74, 1), (6, 3, 77, 1), (7, 0, 79, 2), (7, 2, 77, .5), (7, 2.5, 75, .5), (7, 3, 74, 1)]
    for start in (24, 32, 48):
        for b, bt, m, d in mel:
            T0 = s.T(start + b, bt)
            dur = d * s.beat * 0.95
            s.add('brass', brass(m - 12, dur, 0.85), T0, -0.1)
            s.add('brass', brass(m - 24, dur, 0.5), T0, 0.1)
            if start >= 32:
                s.add('sop', choir(m, dur, 'a', 0.9, attack=0.08, rel=0.4, voices=4), T0, 0.15)
    s.render({'drums': (0.85, {'hall': 0.18}), 'bass': (0.6, {}), 'str': (0.45, {'hall': 0.3}),
              'low': (0.6, {'hall': 0.3}), 'choir': (1.0, {'hall': 0.45}), 'gtrL': (0.5, {'hall': 0.06}),
              'gtrR': (0.5, {'hall': 0.06}), 'brass': (0.85, {'hall': 0.35}), 'sop': (0.75, {'hall': 0.5})},
             {'hall': make_ir(2.6, 0.9, seed=21, damp=6000)}, os.path.join(OUT, 'boss.ogg'), rms_db=-15.5, low_db=-5, high_db=4, hpf=35)


# ======================= STINGS =======================
def victory():
    s = Song(100, 4, tail=6.0, loop=False)
    # timpani roll crescendo then hit
    for k in range(12):
        s.add('perc', timpani(0.2 + 0.05 * k, 38), s.T(0, k * 0.125), (-1) ** k * 0.15)
    s.add('perc', timpani(1.0, 38), s.T(0, 1.5))
    s.add('perc', crash(0.9), s.T(0, 1.5))
    s.add('perc', boom(0.6), s.T(0, 1.5))
    # fanfare: pickup triplet then rising
    fan = [(0, 0.0, 62, 0.33), (0, 0.33, 66, 0.33), (0, 0.67, 69, 0.33), (0, 1.0, 74, 0.5),
           (0, 1.5, 74, 1.0), (0, 2.5, 76, 0.5), (0, 3.0, 78, 1.0), (1, 0.0, 81, 3.5)]
    for b, bt, m, d in fan:
        s.add('brass', brass(m - 12, d * s.beat, 1.0), s.T(b, bt), -0.1)
        s.add('brass', brass(m - 5 if m > 70 else m - 8, d * s.beat, 0.55), s.T(b, bt), 0.15)
    for m in (50, 57, 62, 66, 69, 74):
        s.add('choir', choir(m, s.bar * 1.0, 'a', 0.8, attack=0.4, rel=1.6), s.T(0, 1.5), 0.0)
        s.add('str', strings(m, s.bar * 1.2, 0.6, bright=1.0, attack=0.3, rel=1.8), s.T(0, 1.5), 0.0)
    for k, m in enumerate((74, 78, 81, 86)):
        s.add('bell', bellv(m, 4.0, 0.5), s.T(1, k * 0.25), 0.3)
    s.add('perc', timpani(0.9, 38), s.T(1, 0))
    s.add('perc', crash(0.7), s.T(1, 0))
    s.render({'perc': (1.0, {'hall': 0.3}), 'brass': (0.8, {'hall': 0.35}), 'choir': (0.6, {'hall': 0.6}),
              'str': (0.5, {'hall': 0.4}), 'bell': (0.6, {'hall': 0.5})},
             {'hall': IR_HALL}, os.path.join(OUT, 'victory.ogg'), rms_db=-16.0, fade_end=1.5, high_db=2)


def defeat():
    s = Song(60, 2, tail=5.0, loop=False)
    s.add('perc', boom(1.0), 0.0)
    s.add('perc', taiko(0.9, big=True), 0.0)
    line = [(0.0, 50, 1.2), (1.2, 48, 1.2), (2.4, 46, 1.2), (3.6, 45, 2.4)]
    for t0, m, d in line:
        s.add('cello', cello(m, d, 1.0, attack=0.15, rel=1.0), t0, 0.0)
    for t0, chs in [(0.0, [50, 53, 57]), (2.4, [46, 50, 53]), (3.6, [45, 49, 52])]:
        for m in chs:
            s.add('str', strings(m, 2.4 if t0 < 3 else 3.5, 0.5, bright=0.5, attack=0.4, rel=1.5), t0, 0.0)
    s.add('choir', choir(69, 1.6, 'o', 0.9, attack=0.5, rel=0.8, voices=2), 0.4, 0.2)
    s.add('choir', choir(65, 2.6, 'u', 0.8, attack=0.4, rel=1.6, voices=2), 2.0, 0.2)
    s.add('drone', drone(26, 7.0, 1.0), 0.0)
    s.add('perc', taiko(0.6, big=True), 3.6)
    s.render({'perc': (1.0, {'hall': 0.35}), 'cello': (0.9, {'hall': 0.4}), 'str': (0.5, {'hall': 0.5}),
              'choir': (0.6, {'hall': 0.6}), 'drone': (0.8, {})},
             {'hall': IR_HALL}, os.path.join(OUT, 'defeat.ogg'), rms_db=-19.0, fade_end=2.0, high_db=6)


TRACKS = {'title': title, 'sanctum': sanctum, 'catacombs': catacombs, 'boss': boss,
          'victory': victory, 'defeat': defeat}

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or list(TRACKS)
    for nme in names:
        _cache.clear()
        TRACKS[nme]()
