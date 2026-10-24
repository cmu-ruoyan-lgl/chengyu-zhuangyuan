# -*- coding: utf-8 -*-
"""测量合成图（scholar.png）的剪影剖面，输出人体比例分区，用于骨骼装配定位。"""
import sys, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets/Textures/scholar.png")

im = Image.open(path).convert("RGBA")
a = np.array(im)
mask = a[..., 3] > 24
H, W = mask.shape
ys, xs = np.where(mask)
y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
fh, fw = y1 - y0 + 1, x1 - x0 + 1
print("image=%dx%d  figure bbox=(%d,%d)-(%d,%d)  %dx%d" % (W, H, x0, y0, x1, y1, fw, fh))

rows = mask.sum(axis=1)
print("\n逐行宽度（按身高的 2% 采样）：")
for i in range(0, 51):
    p = i / 50.0
    r = y0 + int(p * (fh - 1))
    w = rows[r]
    bar = "#" * int(40 * w / max(1, rows.max()))
    print("  %3d%%  row=%3d  w=%3d  %s" % (int(p * 100), r, w, bar))

# 找颈线：上半部分（20%~48%）的行宽局部最小
seg = rows[y0 + int(0.20 * fh): y0 + int(0.48 * fh)]
neck_rel = int(np.argmin(seg))
neck = y0 + int(0.20 * fh) + neck_rel
print("\n颈线 row=%d (身高的 %.1f%%)，该行宽 %d" % (neck, 100.0 * (neck - y0) / fh, rows[neck]))
print("头部区域: row %d..%d (高 %d)" % (y0, neck, neck - y0))
hm = mask[y0:neck + 1]
hx = np.where(hm.any(axis=0))[0]
print("头部横向: %d..%d (宽 %d)" % (hx.min(), hx.max(), hx.max() - hx.min() + 1))
