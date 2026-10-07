"""効果音・環境音・BGM をすべて数式で合成して audio/ に WAV で書き出す。
    py -3.10 tools/gen_audio.py
外部素材は使っていない（旋律もオリジナル）。
"""
import os
import wave

import numpy as np
from scipy.signal import butter, lfilter, sosfilt

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(7)


def t_of(dur):
    return np.arange(int(dur * SR)) / SR


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32000).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def bp(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def lp(x, f, order=2):
    sos = butter(order, f, btype="low", fs=SR, output="sos")
    return sosfilt(sos, x)


def hp(x, f, order=2):
    sos = butter(order, f, btype="high", fs=SR, output="sos")
    return sosfilt(sos, x)


def noise(n):
    return rng.uniform(-1, 1, n)


def env_ad(n, a, d):
    """a 秒で立ち上がり、指数 d で減衰"""
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-t * d)
    return e


def fade(x, fi=0.005, fo=0.02):
    n = len(x)
    a = int(fi * SR)
    b = int(fo * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[n - b:] *= np.linspace(1, 0, b)
    return x


def reverb(x, wet=0.3, size=1.0):
    """Schroeder 風の簡単な残響"""
    out = np.zeros_like(x)
    for d, g in [(1116, 0.84), (1188, 0.83), (1277, 0.82), (1356, 0.81)]:
        D = int(d * size)
        a = np.zeros(D + 1)
        a[0] = 1.0
        a[D] = -g
        out += lfilter([1.0], a, x)
    out /= 4.0
    for d, g in [(225, 0.5), (556, 0.5), (441, 0.5)]:
        b = np.zeros(d + 1)
        b[0] = -g
        b[d] = 1.0
        a = np.zeros(d + 1)
        a[0] = 1.0
        a[d] = -g
        out = lfilter(b, a, out)
    return x * (1 - wet) + out * wet


def loopify(x, xf=1.0):
    """末尾を先頭にクロスフェードして継ぎ目なくループさせる"""
    n = int(xf * SR)
    head = x[:n].copy()
    tail = x[-n:].copy()
    k = np.linspace(0, 1, n)
    y = x[n:].copy()
    y[-n:] = tail * (1 - k) + head * k
    return y


def crackle(n, rate, dec=600.0, amp=1.0):
    """落ち葉のパリパリ（細かいインパルスの集まり）"""
    x = np.zeros(n)
    cnt = int(rate * n / SR)
    for _ in range(cnt):
        p = rng.integers(0, max(1, n - 200))
        L = rng.integers(40, 160)
        tt = np.arange(L) / SR
        x[p:p + L] += noise(L) * np.exp(-tt * dec * rng.uniform(0.6, 1.6)) * rng.uniform(0.2, 1.0) * amp
    return x


def crow():
    x = np.zeros(int(1.6 * SR))
    for k in range(2):
        t = t_of(0.42)
        f0 = 520 - 120 * t / 0.42
        ph = 2 * np.pi * np.cumsum(f0) / SR
        saw = sum(np.sin(m * ph) / m for m in range(1, 18))
        v = bp(saw + noise(len(t)) * 0.6, 900, 1700) + bp(saw, 1900, 2600) * 0.5
        e = np.minimum(1, t / 0.03) * np.minimum(1, (0.42 - t) / 0.15)
        p = int(k * 0.62 * SR)
        x[p:p + len(t)] += v * e
    return fade(reverb(x, 0.45, 1.4))


def ks_pluck(freq, dur, bright=0.5):
    n = int(dur * SR)
    N = max(2, int(SR / freq))
    buf = lp(noise(N), 1000 + 5000 * bright)
    out = np.zeros(n)
    i = 0
    damp = 0.996
    while i < n:
        L = min(N, n - i)
        out[i:i + L] = buf[:L]
        nb = damp * 0.5 * (buf + np.roll(buf, -1))
        buf = nb
        i += N
    return out


def musicbox(freq, dur):
    t = t_of(dur)
    x = (np.sin(2 * np.pi * freq * t) * np.exp(-t * 2.2)
         + 0.35 * np.sin(2 * np.pi * freq * 4.0 * t) * np.exp(-t * 7)
         + 0.12 * np.sin(2 * np.pi * freq * 6.8 * t) * np.exp(-t * 12))
    return x * np.minimum(1, t / 0.003)


def pad(freqs, dur):
    t = t_of(dur)
    x = np.zeros(len(t))
    for f in freqs:
        for det in (-0.6, 0.6):
            ph = 2 * np.pi * (f + det) * t
            x += np.sin(ph) + 0.3 * np.sin(2 * ph)
    e = np.minimum(1, t / 0.8) * np.minimum(1, (dur - t) / 0.8).clip(0, 1)
    return lp(x, 900) * e




def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# ---------------------------------------------------------------- 効果音
def step(k):
    """革靴でコンクリートを歩く音"""
    t = t_of(0.18)
    n = len(t)
    heel = bp(noise(n), 900 + k * 150, 4200) * np.exp(-t * 70)
    body = np.sin(2 * np.pi * (160 + k * 15) * t) * np.exp(-t * 45) * 0.5
    grit = hp(crackle(n, 200, 900), 3000) * np.exp(-t * 25) * 0.3
    return fade(heel + body + grit, 0.001)


def land():
    t = t_of(0.35)
    n = len(t)
    x = bp(noise(n), 300, 2500) * np.exp(-t * 30)
    x += np.sin(2 * np.pi * 110 * t) * np.exp(-t * 25) * 0.7
    return fade(x, 0.001)


def whoosh(dur=1.6):
    n = int(dur * SR)
    t = np.arange(n) / SR
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    lo = bp(noise(n), 250, 900)
    hi = bp(noise(n), 1200, 3000) * 0.35
    return fade((lo + hi) * e)


def sigh():
    """ため息（息の音だけ。声は入れない）"""
    dur = 1.9
    n = int(dur * SR)
    t = np.arange(n) / SR
    inh = np.clip(t / 0.55, 0, 1) * np.clip((0.7 - t) / 0.15, 0, 1)
    exh = np.where(t > 0.75, np.minimum(1, (t - 0.75) / 0.06) * np.exp(-(t - 0.75) * 1.9), 0)
    src = noise(n)
    a = bp(src, 500, 1300) * 0.6 + bp(src, 1500, 2600) * 0.35 + bp(src, 3000, 5000) * 0.12
    b = bp(src, 350, 900) * 0.8 + bp(src, 1100, 1900) * 0.4
    return fade(a * inh * 0.35 + b * exh, 0.01, 0.1)


def flap():
    """鳥の群れの羽ばたき"""
    dur = 2.2
    n = int(dur * SR)
    x = np.zeros(n)
    for _ in range(26):
        st = rng.uniform(0, 0.9)
        rate = rng.uniform(7, 11)
        cnt = int(rng.uniform(5, 11))
        for k in range(cnt):
            p = int((st + k / rate) * SR)
            L = int(0.06 * SR)
            if p + L < n:
                tt = np.arange(L) / SR
                x[p:p + L] += bp(noise(L), 400, 2500) * np.sin(np.pi * tt / 0.06) * rng.uniform(0.3, 1.0)
    for _ in range(4):
        L = int(0.12 * SR)
        p = rng.integers(0, n - L)
        tt = np.arange(L) / SR
        f = rng.uniform(2600, 3600) - 1500 * tt / 0.12
        x[p:p + L] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / 0.12) * 0.4
    t = np.arange(n) / SR
    return fade(x * np.minimum(1, t / 0.1) * np.clip((dur - t) / 0.8, 0, 1))


def door():
    """ベランダのサッシを開ける"""
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    roll = lp(noise(n), 400) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t)) * 2.5
    rattle = hp(crackle(n, 120, 700), 1800) * 0.4
    e = np.minimum(1, t / 0.05) * np.clip((0.75 - t) / 0.1, 0, 1)
    hit = np.where(t > 0.72, np.sin(2 * np.pi * 240 * (t - 0.72)) * np.exp(-(t - 0.72) * 40), 0)
    return fade((roll + rattle) * e + hit * 0.7)


def signal_loop():
    """歩行者信号（ピヨ、ピヨピヨ）"""
    dur = 2.4
    n = int(dur * SR)
    x = np.zeros(n)
    for st in (0.0, 0.6, 0.78, 1.2, 1.8, 1.98):
        L = int(0.14 * SR)
        tt = np.arange(L) / SR
        f = 2300 + 1600 * np.sin(np.pi * tt / 0.14)
        p = int(st * SR)
        x[p:p + L] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / 0.14) ** 0.7
    return x


def heli(dur=4.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = (t * 5.0) % 1.0
    pulses = np.exp(-ph * 18)
    x = lp(noise(n), 300) * pulses * 3 + lp(noise(n), 900) * 0.15
    x += np.sin(2 * np.pi * 55 * t) * pulses * 0.6
    return x


def kankan(dur=7.0):
    """遠くの踏切"""
    n = int(dur * SR)
    x = np.zeros(n)
    k = 0
    s = 0.0
    while s < dur - 0.4:
        f = 760 if k % 2 == 0 else 700
        L = int(0.4 * SR)
        tt = np.arange(L) / SR
        tone = np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 2.7 * tt) * np.exp(-tt * 9)
        p = int(s * SR)
        x[p:p + L] += tone * np.exp(-tt * 7)
        s += 0.42
        k += 1
    t = np.arange(n) / SR
    x *= np.minimum(1, t / 1.5) * np.clip((dur - t) / 2.0, 0, 1)
    return fade(reverb(lp(x, 2500), 0.5, 1.5))


# ---------------------------------------------------------------- 環境音
def wind_roof(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    base = lp(lp(noise(n), 450, 1), 280, 1)
    g = 0.5 + 0.28 * np.sin(2 * np.pi * t / 6.5) + 0.22 * np.sin(2 * np.pi * t / 2.9 + 1.0)
    whistle = bp(noise(n), 620, 760, 2) * (0.2 + 0.8 * np.maximum(0, np.sin(2 * np.pi * t / 13.0))) * 0.5
    flutter = bp(noise(n), 150, 400) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * g * 0.6
    return loopify(base * g * 3 + whistle + flutter, 1.5)


def wind_fly(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    g = 0.7 + 0.18 * np.sin(2 * np.pi * t / 5.0) + 0.12 * np.sin(2 * np.pi * t / 1.7)
    x = bp(noise(n), 200, 1400) * g + bp(noise(n), 1500, 3500) * 0.12 * g
    return loopify(x, 1.5)


def city(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    hum = lp(lp(noise(n), 160, 1), 120, 1) * 4
    x = hum + bp(noise(n), 300, 1200) * 0.12
    for _ in range(14):
        c = rng.uniform(0, dur)
        w = rng.uniform(1.5, 4.0)
        e = np.exp(-((t - c) / w) ** 2)
        x += bp(noise(n), 250, 900) * e * rng.uniform(0.3, 0.7)
    for _ in range(2):
        p = int(rng.uniform(2, dur - 2) * SR)
        L = int(0.35 * SR)
        tt = np.arange(L) / SR
        hn = (np.sign(np.sin(2 * np.pi * 410 * tt)) + np.sign(np.sin(2 * np.pi * 520 * tt))) * 0.5
        x[p:p + L] += lp(hn, 1500) * np.minimum(1, tt / 0.02) * np.clip((0.35 - tt) / 0.05, 0, 1) * 0.12
    return loopify(reverb(x, 0.3, 1.6), 2.0)


# ---------------------------------------------------------------- BGM
def cello(freq, dur):
    t = t_of(dur)
    vib = 1 + 0.003 * np.sin(2 * np.pi * 5.2 * t)
    ph = 2 * np.pi * np.cumsum(freq * vib) / SR
    saw = sum(np.sin(k * ph) / k for k in range(1, 14))
    e = np.minimum(1, t / (dur * 0.35)) * np.clip((dur - t) / (dur * 0.4), 0, 1)
    return lp(saw, 700) * e


def drone():
    """導入：静かで少し重たい"""
    seg = 6.0
    prog = [(38, [50, 53, 57]), (34, [50, 53, 58]), (31, [50, 55, 58]), (33, [49, 52, 57])]
    total = seg * len(prog)
    n = int((total + 4) * SR)
    out = np.zeros(n)
    for i, (r, tones) in enumerate(prog):
        p = int(i * seg * SR)
        s = cello(mtof(r), seg + 2.0) * 0.6
        s = s + pad([mtof(m) for m in tones], seg + 2.0)[: len(s)] * 0.05
        L = min(len(s), n - p)
        out[p:p + L] += s[:L]
    t = np.arange(n) / SR
    out += np.sin(2 * np.pi * mtof(26) * t) * 0.25
    out = reverb(out, 0.45, 1.6)
    L = int(total * SR)
    loop = out[:L].copy()
    loop[: n - L] += out[L:]
    return loop


def epiano(freq, dur):
    t = t_of(dur)
    mod = np.sin(2 * np.pi * freq * t) * 1.2 * np.exp(-t * 4)
    x = np.sin(2 * np.pi * freq * t + mod) * np.exp(-t * 1.6)
    x += 0.25 * np.sin(2 * np.pi * freq * 7.0 * t) * np.exp(-t * 14)
    return x * np.minimum(1, t / 0.004)


def bgm():
    """帰り道：ゆるい、ちょっと叙情的"""
    bpm = 80
    beat = 60 / bpm
    bar = beat * 4
    chords = [
        (41, [57, 60, 64, 65]), (40, [55, 59, 62, 64]), (38, [57, 60, 62, 65]), (43, [53, 57, 59, 62]),
        (41, [57, 60, 64, 65]), (40, [55, 59, 62, 64]), (45, [55, 60, 64, 67]), (38, [54, 57, 60, 62]),
        (41, [57, 60, 64, 65]), (43, [55, 59, 62, 65]), (40, [55, 59, 62, 64]), (45, [55, 60, 64, 67]),
        (38, [57, 60, 62, 65]), (43, [53, 57, 59, 62]), (36, [55, 59, 64, 67]), (36, [55, 59, 64, 67]),
    ]
    mel = [
        [(72, 0, 1.5), (69, 1.5, 1), (67, 2.5, 1.5)], [(67, 0, 1), (69, 1, 1), (71, 2, 2)],
        [(72, 0.5, 1.5), (74, 2, 1), (72, 3, 1)], [(71, 0, 3)],
        [(72, 0, 1.5), (69, 1.5, 1), (67, 2.5, 1.5)], [(67, 0, 1), (64, 1, 1), (62, 2, 2)],
        [(64, 0.5, 1.5), (67, 2, 2)], [(66, 0, 2), (69, 2, 2)],
        [(69, 0, 1.5), (72, 1.5, 1), (76, 2.5, 1.5)], [(74, 0, 2), (71, 2, 2)],
        [(71, 0, 1), (72, 1, 1), (74, 2, 2)], [(72, 0, 3)],
        [(69, 0, 1), (72, 1, 1), (74, 2, 1.5)], [(71, 0, 2), (67, 2, 2)],
        [(64, 0, 4)], [],
    ]
    total = bar * len(chords)
    n = int((total + 4) * SR)
    out = np.zeros(n)

    def add(sig, at, gain):
        p = int(at * SR)
        L = min(len(sig), n - p)
        out[p:p + L] += sig[:L] * gain

    for b, (root, tones) in enumerate(chords):
        t0 = b * bar
        add(ks_pluck(mtof(root), 1.8, 0.2), t0, 0.5)
        add(ks_pluck(mtof(root + 7), 1.0, 0.2), t0 + beat * 2.5, 0.25)
        for k, m in enumerate(tones):
            add(epiano(mtof(m), 3.0), t0 + k * 0.012, 0.11)
            add(epiano(mtof(m), 1.6), t0 + beat * 2.25 + k * 0.012, 0.06)
        for m, st, ln in mel[b]:
            add(epiano(mtof(m + 12), ln * beat + 1.0) * 0.8 + musicbox(mtof(m + 12), ln * beat + 1.0) * 0.15,
                t0 + st * beat, 0.16)
        for k in range(8):
            nn = int(0.08 * SR)
            tt = np.arange(nn) / SR
            add(hp(noise(nn), 5000) * np.exp(-tt * 50), t0 + k * beat / 2, 0.03 if k % 2 else 0.015)
    out = reverb(out, 0.3, 1.2)
    L = int(total * SR)
    loop = out[:L].copy()
    loop[: n - L] += out[L:]
    return loop


def main():
    os.makedirs(OUT, exist_ok=True)
    for k in range(3):
        save(f"step{k}", step(k), 0.6)
    save("land", land(), 0.7)
    save("whoosh", whoosh(), 0.7)
    save("sigh", sigh(), 0.7)
    save("flap", flap(), 0.8)
    save("door", door(), 0.7)
    save("signal", signal_loop(), 0.5)
    save("heli", heli(), 0.8)
    save("kankan", kankan(), 0.6)
    save("crow", crow(), 0.6)
    save("wind_roof", wind_roof(26.0), 0.8)
    save("wind_fly", wind_fly(20.0), 0.7)
    save("city", city(30.0), 0.8)
    save("drone", drone(), 0.8)
    save("bgm", bgm(), 0.8)
    print("ok")


if __name__ == "__main__":
    main()
