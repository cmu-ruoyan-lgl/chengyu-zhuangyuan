# -*- coding: utf-8 -*-
"""骨骼装配拟合：以合成图（scholar.png）剪影为真值，自动优化各部件的
位置 / 缩放，使装配后的剪影与原图 IoU 最大。

输出：assets/Textures/doll/rig_anchors.json（分数坐标，可直接进 config.json）
用法：python3 tools/fit_doll_rig.py [--iters N]
"""
import os, sys, json, math
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMPOSITE = os.path.join(ROOT, "assets/Textures/scholar.png")
PART_DIR = os.path.join(ROOT, "assets/Textures/doll")
OUT = os.path.join(ROOT, ".tmp", "rig_anchors.json")
RES = 160          # 优化分辨率（速度与精度折中）
N = 512            # 合成图基准尺寸


def mask_of(path, crop_bottom=0.0):
    im = Image.open(path).convert("RGBA")
    if crop_bottom:
        w, h = im.size
        im = im.crop((0, 0, w, int(h * (1 - crop_bottom))))
    a = np.array(im)
    al = a[..., 3]
    # 部件已抠底（背景 alpha=0），直接用 alpha；合成图同样是透明底
    return al > 24


def to_res(mask, res=RES):
    """按 bbox 裁剪后缩放到 res 网格，返回（子掩码, bbox）。"""
    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    sub = mask[y0:y1 + 1, x0:x1 + 1]
    h, w = sub.shape
    # 保持长宽比放进 res×res
    s = res / max(h, w)
    nw, nh = max(1, int(round(w * s))), max(1, int(round(h * s)))
    im = Image.fromarray((sub * 255).astype(np.uint8)).resize((nw, nh), Image.BILINEAR)
    arr = np.array(im) > 127
    return arr, (w, h)


def place(part_mask, cx, cy, scale, ow, oh, res=RES):
    """把部件放到 res 网格：scale 为相对合成图基准的比例。
    注意：part_mask 已按长边缩到 res，目标像素尺寸必须用**原始包围盒**尺寸算，
    否则会被二次缩小。"""
    tw = max(1, int(round(ow * scale * res / N)))
    th = max(1, int(round(oh * scale * res / N)))
    im = Image.fromarray((part_mask * 255).astype(np.uint8)).resize((tw, th), Image.BILINEAR)
    arr = np.array(im) > 127
    px = int(round(cx * res / N - tw / 2))
    py = int(round(cy * res / N - th / 2))
    canvas = np.zeros((res, res), dtype=bool)
    x0, y0 = max(0, px), max(0, py)
    x1, y1 = min(res, px + tw), min(res, py + th)
    if x1 > x0 and y1 > y0:
        canvas[y0:y1, x0:x1] |= arr[y0 - py:y1 - py, x0 - px:x1 - px]
    return canvas


def iou(union_mask, target):
    inter = np.logical_and(union_mask, target).sum()
    u = np.logical_or(union_mask, target).sum()
    return inter / max(1, u)


def main():
    iters = 6
    if "--iters" in sys.argv:
        iters = int(sys.argv[sys.argv.index("--iters") + 1])

    cmask = mask_of(COMPOSITE)
    target = np.array(Image.fromarray((cmask * 255).astype(np.uint8))
                      .resize((RES, RES), Image.BILINEAR)) > 127

    names = ["chair", "torso", "head", "book", "arm_far", "arm_near"]
    parts = {}
    for nm in names:
        p = os.path.join(PART_DIR, "scholar_%s.png" % nm)
        if not os.path.exists(p):
            print("缺少部件 %s" % p); return
        m, (w, h) = to_res(mask_of(p))
        parts[nm] = dict(mask=m, ow=w, oh=h)

    # 解剖先验（读合成图剪影剖面得出）+ 有界微调窗口，防止优化把部件放飞
    PRIOR = {
        "chair":   dict(cx=250, cy=460, s=0.85),
        "torso":   dict(cx=228, cy=246, s=0.62),
        "head":    dict(cx=219, cy=102, s=0.60),
        "book":    dict(cx=287, cy=322, s=0.55),
        "arm_far": dict(cx=154, cy=266, s=0.50),
        "arm_near": dict(cx=356, cy=272, s=0.55),
    }
    BOUND = dict(cx=48, cy=48, s=0.18)   # 允许偏离先验的幅度
    init = {k: dict(v) for k, v in PRIOR.items()}
    order = ["torso", "head", "chair", "book", "arm_far", "arm_near"]

    def part_masks(params, skip=None):
        out = []
        for nm in names:
            if nm == skip:
                continue
            p = params[nm]
            out.append(place(parts[nm]["mask"], p["cx"], p["cy"], p["s"],
                             parts[nm]["ow"], parts[nm]["oh"]))
        return out

    def union_of(params, skip=None):
        u = np.zeros((RES, RES), dtype=bool)
        for m in part_masks(params, skip):
            u |= m
        return u

    TAREA = max(1, int(target.sum()))

    def score(params):
        ms = part_masks(params)
        u = np.zeros((RES, RES), dtype=bool)
        for m in ms:
            u |= m
        tp = int(np.logical_and(u, target).sum())
        # 关键：每个部件单独为「溢出剪影」的部分买单（部件互相重叠不能互相掩盖）
        bleed = sum(int(np.logical_and(m, ~target).sum()) for m in ms)
        sc = tp / TAREA - 1.0 * bleed / TAREA
        # 解剖次序惩罚：头在躯干上、凳在最下
        pen = 0.0
        if params["head"]["cy"] > params["torso"]["cy"] - 40:
            pen += 0.10
        if params["chair"]["cy"] < params["torso"]["cy"] + 40:
            pen += 0.10
        return sc - pen

    def show_overlay(params, tag="装配"):
        """叠加对比：# = 重合，o = 装配件溢出原剪影，x = 原剪影未覆盖。"""
        u = union_of(params)
        ys, xs = np.where(np.logical_or(u, target))
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        rows = 34
        ri = np.linspace(y0, y1 - 1, rows).astype(int)
        ci = np.linspace(x0, x1 - 1, 52).astype(int)
        a = u[np.ix_(ri, ci)]
        t = target[np.ix_(ri, ci)]
        print("=== %s叠加（# 重合 / o 溢出 / x 空缺）===" % tag)
        for r in range(rows):
            line = []
            for c in range(52):
                line.append("#" if (a[r, c] and t[r, c]) else ("o" if a[r, c] else ("x" if t[r, c] else ".")))
            print("".join(line))
        tp = int(np.logical_and(u, target).sum())
        bl = int(np.logical_and(u, ~target).sum())
        fn = int(np.logical_and(~u, target).sum())
        print("覆盖 %.1f%% / 溢出 %.1f%% / 空缺 %.1f%%  (目标像素 %d)"
              % (100.0 * tp / TAREA, 100.0 * bl / TAREA, 100.0 * fn / TAREA, TAREA))

    if "--show" in sys.argv:
        # 权威来源是已落库的 config.json（真正生效的锚点），其次才是拟合输出
        params = {k: dict(v) for k, v in PRIOR.items()}
        loaded = None
        cfg_path = os.path.join(ROOT, "assets/data/config.json")
        if os.path.exists(cfg_path):
            loaded = json.load(open(cfg_path))["ui"]["scholar"]["parts"]
        elif os.path.exists(OUT):
            loaded = json.load(open(OUT))["parts"]
        if loaded:
            for nm in names:
                q = loaded.get(nm)
                if q:
                    params[nm] = dict(cx=(q["x"] + q["w"] / 2) * N,
                                      cy=(q["y"] + q["h"] / 2) * N,
                                      s=q["w"] * N / parts[nm]["ow"])
        show_overlay(params)
        return

    best = score(init)
    print("初始 score=%.3f" % best)
    params = {k: dict(v) for k, v in init.items()}

    for it in range(iters):
        for nm in order:
            p = params[nm]
            steps = [40, 20, 10, 5, 2] if it == 0 else [16, 8, 4, 2]
            for step in steps:
                improved = True
                while improved:
                    improved = False
                    for key, ds in (("cx", step), ("cy", step), ("s", step / 512.0)):
                        for sign in (1, -1):
                            old = p[key]
                            p[key] = old + sign * ds
                            lim = BOUND[key]
                            if abs(p[key] - PRIOR[nm][key]) > lim:
                                p[key] = old; continue
                            sc = score(params)
                            if sc > best + 1e-6:
                                best = sc; improved = True
                            else:
                                p[key] = old
        print("  iter %d  IoU=%.3f" % (it + 1, best))

    print("\n最终 IoU=%.3f" % best)
    out = {}
    for nm in names:
        p = params[nm]
        w, h = parts[nm]["ow"], parts[nm]["oh"]
        out[nm] = dict(cx=round(p["cx"] / N, 4), cy=round(p["cy"] / N, 4),
                       w=round(w * p["s"] / N, 4), h=round(h * p["s"] / N, 4))
        print("  %-9s cx=%.3f cy=%.3f  w=%.3f h=%.3f  (scale %.2f)"
              % (nm, out[nm]["cx"], out[nm]["cy"], out[nm]["w"], out[nm]["h"], p["s"]))
    with open(OUT, "w") as f:
        json.dump(dict(iou=round(best, 4), parts=out), f, ensure_ascii=False, indent=2)
    print("已写入 %s" % OUT)

    # 打印装配结果 ASCII，便于核对
    u = union_of(params)
    ys, xs = np.where(u)
    print("\n=== 装配剪影 ===")
    sub = u[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = sub.shape
    rows = 34
    ri = np.linspace(0, h - 1, rows).astype(int)
    ci = np.linspace(0, w - 1, 52).astype(int)
    s2 = sub[np.ix_(ri, ci)]
    for r in range(rows):
        print("".join("#" if s2[r, c] else "." for c in range(52)))


if __name__ == "__main__":
    main()
