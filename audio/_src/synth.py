"""Tiny procedural synth toolkit for Veilborne audio (numpy/scipy only).
All original, generated from math. Used by gen_sfx.py and gen_music.py."""
import numpy as np
from scipy import signal
import subprocess, os, wave

SR = 44100
rng = np.random.default_rng(1234)


def t_arr(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def mtof(m):
    return 440.0 * 2 ** ((np.asarray(m, dtype=float) - 69) / 12.0)


# ---------------- oscillators ----------------
def phase_from_freq(freq, n, sr=SR):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.cumsum(f) / sr, f


def _polyblep(t, dt):
    out = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    out[m] = x + x - x * x - 1
    m2 = t > 1 - dt
    x = (t[m2] - 1) / dt[m2]
    out[m2] = x * x + x + x + 1
    return out


def saw(freq, n, sr=SR, ph0=0.0):
    ph, f = phase_from_freq(freq, n, sr)
    t = (ph + ph0) % 1.0
    dt = np.clip(f / sr, 1e-6, 0.5)
    return 2 * t - 1 - _polyblep(t, dt)


def square(freq, n, sr=SR, ph0=0.0):
    ph, f = phase_from_freq(freq, n, sr)
    dt = np.clip(f / sr, 1e-6, 0.5)
    t1 = (ph + ph0) % 1.0
    t2 = (t1 + 0.5) % 1.0
    return (np.where(t1 < 0.5, 1.0, -1.0) + _polyblep(t1, dt) - _polyblep(t2, dt))


def sine(freq, n, sr=SR, ph0=0.0):
    ph, _ = phase_from_freq(freq, n, sr)
    return np.sin(2 * np.pi * (ph + ph0))


def noise(n):
    return rng.standard_normal(n)


# ---------------- envelopes ----------------
def adsr(n, a, d, s, r, sr=SR, hold=None):
    """hold: seconds of sustain before release (default: fill)."""
    A, D, R = int(a * sr), int(d * sr), int(r * sr)
    A = max(A, 1); D = max(D, 1); R = max(R, 1)
    H = n - A - D - R if hold is None else int(hold * sr)
    H = max(H, 0)
    e = np.concatenate([
        np.linspace(0, 1, A, endpoint=False),
        np.linspace(1, s, D, endpoint=False),
        np.full(H, s),
        np.linspace(s, 0, R)])
    if len(e) < n:
        e = np.concatenate([e, np.zeros(n - len(e))])
    return e[:n]


def expdecay(n, tau, sr=SR):
    return np.exp(-np.arange(n) / (tau * sr))


def fade(x, fin=0.002, fout=0.01, sr=SR):
    x = x.copy()
    a = min(int(fin * sr), len(x)); b = min(int(fout * sr), len(x))
    if a > 0: x[:a] *= np.linspace(0, 1, a)
    if b > 0: x[-b:] *= np.linspace(1, 0, b)
    return x


# ---------------- filters ----------------
def lp(x, fc, order=2, sr=SR):
    fc = min(fc, sr * 0.45)
    sos = signal.butter(order, fc, 'low', fs=sr, output='sos')
    return signal.sosfilt(sos, x, axis=0)


def hp(x, fc, order=2, sr=SR):
    sos = signal.butter(order, fc, 'high', fs=sr, output='sos')
    return signal.sosfilt(sos, x, axis=0)


def bp(x, lo, hi, order=2, sr=SR):
    hi = min(hi, sr * 0.45)
    sos = signal.butter(order, [lo, hi], 'band', fs=sr, output='sos')
    return signal.sosfilt(sos, x, axis=0)


def peak(x, f, q, sr=SR):
    b, a = signal.iirpeak(f, q, fs=sr)
    return signal.lfilter(b, a, x, axis=0)


def sweep_filter(x, f_start, f_end, kind='low', q=0.9, blocks=64, sr=SR, curve='exp'):
    """Time-varying state-variable filter (block-wise coefficient update, sample loop free)."""
    n = len(x)
    out = np.zeros(n)
    edges = np.linspace(0, n, blocks + 1).astype(int)
    zi = None
    for i in range(blocks):
        a, b = edges[i], edges[i + 1]
        if b <= a: continue
        k = i / max(blocks - 1, 1)
        if curve == 'exp':
            f = f_start * (f_end / f_start) ** k
        else:
            f = f_start + (f_end - f_start) * k
        f = float(np.clip(f, 20, sr * 0.45))
        if kind == 'band':
            lo, hi = f / (1 + 1 / q), f * (1 + 1 / q)
            hi = min(hi, sr * 0.45)
            sos = signal.butter(2, [lo, hi], 'band', fs=sr, output='sos')
        else:
            sos = signal.butter(2, f, kind, fs=sr, output='sos')
        if zi is None or zi.shape[0] != sos.shape[0]:
            zi = np.zeros((sos.shape[0], 2))
        out[a:b], zi = signal.sosfilt(sos, x[a:b], zi=zi)
    return out


VOWELS = {  # formant freqs, bandwidth-ish q, gains
    'a': [(800, 6, 1.0), (1150, 8, 0.5), (2900, 12, 0.25), (3900, 14, 0.1)],
    'o': [(450, 6, 1.0), (800, 8, 0.45), (2830, 12, 0.15), (3800, 14, 0.08)],
    'u': [(325, 6, 1.0), (700, 8, 0.25), (2530, 12, 0.08), (3500, 14, 0.04)],
    'e': [(400, 6, 1.0), (1600, 9, 0.4), (2700, 12, 0.3), (3300, 14, 0.15)],
    'i': [(300, 6, 1.0), (2200, 10, 0.3), (3000, 12, 0.25), (3700, 14, 0.12)],
}


def formant(x, vowel='a', shift=1.0, sr=SR):
    out = np.zeros_like(x)
    for f, q, g in VOWELS[vowel]:
        out += g * peak(x, min(f * shift, sr * 0.45), q, sr)
    return out


# ---------------- effects ----------------
def make_ir(dur=2.5, decay=0.6, sr=SR, stereo=True, damp=6000, seed=7, predelay=0.012):
    r = np.random.default_rng(seed)
    n = int(dur * sr)
    t = np.arange(n) / sr
    env = np.exp(-t * 6.9 / (decay * 3.0))  # decay ~ RT60/3 scaling
    chans = []
    for c in range(2 if stereo else 1):
        nz = r.standard_normal(n)
        hi = hp(nz, 2500) * np.exp(-t * 6.9 / (decay * 1.2))
        lo = lp(nz, 2500) * env
        ir = lp(hi * 0.5 + lo, damp)
        ir = np.concatenate([np.zeros(int(predelay * sr)), ir])
        # few early reflections
        for k in range(6):
            d = int(r.uniform(0.008, 0.06) * sr)
            ir[d] += r.uniform(-0.6, 0.6)
        ir /= np.sqrt(np.sum(ir ** 2))
        chans.append(ir)
    return np.stack(chans, axis=1) if stereo else chans[0]


def reverb(x, ir, wet=0.3, dry=1.0):
    """x mono (n,) or stereo (n,2); ir stereo (m,2). Returns stereo length n+m-1."""
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    if ir.ndim == 1:
        ir = np.stack([ir, ir], axis=1)
    out = np.zeros((x.shape[0] + ir.shape[0] - 1, 2))
    for c in range(2):
        out[:, c] = signal.fftconvolve(x[:, c], ir[:, c])
    out *= wet
    out[:x.shape[0]] += x * dry
    return out


def reverb_mono(x, ir, wet=0.3):
    y = signal.fftconvolve(x, ir if ir.ndim == 1 else ir[:, 0]) * wet
    y[:len(x)] += x
    return y


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def pan(x, p):
    """p -1..1 equal-power pan, mono->stereo"""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def normalize(x, peak_db=-1.0):
    m = np.max(np.abs(x))
    if m < 1e-9: return x
    return x * (10 ** (peak_db / 20) / m)


def trim(x, thresh_db=-60, pad=0.01, sr=SR):
    a = np.abs(x if x.ndim == 1 else x.max(axis=1))
    th = 10 ** (thresh_db / 20) * a.max()
    idx = np.where(a > th)[0]
    if len(idx) == 0: return x
    s = max(idx[0] - int(0.001 * sr), 0)
    e = min(idx[-1] + int(pad * sr), len(x))
    return x[s:e]


def limiter(x, ceiling_db=-1.0, release=0.08, sr=SR):
    """Simple look-ahead-free peak limiter via smoothed gain envelope (block based)."""
    ceil = 10 ** (ceiling_db / 20)
    a = np.abs(x).max(axis=1) if x.ndim == 2 else np.abs(x)
    # running max over 5ms windows
    w = int(0.005 * sr)
    pad = np.pad(a, (w, w), mode='edge')
    from numpy.lib.stride_tricks import sliding_window_view
    mx = sliding_window_view(pad, 2 * w + 1).max(axis=1)[:len(a)]
    g = np.minimum(1.0, ceil / np.maximum(mx, 1e-9))
    # smooth release with one-pole filter (attack instant because of window)
    b, aa = signal.butter(1, 1.0 / (release * np.pi) , 'low', fs=sr)
    gs = signal.filtfilt(b, aa, g)
    gs = np.minimum(gs, g * 1.0 + (gs - g).clip(max=0))  # never exceed raw gain
    gs = np.minimum(gs, g)
    y = x * (gs[:, None] if x.ndim == 2 else gs)
    return np.clip(y, -ceil, ceil)


# ---------------- writers ----------------
def write_wav(path, x, sr=SR):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype('<i2')
    ch = 1 if x.ndim == 1 else x.shape[1]
    with wave.open(path, 'wb') as w:
        w.setnchannels(ch); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(data.tobytes())


def write_ogg(path, x, sr=SR, q=3):
    tmp = path + '.tmp.wav'
    write_wav(tmp, x, sr)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis',
                    '-q:a', str(q), path], check=True)
    os.remove(tmp)
