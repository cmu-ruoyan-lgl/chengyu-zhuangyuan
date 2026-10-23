#!/usr/bin/env python3
"""合成 5 个玩法反馈音效到 assets/Sounds/（stdlib wave，零依赖）。

程序化降级路线（RISK 裁决 #17：MCP 优先但配额受限时不阻塞开发）。
16-bit PCM mono 22050Hz，单文件 < 35KB。
  fill_ok    填字正确：清脆单音（880Hz 短促衰减）
  fill_err    填字错误：低沉短音（180Hz 方波感）
  idiom_done  成语完成：上行音阶（C5→E5→G5）
  cross_ok    交叉验证：双音和声（660+990）
  level_win   通关胜利：C-E-G-C 上行琶音
"""
import math
import os
import struct
import sys
import wave

SR = 22050

def env(t, dur, attack=0.005, release=None):
    """简单攻击-衰减包络。"""
    release = release if release is not None else dur
    if t < attack:
        return t / attack
    if t > dur - release:
        return max(0.0, (dur - t) / release)
    return 1.0

def tone(dur, freqs, vol=0.5, kind="sine", slide=0.0, attack=0.005, release=None):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        total = 0.0
        for k, f in enumerate(freqs):
            fi = f * (1.0 + slide * t)
            ph = 2 * math.pi * fi * t
            if kind == "square":
                total += (1.0 if math.sin(ph) >= 0 else -1.0) / len(freqs)
            elif kind == "saw":
                total += (2.0 * ((fi * t) % 1.0) - 1.0) / len(freqs)
            else:
                total += math.sin(ph) / len(freqs)
        out.append(total * env(t, dur, attack, release) * vol)
    return out

def silence(dur):
    return [0.0] * int(SR * dur)

def mix(a, b):
    n = max(len(a), len(b))
    out = []
    for i in range(n):
        va = a[i] if i < len(a) else 0.0
        vb = b[i] if i < len(b) else 0.0
        out.append(va + vb)
    return out

def write_wav(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # 归一化防削波
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = min(1.0, 0.92 / peak)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s * gain)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print(f"  {os.path.basename(path)}  {os.path.getsize(path)}B  {len(samples)/SR:.2f}s")

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "Sounds")

    sounds = {
        # 填字正确：清脆单音，95ms
        "fill_ok.wav": tone(0.095, [880.0], vol=0.55, release=0.06),
        # 填字错误：低沉短音，150ms
        "fill_err.wav": tone(0.15, [180.0], vol=0.6, kind="square", release=0.1),
        # 成语完成：上行音阶 300ms
        "idiom_done.wav": tone(0.10, [523.25], vol=0.5, release=0.05)
            + tone(0.10, [659.25], vol=0.5, release=0.05)
            + tone(0.12, [783.99], vol=0.55, release=0.08),
        # 交叉验证：双音和声 200ms
        "cross_ok.wav": tone(0.2, [660.0, 990.0], vol=0.42, release=0.12),
        # 通关：C-E-G-C 琶音 650ms
        "level_win.wav": tone(0.12, [523.25], vol=0.5, release=0.05)
            + tone(0.12, [659.25], vol=0.5, release=0.05)
            + tone(0.12, [783.99], vol=0.5, release=0.05)
            + tone(0.3, [1046.5], vol=0.6, release=0.22),
    }

    for name, samples in sounds.items():
        write_wav(os.path.join(out_dir, name), samples)
    print(f"完成：{len(sounds)} 个音效 → {out_dir}")

if __name__ == "__main__":
    sys.exit(main())
