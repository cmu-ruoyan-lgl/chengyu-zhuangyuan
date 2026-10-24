# -*- coding: utf-8 -*-
"""把 PNG 的 alpha 剪影渲染成 ASCII，便于无法看图时判断形状/姿态。"""
import sys, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def ascii_mask(mask, cols=52):
    ys, xs = np.where(mask)
    if len(ys) == 0:
        return "(empty)"
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    m = mask[y0:y1 + 1, x0:x1 + 1]
    h, w = m.shape
    rows = max(3, int(cols * h / max(1, w) * 0.5))
    ri = (np.linspace(0, h - 1, rows)).astype(int)
    ci = (np.linspace(0, w - 1, cols)).astype(int)
    sub = m[np.ix_(ri, ci)]
    out = []
    for r in range(rows):
        out.append("".join("#" if sub[r, c] else "." for c in range(cols)))
    return "\n".join(out)


def show(path, cols=52, crop_bottom=0.0, label=None):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    if crop_bottom:
        im = im.crop((0, 0, w, int(h * (1 - crop_bottom))))
    a = np.array(im)
    rgb, al = a[..., :3].astype(np.int16), a[..., 3]
    bright = (rgb.min(axis=2) > 235)
    mask = (al > 24) & (~bright)
    print("=== %s (%dx%d) ===" % (label or os.path.basename(path), w, h))
    print(ascii_mask(mask, cols))
    print()


if __name__ == "__main__":
    for p in sys.argv[1:]:
        show(p)
