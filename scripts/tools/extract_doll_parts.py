# -*- coding: utf-8 -*-
"""从「纸娃娃分件图」自动切出骨骼部件，并用 ZNCC 模板匹配把每个部件
对回原合成图（assets/Textures/scholar.png），解出它在真实姿态中的
位置/缩放，输出可直接写进 config.json 的锚点表。

用法：
  python3 tools/extract_doll_parts.py <sheet.png>            # 诊断
  python3 tools/extract_doll_parts.py <sheet.png> --emit     # 切图 + 输出锚点
"""
import sys, os, json
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMPOSITE = os.path.join(ROOT, "assets/Textures/scholar.png")
OUT_DIR = os.path.join(ROOT, "assets/Textures/doll")


def alpha_mask(path, crop_bottom=0.06):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    im = im.crop((0, 0, w, int(h * (1 - crop_bottom))))   # 去水印带
    a = np.array(im)
    rgb, al = a[..., :3].astype(np.int16), a[..., 3]
    bright = (rgb.min(axis=2) > 235)
    return (al > 24) & (~bright), im


def components(mask, min_area=1500):
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    out = []
    for y, x in np.argwhere(mask):
        if lab[y, x]:
            continue
        cur = lab.max() + 1 if out else 1
        stack = [(y, x)]
        lab[y, x] = cur
        minx = maxx = x; miny = maxy = y; area = 0
        while stack:
            cy, cx = stack.pop()
            area += 1
            minx = min(minx, cx); maxx = max(maxx, cx)
            miny = min(miny, cy); maxy = max(maxy, cy)
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = cur
                    stack.append((ny, nx))
        if area >= min_area:
            out.append(dict(area=area, x=minx, y=miny, w=maxx - minx + 1, h=maxy - miny + 1,
                            lab=cur, mask=(lab == cur)))
    return out


def classify(comps):
    """按几何启发式把连通域归类成骨骼部件（面积/长宽比/画面位置）。"""
    items = []
    for c in comps:
        ar = c["w"] / max(1, c["h"])
        cy = (c["y"] + c["h"] / 2)
        items.append((c, ar, cy))
    items.sort(key=lambda t: -t[0]["area"])
    named = {}
    for c, ar, cy in items:
        named.setdefault("_all", []).append(c)
    allc = sorted(named["_all"], key=lambda c: -c["area"])
    head = allc[0]
    rest = [c for c in allc if c is not head]
    # 躯干：剩下的里面最高（h/w 最大且面积大）
    torso = max(rest, key=lambda c: c["area"])
    rest = [c for c in rest if c is not torso]
    # 小木凳：最靠下（cy 最大）且偏宽
    chair = max(rest, key=lambda c: (c["y"] + c["h"]))
    rest = [c for c in rest if c is not chair]
    # 书：剩下的里面最宽（w/h 最大）
    book = max(rest, key=lambda c: c["w"] / max(1, c["h"]))
    rest = [c for c in rest if c is not book]
    arms = sorted(rest, key=lambda c: c["x"])   # 左臂（画面靠左）在前
    return dict(head=head, torso=torso, chair=chair, book=book,
                arms=arms, page=(arms[2] if len(arms) > 2 else None))


def box_integral(img):
    """积分图（含零填充行/列），便于 O(1) 窗口求和。"""
    s = np.pad(img.astype(np.float64), ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    return s


def zncc_match(composite, part_mask):
    """在 composite 里滑动 part_mask，返回最佳 (score, dy, dx)。ZNCC。"""
    H, W = composite.shape
    ph, pw = part_mask.shape
    if ph > H or pw > W:
        part_mask = np.array(Image.fromarray((part_mask * 255).astype(np.uint8))
                             .resize((min(W, pw), min(H, ph)), Image.BILINEAR)) > 127
        ph, pw = part_mask.shape
    P = part_mask.astype(np.float64)
    n = ph * pw
    p_mean = P.mean()
    p_std = P.std()
    if p_std < 1e-6:
        return -1, 0, 0

    C = composite.astype(np.float64)
    Fh, Fw = H + ph, W + pw
    # 互相关 R[dy,dx] = sum_n C[n+(dy,dx)] * P[n]（零填充避免环绕）
    corr = np.fft.irfft2(np.fft.rfft2(C, s=(Fh, Fw))
                         * np.conj(np.fft.rfft2(P, s=(Fh, Fw))), s=(Fh, Fw))
    corr = corr[:H - ph + 1, :W - pw + 1]

    ic = box_integral(C)
    ic2 = box_integral(C * C)

    def win(integ, y0, x0, h, w):
        return (integ[y0 + h, x0 + w] - integ[y0, x0 + w]
                - integ[y0 + h, x0] + integ[y0, x0])

    sumC = win(ic, 0, 0, H, W)  # 占位，真正需要逐窗口：用滑动积分
    # 逐窗口求和（用积分图向量化）
    ys = np.arange(0, H - ph + 1)
    xs = np.arange(0, W - pw + 1)
    # sum over window for all (y,x)：用四个角采样
    def win_all(integ):
        A = integ[np.ix_(ys + ph, xs + pw)]
        B = integ[np.ix_(ys, xs + pw)]
        Cc = integ[np.ix_(ys + ph, xs)]
        D = integ[np.ix_(ys, xs)]
        return A - B - Cc + D

    sC = win_all(ic)
    sC2 = win_all(ic2)
    meanC = sC / n
    varC = np.maximum(sC2 / n - meanC ** 2, 0)
    stdC = np.sqrt(varC)
    with np.errstate(divide="ignore", invalid="ignore"):
        score = (corr - n * p_mean * meanC) / np.maximum(p_std * stdC * n, 1e-3)
    score = np.nan_to_num(score, nan=-1.0)
    score[stdC < 0.02] = -1      # 窗口几乎空白 → 无意义
    score = np.clip(score, -1.0, 1.0)
    idx = np.unravel_index(np.nanargmax(score), score.shape)
    return float(score[idx]), int(idx[0]), int(idx[1])


def main():
    args = sys.argv[1:]
    path = args[0]
    emit = "--emit" in args
    mask, im = alpha_mask(path)
    comps = components(mask)
    parts = classify(comps)

    cmask, cim = alpha_mask(COMPOSITE, crop_bottom=0.0)
    CH, CW = cmask.shape
    print("composite=%dx%d  parts=%d" % (CW, CH, len(comps)))

    result = {}
    for name, c in (("head", parts["head"]), ("torso", parts["torso"]),
                    ("book", parts["book"]), ("chair", parts["chair"])):
        best = (-2, None, 0, 0)
        for s in np.arange(0.35, 1.45, 0.05):
            w = max(4, int(c["w"] * s)); h = max(4, int(c["h"] * s))
            pm = np.array(Image.fromarray((c["mask"] * 255).astype(np.uint8))
                          .resize((w, h), Image.BILINEAR)) > 127
            sc, dy, dx = zncc_match(cmask, pm)
            if sc > best[0]:
                best = (sc, float(s), dx, dy, w, h)
        sc, s, dx, dy, w, h = best
        print("  %-6s score=%.3f scale=%.2f pos=(%4d,%4d) size=%4dx%4d  cx=%.2f cy=%.2f"
              % (name, sc, s, dx, dy, w, h, (dx + w / 2) / CW, (dy + h / 2) / CH))
        result[name] = dict(score=round(sc, 3), x=round(dx / CW, 4), y=round(dy / CH, 4),
                            w=round(w / CW, 4), h=round(h / CH, 4))
    for i, c in enumerate(parts["arms"][:2]):
        best = (-2, None, 0, 0)
        for s in np.arange(0.35, 1.45, 0.05):
            w = max(4, int(c["w"] * s)); h = max(4, int(c["h"] * s))
            pm = np.array(Image.fromarray((c["mask"] * 255).astype(np.uint8))
                          .resize((w, h), Image.BILINEAR)) > 127
            sc, dy, dx = zncc_match(cmask, pm)
            if sc > best[0]:
                best = (sc, float(s), dx, dy, w, h)
        sc, s, dx, dy, w, h = best
        nm = "arm_%s" % ("far" if i == 0 else "near")
        print("  %-6s score=%.3f scale=%.2f pos=(%4d,%4d) size=%4dx%4d  cx=%.2f cy=%.2f"
              % (nm, sc, s, dx, dy, w, h, (dx + w / 2) / CW, (dy + h / 2) / CH))
        result[nm] = dict(score=round(sc, 3), x=round(dx / CW, 4), y=round(dy / CH, 4),
                          w=round(w / CW, 4), h=round(h / CH, 4))

    if emit:
        os.makedirs(OUT_DIR, exist_ok=True)
        for name, c in (("head", parts["head"]), ("torso", parts["torso"]),
                        ("book", parts["book"]), ("chair", parts["chair"])):
            crop = im.crop((c["x"], c["y"], c["x"] + c["w"], c["y"] + c["h"]))
            crop.save(os.path.join(OUT_DIR, "scholar_%s.png" % name))
        for i, c in enumerate(parts["arms"][:2]):
            nm = "arm_far" if i == 0 else "arm_near"
            crop = im.crop((c["x"], c["y"], c["x"] + c["w"], c["y"] + c["h"]))
            crop.save(os.path.join(OUT_DIR, "scholar_%s.png" % nm))
        with open(os.path.join(OUT_DIR, "anchors.json"), "w") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print("已输出部件到 %s" % OUT_DIR)
    return result


if __name__ == "__main__":
    main()
