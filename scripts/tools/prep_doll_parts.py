# -*- coding: utf-8 -*-
"""部件抠底：把分件图切出的部件 PNG 的浅色背景变透明并裁到包围盒。

用「从边界漫灌」而不是全局亮度阈值——书本内页等白色区域是内容，不能被抠掉。
用法：python3 tools/prep_doll_parts.py
"""
import os, glob
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PART_DIR = os.path.join(ROOT, "assets/Textures/doll")


def flood_bg(bright):
    """从图像边界出发漫灌近白像素 → 背景掩码。"""
    h, w = bright.shape
    seen = np.zeros_like(bright, dtype=bool)
    stack = []
    for x in range(w):
        for y in (0, h - 1):
            if bright[y, x] and not seen[y, x]:
                seen[y, x] = True; stack.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bright[y, x] and not seen[y, x]:
                seen[y, x] = True; stack.append((y, x))
    while stack:
        cy, cx = stack.pop()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and bright[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                stack.append((ny, nx))
    return seen


def dilate(m, r=2):
    out = m.copy()
    for _ in range(r):
        p = np.pad(out, 1)
        out = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
    return out


def prep(path):
    im = Image.open(path).convert("RGBA")
    a = np.array(im).astype(np.int16)
    rgb, al = a[..., :3], a[..., 3].copy()
    bright = (rgb.min(axis=2) > 235)
    bg = flood_bg(bright)
    bg = dilate(bg, 2) & bright          # 只吃背景本身，不吃内部亮色
    al[bg] = 0
    out = np.array(im).copy()
    out[..., 3] = al
    ys, xs = np.where(al > 8)
    if len(ys) == 0:
        print("  空部件：%s" % os.path.basename(path)); return
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    pad = 2
    y0 = max(0, y0 - pad); x0 = max(0, x0 - pad)
    y1 = min(out.shape[0] - 1, y1 + pad); x1 = min(out.shape[1] - 1, x1 + pad)
    crop = Image.fromarray(out[y0:y1 + 1, x0:x1 + 1].astype(np.uint8))
    crop.save(path)
    print("  %-24s %dx%d -> %dx%d  背景去除 %d px"
          % (os.path.basename(path), im.size[0], im.size[1], crop.size[0], crop.size[1], int(bg.sum())))


if __name__ == "__main__":
    for p in sorted(glob.glob(os.path.join(PART_DIR, "scholar_*.png"))):
        prep(p)
