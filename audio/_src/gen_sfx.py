"""Procedurally synthesizes every Veilborne sfx + ui sound into audio/sfx/*.wav (mono, 44.1k, 16-bit).
Run:  python3 audio/_src/gen_sfx.py"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from synth import *

OUT = os.path.join(os.path.dirname(__file__), '..', 'sfx')
R = np.random.default_rng(42)
IR_ROOM = make_ir(1.2, 0.35, stereo=False, seed=3, damp=7000)
IR_HALL = make_ir(2.6, 0.9, stereo=False, seed=5, damp=5000)


def N(d):
    return int(d * SR)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, delay):
    return np.concatenate([np.zeros(N(delay)), x])


# ---------- building blocks ----------
def whoosh(dur, f0, f1, q=1.6, shape=None, bright=0.0):
    n = N(dur)
    x = R.standard_normal(n)
    y = sweep_filter(x, f0, f1, 'band', q=q, blocks=48)
    if shape is None:
        t = np.linspace(0, 1, n)
        shape = np.sin(np.pi * t ** 0.6) ** 2
    y = y * shape
    if bright:
        y += bright * hp(R.standard_normal(n), 6000) * shape ** 2
    return lp(y, 9000)


def thump(dur, f0, f1, tau=0.08, click=0.3):
    n = N(dur)
    f = f1 + (f0 - f1) * np.exp(-np.arange(n) / (0.03 * SR))
    y = sine(f, n) * expdecay(n, tau)
    c = lp(R.standard_normal(N(0.006)), 3000) * click
    y[:len(c)] += c
    return fade(y, 0.0005, dur * 0.3)


def crunch(dur, lo, hi, tau=0.03):
    n = N(dur)
    y = bp(R.standard_normal(n), lo, hi) * expdecay(n, tau)
    return fade(soft_clip(y * 3, 1.5), 0.0005, dur * 0.3)


def bell(freq, dur, tau=0.6, ratios=(1, 2.01, 2.76, 5.4, 8.93), amps=(1, .5, .35, .2, .1), bright_tau=None):
    n = N(dur)
    y = np.zeros(n)
    for r_, a_ in zip(ratios, amps):
        tt = tau / (1 + 0.6 * (r_ - 1)) if bright_tau is None else bright_tau
        y += a_ * sine(freq * r_, n, ph0=R.random()) * expdecay(n, tt)
    return fade(y, 0.001, 0.02)


def metal_ring(dur, base, tau=0.25, k=6):
    n = N(dur)
    y = np.zeros(n)
    for i in range(k):
        f = base * R.uniform(1, 4.5)
        y += sine(f, n, ph0=R.random()) * expdecay(n, tau * R.uniform(0.4, 1.0)) / (1 + i * 0.4)
    return y


def grunt(dur, f0_start, f0_end, vowel='a', shift=1.0, breath=0.25, rasp=0.0, env=None):
    n = N(dur)
    t = np.linspace(0, 1, n)
    f0 = f0_start * (f0_end / f0_start) ** t
    f0 = f0 * (1 + 0.012 * sine(5.5, n)) * (1 + 0.01 * lp(R.standard_normal(n), 30))
    src = saw(f0, n) * 0.6 + square(f0, n) * 0.2
    if rasp:
        src *= 1 + rasp * lp(R.standard_normal(n), 80) * 3
    src += breath * hp(R.standard_normal(n), 1500)
    y = formant(src, vowel, shift)
    if env is None:
        env = adsr(n, 0.015, dur * 0.3, 0.6, dur * 0.5)
    return lp(y * env, 6000)


def crackles(dur, rate=60, tau=0.003):
    n = N(dur)
    y = np.zeros(n)
    k = int(rate * dur)
    for _ in range(k):
        p = R.integers(0, max(n - 400, 1))
        L = N(R.uniform(0.002, 0.008))
        y[p:p + L] += R.uniform(-1, 1) * hp(R.standard_normal(L), 2000)[:len(y[p:p + L])] * np.exp(-np.arange(L) / (tau * SR))[:len(y[p:p + L])]
    return y


def chirp_sparkle(dur, f0, f1, count=10, tau=0.08):
    y = np.zeros(N(dur))
    for i in range(count):
        tpos = i / count * dur * 0.8
        f = f0 * (f1 / f0) ** (i / max(count - 1, 1))
        b = bell(f * R.uniform(0.98, 1.02), 0.4, tau=tau, amps=(1, .3, .2, .1, .05)) * R.uniform(0.5, 1)
        s = N(tpos)
        e = min(s + len(b), len(y))
        y[s:e] += b[:e - s]
    return y


def chord_pad(freqs, dur, vowel=None, attack=0.2, rel=0.5):
    n = N(dur)
    y = np.zeros(n)
    for f in freqs:
        for det in (-0.006, 0.0, 0.007):
            y += saw(f * (1 + det) * (1 + 0.004 * sine(5.0 + R.random(), n)), n, ph0=R.random())
    if vowel:
        y = formant(y, vowel)
    else:
        y = lp(y, 2500)
    return y * adsr(n, attack, 0.1, 0.9, rel)


def finish(name, x, peak_db=-1.0, verb=None, wet=0.0, hpf=30):
    if verb is not None and wet > 0:
        x = reverb_mono(x, verb, wet)
    x = hp(x, hpf)
    x = trim(x, -42, pad=0.005)
    x = fade(x, 0.0015, min(0.12, len(x) / SR * 0.25))
    x = normalize(x, peak_db)
    write_wav(os.path.join(OUT, name + '.wav'), x)
    print(f'{name:16s} {len(x) / SR:5.2f}s')


# ---------- gameplay sfx ----------
def gen_all():
    os.makedirs(OUT, exist_ok=True)

    # swing_spear: fast thrust whoosh + tiny metal tick
    w = whoosh(0.28, 3500, 700, q=1.4, bright=0.15)
    w2 = whoosh(0.22, 1200, 300, q=1.0) * 0.5
    tick = metal_ring(0.08, 2500, tau=0.02) * 0.08
    finish('swing_spear', mix(w, w2, tick), verb=IR_ROOM, wet=0.08)

    # swing_blades: two quick high whooshes + shing
    a = whoosh(0.2, 5000, 1500, q=1.8, bright=0.25)
    b = whoosh(0.2, 6000, 1800, q=1.8, bright=0.25)
    shing = metal_ring(0.35, 2200, tau=0.09, k=7) * 0.12
    finish('swing_blades', mix(a, at(b * 0.85, 0.07), at(shing, 0.02)), verb=IR_ROOM, wet=0.08)

    # hit_flesh: thump + crunch + wet slap
    th = thump(0.22, 160, 55, tau=0.06, click=0.5)
    cr = crunch(0.12, 900, 3500, tau=0.025) * 0.5
    wet = lp(R.standard_normal(N(0.15)), 900) * expdecay(N(0.15), 0.04) * 0.6
    bone = crunch(0.05, 2500, 7000, tau=0.008) * 0.3
    finish('hit_flesh', soft_clip(mix(th, cr, wet, bone) * 1.5, 1.2), verb=IR_ROOM, wet=0.06)

    # hit_crit: heavier impact + bright ring + sub boom
    th = thump(0.4, 200, 42, tau=0.12, click=0.8)
    cr = crunch(0.18, 700, 5000, tau=0.04) * 0.6
    ring = bell(1320, 0.7, tau=0.35, ratios=(1, 2.32, 3.17, 4.41, 6.2), amps=(1, .7, .5, .3, .2)) * 0.25
    zap = whoosh(0.15, 8000, 2000, q=2, bright=0.3) * 0.4
    finish('hit_crit', soft_clip(mix(th * 1.2, cr, ring, zap) * 1.6, 1.4), verb=IR_ROOM, wet=0.12)

    # dash: rising/falling airy swoosh + shimmer
    n = N(0.38)
    tt = np.linspace(0, 1, n)
    sh = np.sin(np.pi * tt ** 0.5) ** 1.5
    w = whoosh(0.38, 600, 3800, q=1.2, shape=sh, bright=0.2)
    sp = sine(2400 + 3000 * tt, n) * sh * 0.05 + sine(3600 + 4000 * tt, n) * sh * 0.03
    finish('dash', mix(w, sp), verb=IR_ROOM, wet=0.15)

    # special_ember: flame burst + boom + crackles
    n = N(1.3)
    tt = np.linspace(0, 1, n)
    roar = sweep_filter(R.standard_normal(n), 300, 2500, 'band', q=0.7) * np.exp(-tt * 3) * (1 - np.exp(-tt * 60))
    roar = soft_clip(roar * 2.5 * (1 + 0.5 * lp(R.standard_normal(n), 12) * 4), 1.5)
    boom = thump(0.8, 120, 38, tau=0.25, click=0.6)
    cr = crackles(1.2, rate=90) * np.exp(-np.linspace(0, 1, N(1.2)) * 2.5) * 0.6
    wh = whoosh(0.5, 400, 3000, q=1.0) * 0.6
    finish('special_ember', mix(wh, at(roar, 0.05), at(boom, 0.05), at(cr, 0.08)), verb=IR_HALL, wet=0.12)

    # special_moon: crystalline chimes + shimmer swell + whoosh
    notes = [76, 81, 83, 88, 91, 95]
    ch = np.zeros(N(1.6))
    for i, m in enumerate(notes):
        b = bell(float(mtof(m)), 1.2, tau=0.5, amps=(1, .4, .25, .1, .05)) * 0.45
        s = N(0.03 + i * 0.045)
        ch[s:s + len(b)] += b[:len(ch) - s]
    n = N(1.6)
    tt = np.linspace(0, 1, n)
    pad = chord_pad([float(mtof(64)), float(mtof(71)), float(mtof(76))], 1.6, attack=0.05, rel=1.2) * 0.07
    shimmer = hp(R.standard_normal(n), 7000) * np.exp(-tt * 4) * 0.25
    wh = whoosh(0.5, 3000, 800, q=1.2) * 0.6
    finish('special_moon', mix(ch, pad, shimmer, wh), verb=IR_HALL, wet=0.35)

    # hero_hurt: short female effort grunt + impact
    g = grunt(0.26, 300, 230, 'a', shift=1.15, breath=0.35,
              env=adsr(N(0.26), 0.01, 0.06, 0.55, 0.15))
    th = thump(0.15, 140, 60, tau=0.04, click=0.4) * 0.6
    finish('hero_hurt', mix(g, th), verb=IR_ROOM, wet=0.08)

    # hero_down: falling cry + body fall + weapon clatter
    g = grunt(0.7, 330, 190, 'a', shift=1.12, breath=0.4,
              env=adsr(N(0.7), 0.02, 0.25, 0.5, 0.4))
    fall = mix(thump(0.35, 110, 45, tau=0.09, click=0.6), crunch(0.2, 200, 1200, tau=0.05) * 0.4)
    clat = np.zeros(N(0.6))
    for k, d in enumerate([0.0, 0.11, 0.19, 0.26]):
        m = metal_ring(0.3, 1700 + 400 * k, tau=0.05, k=5) * (0.35 / (1 + k * 0.5))
        s = N(d); clat[s:s + len(m)] += m[:len(clat) - s]
    finish('hero_down', mix(g, at(fall, 0.55), at(clat, 0.6)), verb=IR_ROOM, wet=0.12)

    # revive: rising shimmer arpeggio + choir swell
    arp = chirp_sparkle(1.4, float(mtof(72)), float(mtof(96)), count=9, tau=0.25) * 0.4
    choir = chord_pad([float(mtof(60)), float(mtof(64)), float(mtof(67)), float(mtof(72))], 1.5, vowel='a', attack=0.5, rel=0.7) * 0.06
    finish('revive', mix(arp, choir), verb=IR_HALL, wet=0.35)

    # enemy_die: ghost shriek falling + dust puff
    n = N(0.6)
    tt = np.linspace(0, 1, n)
    f = 900 * (0.35) ** tt * (1 + 0.05 * sine(14, n))
    shriek = formant(saw(f, n) + 0.3 * R.standard_normal(n), 'i', 1.0) * adsr(n, 0.01, 0.1, 0.6, 0.35)
    puff = sweep_filter(R.standard_normal(N(0.5)), 1500, 300, 'low') * adsr(N(0.5), 0.02, 0.1, 0.4, 0.3) * 0.8
    finish('enemy_die', mix(shriek * 0.5, at(puff, 0.08)), verb=IR_ROOM, wet=0.18)

    # shade_lunge: hissing whoosh + raspy snarl
    hiss = whoosh(0.4, 2500, 6000, q=1.0, bright=0.4)
    sn = grunt(0.35, 140, 110, 'o', shift=0.9, breath=0.8, rasp=0.9,
               env=adsr(N(0.35), 0.03, 0.1, 0.7, 0.2)) * 0.6
    finish('shade_lunge', mix(hiss, sn), verb=IR_ROOM, wet=0.12)

    # spitter_shoot: wet ptoo + hiss
    n = N(0.3)
    tt = np.linspace(0, 1, n)
    bub = sine(350 + 900 * tt ** 0.5, n) * expdecay(n, 0.05) * 0.8
    wetn = lp(R.standard_normal(n), 1800) * expdecay(n, 0.04)
    hiss = hp(R.standard_normal(n), 4000) * adsr(n, 0.02, 0.05, 0.3, 0.2) * 0.25
    finish('spitter_shoot', soft_clip(mix(bub, wetn, hiss) * 1.5), verb=IR_ROOM, wet=0.06)

    # projectile_hit: splat + bubbles + sizzle
    sp = bp(R.standard_normal(N(0.12)), 400, 2500) * expdecay(N(0.12), 0.03)
    bubbles = np.zeros(N(0.3))
    for i in range(5):
        L = N(0.04)
        b = sine(np.linspace(R.uniform(500, 900), R.uniform(1000, 1800), L), L) * expdecay(L, 0.01)
        s = N(R.uniform(0.0, 0.18)); bubbles[s:s + L] += b * 0.35
    siz = hp(R.standard_normal(N(0.4)), 3500) * adsr(N(0.4), 0.01, 0.05, 0.3, 0.3) * 0.25
    finish('projectile_hit', mix(sp, bubbles, siz, thump(0.1, 120, 60, 0.03) * 0.5), verb=IR_ROOM, wet=0.06)

    # brute_slam: heavy windup whoosh + guttural growl
    w = whoosh(0.8, 200, 900, q=0.9, shape=adsr(N(0.8), 0.5, 0.1, 0.8, 0.2))
    gr = grunt(0.9, 75, 95, 'o', shift=0.7, breath=0.3, rasp=1.2,
               env=adsr(N(0.9), 0.15, 0.2, 0.8, 0.3))
    finish('brute_slam', soft_clip(mix(w * 0.6, gr) * 1.4, 1.3), verb=IR_ROOM, wet=0.1)

    # slam_impact: massive boom + crack + rubble
    boom = thump(1.0, 95, 32, tau=0.3, click=1.0) * 1.3
    crack = crunch(0.15, 300, 6000, tau=0.03) * 0.8
    rub = np.zeros(N(1.0))
    for i in range(40):
        L = N(R.uniform(0.01, 0.04))
        g = bp(R.standard_normal(L), 300, R.uniform(1500, 4000)) * expdecay(L, 0.01)
        s = N(0.05 + R.exponential(0.2))
        if s + L < len(rub): rub[s:s + L] += g * R.uniform(0.1, 0.5) * np.exp(-s / SR * 2)
    low = lp(R.standard_normal(N(1.0)), 200) * expdecay(N(1.0), 0.25) * 0.6
    finish('slam_impact', soft_clip(mix(boom, crack, rub, low) * 1.3, 1.2), verb=IR_HALL, wet=0.1)

    # regent_burst: deep pulse + dark detuned swell + whoosh ring
    n = N(1.0)
    tt = np.linspace(0, 1, n)
    pulse = thump(0.6, 140, 45, tau=0.15, click=0.4)
    dark = chord_pad([float(mtof(38)), float(mtof(41)), float(mtof(44))], 1.0, attack=0.01, rel=0.7) * 0.2
    dark = soft_clip(dark * 3, 2)
    t9 = np.linspace(0, 1, N(0.9))
    wh = whoosh(0.9, 300, 4000, q=0.9, shape=np.exp(-t9 * 3) * (1 - np.exp(-t9 * 40)))
    finish('regent_burst', mix(pulse, dark * 0.5, wh * 0.7), verb=IR_HALL, wet=0.15)

    # regent_charge: rising rumble into rushing whoosh
    n = N(1.3)
    tt = np.linspace(0, 1, n)
    rumble = sweep_filter(R.standard_normal(n), 120, 2500, 'low') * (tt ** 1.5) * 1.5
    rise = saw(50 * (4 ** tt), n) * tt ** 2 * 0.3
    rise = lp(soft_clip(rise * 2), 1500)
    rush = whoosh(0.45, 800, 4500, q=0.8, bright=0.3)
    finish('regent_charge', mix(rumble, rise, at(rush, 0.9)), verb=IR_HALL, wet=0.12)

    # regent_summon: eerie rising wails + rumble + whisper noise
    n = N(1.9)
    tt = np.linspace(0, 1, n)
    wails = np.zeros(n)
    for i, (f0, f1) in enumerate([(220, 440), (330, 520), (260, 620), (180, 300)]):
        f = f0 * (f1 / f0) ** tt * (1 + 0.02 * sine(5 + i, n))
        wails += formant(saw(f, n, ph0=R.random()), 'u' if i % 2 else 'o') * np.sin(np.pi * np.clip(tt * 1.1 - i * 0.04, 0, 1)) * 0.5
    rumble = lp(R.standard_normal(n), 120) * np.sin(np.pi * tt) * 2
    whisper = bp(R.standard_normal(n), 2000, 6000) * (0.5 + 0.5 * sine(7, n)) * np.sin(np.pi * tt) * 0.15
    finish('regent_summon', mix(wails, rumble, whisper), verb=IR_HALL, wet=0.35)

    # regent_roar: deep distorted bellow
    n = N(1.8)
    g1 = grunt(1.8, 70, 55, 'a', shift=0.65, breath=0.4, rasp=1.5,
               env=adsr(n, 0.12, 0.3, 0.8, 0.9))
    g2 = grunt(1.8, 105, 82, 'o', shift=0.7, breath=0.2, rasp=1.0,
               env=adsr(n, 0.15, 0.3, 0.7, 0.9)) * 0.6
    sub = sine(np.linspace(48, 38, n), n) * adsr(n, 0.1, 0.3, 0.7, 0.9) * 0.4
    roar = soft_clip((g1 + g2) * 3, 2.5) + sub
    finish('regent_roar', roar, verb=IR_HALL, wet=0.3)

    # regent_die: falling agonised roar + armour collapse + soul whoosh
    n = N(2.2)
    g = grunt(2.2, 95, 45, 'a', shift=0.65, breath=0.5, rasp=1.6,
              env=adsr(n, 0.08, 0.5, 0.7, 1.4))
    g = soft_clip(g * 3, 2.2)
    clat = np.zeros(N(1.2))
    for k in range(8):
        m = metal_ring(0.4, R.uniform(600, 1800), tau=0.08, k=5) * R.uniform(0.15, 0.4)
        s = N(R.uniform(0, 0.6)); clat[s:s + len(m)] += m[:len(clat) - s]
    fall = thump(0.8, 90, 35, tau=0.25, click=1.0)
    soul = whoosh(1.4, 300, 5000, q=1.0, bright=0.2) * 0.5
    finish('regent_die', mix(g, at(clat, 1.3), at(fall, 1.3), at(soul, 1.5)), verb=IR_HALL, wet=0.3)

    # boon_pickup: ascending sparkle + warm swell
    sp = chirp_sparkle(1.0, float(mtof(79)), float(mtof(98)), count=7, tau=0.2) * 0.5
    pad = chord_pad([float(mtof(67)), float(mtof(71)), float(mtof(74))], 1.0, attack=0.15, rel=0.6) * 0.06
    finish('boon_pickup', mix(sp, pad), verb=IR_HALL, wet=0.3)

    # door_open: stone grind + magic hum
    n = N(1.6)
    tt = np.linspace(0, 1, n)
    grind = lp(R.standard_normal(n), 900) * (1 + 0.8 * np.clip(lp(R.standard_normal(n), 25) * 6, -1, 1))
    grind *= adsr(n, 0.1, 0.2, 0.8, 0.4)
    hum = (sine(98, n) + 0.6 * sine(147, n) + 0.3 * sine(196 * 1.003, n)) * adsr(n, 0.05, 0.3, 0.5, 0.8) * 0.4
    unlock = thump(0.3, 180, 70, tau=0.08, click=0.8)
    finish('door_open', mix(unlock, at(grind, 0.08), hum), verb=IR_HALL, wet=0.2)

    # room_clear: bell + choir swell
    b = bell(float(mtof(74)), 1.8, tau=0.9) * 0.6 + bell(float(mtof(81)), 1.8, tau=0.7) * 0.3
    ch = chord_pad([float(mtof(62)), float(mtof(66)), float(mtof(69)), float(mtof(74))], 1.6, vowel='a', attack=0.3, rel=0.9) * 0.05
    finish('room_clear', mix(b, ch), verb=IR_HALL, wet=0.35)

    # shard_pickup: glassy two-note ping
    a = bell(float(mtof(91)), 0.35, tau=0.12, amps=(1, .3, .3, .15, .05))
    b = bell(float(mtof(98)), 0.4, tau=0.15, amps=(1, .3, .3, .15, .05))
    finish('shard_pickup', mix(a * 0.7, at(b, 0.06)), verb=IR_ROOM, wet=0.15)

    # footstep: soft sandal on stone
    tap = lp(R.standard_normal(N(0.06)), 2200) * expdecay(N(0.06), 0.012)
    th = thump(0.08, 120, 70, tau=0.02, click=0.1) * 0.6
    scuff = bp(R.standard_normal(N(0.08)), 1500, 5000) * adsr(N(0.08), 0.01, 0.02, 0.3, 0.05) * 0.15
    finish('footstep', mix(tap, th, at(scuff, 0.01)), hpf=60)

    # ---------- UI ----------
    # click: crisp wooden-ish tick
    c = bp(R.standard_normal(N(0.03)), 1500, 6000) * expdecay(N(0.03), 0.004)
    c += sine(1800, N(0.03)) * expdecay(N(0.03), 0.006) * 0.4
    finish('ui_click', c, peak_db=-3)

    # hover: very soft high tick
    h = mix(sine(3200, N(0.04)) * expdecay(N(0.04), 0.008) * 0.6, hp(R.standard_normal(N(0.02)), 5000) * expdecay(N(0.02), 0.003) * 0.3)
    finish('ui_hover', h, peak_db=-6)

    # confirm: rising two-note chime
    a = bell(float(mtof(79)), 0.3, tau=0.12, amps=(1, .3, .2, .1, .05))
    b = bell(float(mtof(86)), 0.5, tau=0.2, amps=(1, .3, .2, .1, .05))
    finish('ui_confirm', mix(a * 0.8, at(b, 0.07), c * 0.5), verb=IR_ROOM, wet=0.15, peak_db=-2)

    # back: falling two notes, softer
    a = bell(float(mtof(81)), 0.25, tau=0.08, amps=(1, .2, .1, .05, .02))
    b = bell(float(mtof(74)), 0.35, tau=0.12, amps=(1, .2, .1, .05, .02))
    finish('ui_back', mix(a * 0.8, at(b, 0.06)), verb=IR_ROOM, wet=0.12, peak_db=-3)

    # boon (menu choose a blessing): sparkle + low chord
    sp = chirp_sparkle(0.9, float(mtof(84)), float(mtof(100)), count=6, tau=0.15) * 0.5
    low = chord_pad([float(mtof(55)), float(mtof(62)), float(mtof(67))], 0.9, attack=0.02, rel=0.7) * 0.08
    finish('ui_boon', mix(sp, low, thump(0.2, 200, 80, 0.05, 0.2) * 0.4), verb=IR_HALL, wet=0.3, peak_db=-2)

    # purchase: coin-like double ping + chime
    coin1 = bell(2100, 0.3, tau=0.1, ratios=(1, 2.7, 5.1), amps=(1, .5, .25))
    coin2 = bell(2650, 0.4, tau=0.14, ratios=(1, 2.7, 5.1), amps=(1, .5, .25))
    ch = bell(float(mtof(84)), 0.6, tau=0.3) * 0.5
    finish('ui_purchase', mix(coin1 * 0.6, at(coin2 * 0.6, 0.07), at(ch, 0.12)), verb=IR_ROOM, wet=0.15, peak_db=-2)

    # open: soft whoosh + chime (panel opening)
    w = whoosh(0.3, 800, 3000, q=1.0) * 0.5
    ch = bell(float(mtof(81)), 0.5, tau=0.2, amps=(1, .3, .2, .1, .05)) * 0.6
    finish('ui_open', mix(w, at(ch, 0.08)), verb=IR_ROOM, wet=0.2, peak_db=-3)


if __name__ == '__main__':
    gen_all()
