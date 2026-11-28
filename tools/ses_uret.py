#!/usr/bin/env python3
"""Junk to Shine sesleri: hepsi koddan üretilir (dış kaynak yok, telif yok).
Çalıştırma: python3 tools/ses_uret.py  -> assets/audio/*.ogg
"""
import numpy as np, subprocess, os, tempfile
from scipy import signal
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t_(d): return np.arange(int(SR * d)) / SR
def noise(d): return rng.standard_normal(int(SR * d))
def bp(x, lo, hi, order=2): return signal.sosfilt(signal.butter(order, [lo, hi], "band", fs=SR, output="sos"), x)
def lp(x, f, order=2): return signal.sosfilt(signal.butter(order, f, "low", fs=SR, output="sos"), x)
def hp(x, f, order=2): return signal.sosfilt(signal.butter(order, f, "high", fs=SR, output="sos"), x)
def brown(d):
    x = np.cumsum(noise(d)); x = hp(x, 20); return x / (np.abs(x).max() + 1e-9)
def norm(x, peak=0.8): return x / (np.abs(x).max() + 1e-9) * peak


def smooth_lfo(d, rate, depth, lo=0.0):
    """Yavaş, rastgele dalgalanan zarf (0..1)."""
    n = int(SR * d); k = max(4, int(d * rate))
    pts = rng.random(k + 1)
    pts[-1] = pts[0]
    x = np.interp(np.linspace(0, k, n), np.arange(k + 1), pts)
    x = lp(x, rate * 2, 1) if rate * 2 < SR / 2 else x
    return lo + (1 - lo) * (1 - depth + depth * x)


def loopify(x, fade=2.0):
    """Sonu başa yumuşakça bindirerek kusursuz döngü yap."""
    if x.ndim == 1: x = x[:, None]
    f = int(SR * fade)
    head, body = x[:f], x[f:].copy()
    w = np.linspace(0, 1, f)[:, None]
    body[-f:] = body[-f:] * (1 - w) + head * w
    return body.squeeze()


def stereo(l, r): return np.stack([l, r], 1)


def save(name, x, q=4):
    x = np.clip(x, -1, 1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, SR, (x * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f.name, "-c:a", "libvorbis", "-q:a", str(q),
                        os.path.join(OUT, name + ".ogg")], check=True)
    os.unlink(f.name)
    print(name, f"{len(x)/SR:.1f} sn")


# ---------------------------------------------------------------- ortam
def waves(d, calm):
    """Kıyıya vuran dalgalar: kahverengi gürültü + 6-10 sn'lik kabarma."""
    n = int(SR * d); out = np.zeros(n)
    pos = 0.0
    while pos < d:
        per = rng.uniform(5.5, 9.5) if not calm else rng.uniform(7, 11)
        i0 = int(pos * SR); L = int(per * SR)
        env = np.zeros(L)
        a = int(L * rng.uniform(0.25, 0.4))
        env[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
        env[a:] = np.exp(-np.linspace(0, 4.5, L - a))
        seg = brown(per) * 0.6 + bp(noise(per), 300, 2500) * 0.25 * env
        seg = lp(seg, rng.uniform(900, 1600) if not calm else 900)
        end = min(n, i0 + L)
        out[i0:end] += (seg * env)[: end - i0]
        pos += per * rng.uniform(0.55, 0.8)
    return out


def wind(d, strength):
    x = bp(noise(d), 180, 900, 2) * smooth_lfo(d, 0.25, 0.9)
    whistle = bp(noise(d), 900, 1400, 4) * smooth_lfo(d, 0.15, 1.0) ** 3
    return x + whistle * 0.6 * strength


def bird(d_total, count):
    out = np.zeros(int(SR * d_total))
    for _ in range(count):
        t0 = rng.uniform(0, d_total - 2)
        f0 = rng.uniform(2400, 4200)
        for k in range(rng.integers(2, 6)):
            dur = rng.uniform(0.06, 0.16)
            tt = t_(dur)
            f = f0 * (1 + rng.uniform(-0.25, 0.3) * tt / dur)
            ph = 2 * np.pi * np.cumsum(f) / SR
            s = np.sin(ph + 0.8 * np.sin(ph * 0.5)) * np.sin(np.pi * tt / dur) ** 2
            i = int((t0 + k * rng.uniform(0.12, 0.22)) * SR)
            out[i:i + len(s)] += s[: len(out) - i] * rng.uniform(0.3, 0.7)
    return out


def ambience(calm):
    D = 46
    l = waves(D, calm) * (0.55 if calm else 0.75)
    r = np.roll(waves(D, calm), int(SR * 1.7)) * (0.55 if calm else 0.75)
    w1, w2 = wind(D, 0.3 if calm else 1.0), wind(D, 0.3 if calm else 1.0)
    l += w1 * (0.12 if calm else 0.45); r += w2 * (0.12 if calm else 0.45)
    if calm:
        b = bird(D, 12)
        l += b * 0.05; r += np.roll(b, 900) * 0.035
        gull = np.zeros(int(SR * D))
        for _ in range(3):
            tt = t_(0.5); f = 1300 - 500 * tt / 0.5
            s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / 0.5) ** 1.5
            s = s + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / 0.5)
            i = int(rng.uniform(1, D - 2) * SR); gull[i:i + len(s)] += s
        l += gull * 0.035; r += gull * 0.05
    x = loopify(stereo(l, r), 3.0)
    return norm(x, 0.7)


save("ortam_kasvetli", ambience(False))
save("ortam_gunesli", ambience(True))

# ---------------------------------------------------------------- aletler
def swish(d=0.42):
    tt = t_(d); x = noise(d)
    f = np.interp(tt, [0, d], [700, 3800])
    y = np.zeros_like(x)
    sos_parts = 8
    for k in range(sos_parts):
        a, b = int(len(x) * k / sos_parts), int(len(x) * (k + 1) / sos_parts)
        fc = f[(a + b) // 2]
        y[a:b] = bp(x, fc * 0.6, min(fc * 1.6, 15000))[a:b]
    env = np.sin(np.pi * np.clip(tt / d, 0, 1)) ** 2.5
    grass = bp(noise(d), 2000, 7000) * (rng.random(len(x)) < 0.02) * 4
    return norm((y + grass * 0.4) * env, 0.75)


def rake_loop(d=3.0):
    x = np.zeros(int(SR * d))
    stroke = 0.75
    for k in range(int(d / stroke)):
        i0 = int(k * stroke * SR)
        L = int(stroke * SR * 0.8)
        env = np.sin(np.linspace(0, np.pi, L)) ** 1.5
        scr = bp(noise(L / SR), 1500, 6000) * 0.5
        clicks = (rng.random(L) < 0.004).astype(float)
        clicks = bp(clicks, 2500, 8000) * 6
        leaves = bp(noise(L / SR), 400, 2500) * 0.6
        x[i0:i0 + L] += (scr + clicks + leaves) * env
    return norm(loopify(x, 0.2), 0.7)


def washer_loop(d=3.0):
    hiss = hp(noise(d), 2500) * 0.6 + bp(noise(d), 600, 2500) * 0.4
    pump = signal.sawtooth(2 * np.pi * 50 * t_(d)) * 0.08
    pump = lp(pump, 400)
    flutter = 1 + 0.06 * np.sin(2 * np.pi * 11 * t_(d))
    return norm(loopify((hiss * flutter + pump), 0.3), 0.6)


def motor_loop(d=2.0, f=95.0, rough=0.3):
    """İki zamanlı motor: kısa darbeler dizisi + uğultu."""
    tt = t_(d)
    ff = f * (1 + 0.02 * np.sin(2 * np.pi * 0.7 * tt))
    ph = np.cumsum(ff) / SR
    pulse = (np.sin(2 * np.pi * ph) > 0.85).astype(float)
    body = lp(pulse, 1800) * 1.5 + signal.sawtooth(2 * np.pi * ph * 2) * 0.15
    x = body + bp(noise(d), 200, 3000) * rough * 0.3
    return norm(loopify(lp(x, 4000), 0.2), 0.6)


def vacuum_loop(d=2.0):
    tt = t_(d)
    whine = sum(np.sin(2 * np.pi * 185 * h * tt) / h for h in range(1, 7)) * 0.12
    air = bp(noise(d), 400, 5000) * 0.6
    return norm(loopify(whine + air, 0.2), 0.6)


def robot_loop(d=2.0):
    tt = t_(d)
    hum = np.sin(2 * np.pi * 120 * tt) * 0.2 + np.sin(2 * np.pi * 240 * tt) * 0.08
    brush = bp(noise(d), 800, 4000) * 0.35 * (1 + 0.3 * np.sin(2 * np.pi * 6 * tt))
    return norm(loopify(hum + brush, 0.2), 0.5)


save("tirpan", swish())
save("tirmik", rake_loop())
save("yikayici", washer_loop())
save("motor", motor_loop())
save("supurge", vacuum_loop())
save("robot", robot_loop())

# ---------------------------------------------------------------- olaylar
def radio():
    d = 0.55; tt = t_(d)
    st = bp(noise(d), 800, 4000) * np.exp(-tt * 5) * 0.8
    beep = np.sin(2 * np.pi * 1450 * tt) * ((tt > 0.32) & (tt < 0.45)) * 0.35
    crackle = (rng.random(len(tt)) < 0.01) * rng.uniform(-1, 1, len(tt)) * np.exp(-tt * 3)
    return norm(st + beep + crackle * 0.6, 0.7)


def bell(freq=880, d=2.2):
    tt = t_(d); x = np.zeros_like(tt)
    for ratio, amp, dec in [(1, 1, 2.2), (2.76, 0.5, 3.5), (5.4, 0.25, 5), (8.93, 0.12, 7), (0.5, 0.3, 1.5)]:
        x += amp * np.sin(2 * np.pi * freq * ratio * tt) * np.exp(-tt * dec)
    return norm(x * (1 - np.exp(-tt * 300)), 0.6)


def chime():
    a = bell(1046.5, 1.8); b = bell(1568.0, 1.6)
    out = np.zeros(int(SR * 2.2)); out[: len(a)] += a; i = int(SR * 0.12); out[i:i + len(b)] += b * 0.8
    return norm(out, 0.6)


def horn():
    d = 3.2; tt = t_(d)
    env = np.clip(tt / 0.25, 0, 1) * np.clip((d - tt) / 0.6, 0, 1)
    x = (signal.sawtooth(2 * np.pi * 110 * tt) + 0.7 * signal.sawtooth(2 * np.pi * 138.6 * tt)) * env
    x = lp(x, 900, 3)
    echo = np.zeros(len(x) + int(SR * 1.2)); echo[: len(x)] += x; echo[int(SR * 0.9):int(SR * 0.9) + len(x)] += lp(x, 500) * 0.3
    return norm(echo, 0.75)


def fanfare():
    # Bölge tamamlandı: yükselen dört nota (marimba benzeri)
    notes = [523.25, 659.25, 783.99, 1046.5]
    out = np.zeros(int(SR * 1.8))
    for k, f in enumerate(notes):
        tt = t_(1.0)
        s = (np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(2 * np.pi * f * 4 * tt) * np.exp(-tt * 20)) * np.exp(-tt * 5)
        i = int(k * 0.12 * SR); out[i:i + len(s)] += s
    return norm(out, 0.6)


def coin():
    tt = t_(0.35)
    a = np.sin(2 * np.pi * 1318.5 * tt) * np.exp(-tt * 14) * (tt < 0.08)
    b = np.sin(2 * np.pi * 1975.5 * tt) * np.exp(-(tt - 0.07).clip(0) * 9) * (tt >= 0.07)
    return norm(a + b, 0.5)


def pickup():
    tt = t_(0.12)
    f = 600 + 900 * tt / 0.12
    return norm(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 25), 0.5)


save("telsiz", radio())
save("buluntu", chime())
save("feribot", horn())
save("bolge_tamam", fanfare())
save("para", coin())
save("topla", pickup())

# ---------------------------------------------------------------- müzik
def ks_pluck(f, d, bright=0.5):
    """Karplus-Strong: koparılan tel."""
    n = int(SR * d); N = int(SR / f)
    buf = rng.uniform(-1, 1, N) * bright + lp(rng.uniform(-1, 1, N + 64), 3000)[64:] * (1 - bright)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % N]
        buf[i % N] = 0.996 * 0.5 * (buf[i % N] + buf[(i + 1) % N])
    return out


def pad(freqs, d):
    tt = t_(d); x = np.zeros_like(tt)
    for f in freqs:
        for det in (-0.004, 0.0, 0.005):
            x += signal.sawtooth(2 * np.pi * f * (1 + det) * tt + rng.uniform(0, 6))
    x = lp(x, 850, 4)
    env = np.minimum(np.clip(tt / 2.5, 0, 1), np.clip((d - tt) / 2.5, 0, 1))
    return x * env


BPM = 72
beat = 60 / BPM
bar = beat * 4
chords = [  # Am - F - C - G (iki tur)
    [220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [261.63, 329.63, 392.0], [196.0, 246.94, 293.66],
]
L = bar * 2 * len(chords) * 2  # 16 ölçü
pad_l = np.zeros(int(SR * L) + SR * 3); pad_r = pad_l.copy()
pl_l = pad_l.copy(); pl_r = pad_l.copy()
for rep in range(2):
    for ci, ch in enumerate(chords):
        t0 = (rep * len(chords) + ci) * bar * 2
        p = pad([f / 2 for f in ch], bar * 2 + 2.5)
        i = int(t0 * SR)
        pad_l[i:i + len(p)] += p; pad_r[i:i + len(p)] += np.roll(p, 400)
        # arpej: 8'lik notalar, akor + oktav
        arp = ch + [ch[0] * 2, ch[1] * 2]
        for k in range(16):
            if rng.random() < 0.18:
                continue
            f = arp[[0, 2, 1, 3, 2, 4, 3, 1][k % 8]]
            s = ks_pluck(f, beat * 2.2, 0.35) * rng.uniform(0.5, 0.8)
            j = int((t0 + k * beat / 2) * SR)
            pan = 0.5 + 0.3 * np.sin(k)
            pl_l[j:j + len(s)] += s * (1 - pan); pl_r[j:j + len(s)] += s * pan
n = int(SR * L)
def wrap(x):
    y = x[:n].copy(); tail = x[n:]; y[: len(tail)] += tail; return y
pads = stereo(wrap(pad_l), wrap(pad_r))
plucks = stereo(lp(wrap(pl_l), 3000, 4), lp(wrap(pl_r), 3000, 4))
# Basit yankı
def reverb(x, mix=0.25):
    out = x.copy()
    for dly, g in [(0.083, 0.5), (0.127, 0.4), (0.191, 0.33), (0.277, 0.25), (0.401, 0.18)]:
        out += np.roll(x, int(dly * SR), axis=0) * g * mix * 2
    return out
save("muzik_taban", norm(reverb(pads, 0.3), 0.55), 5)
save("muzik_melodi", norm(reverb(plucks, 0.35), 0.6), 5)
