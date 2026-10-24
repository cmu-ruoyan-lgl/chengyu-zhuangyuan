#!/usr/bin/env python3
"""书童序列帧图集流水线：视频/帧目录/胶片图 → 透明精灵表（atlas PNG + sprite.json）。

用法（在项目根执行）：
  # A. 视频转帧（固定机位，共享裁窗对齐）
  python3 scripts/tools/scholar_spritesheet.py --video .tmp/anim.mp4 \
      [--fps 12] [--frame-max 320] [--flip-interval 5] \
      [--out assets/sprites/scholar]

  # B. 胶片图切分（AI 单图多姿态网格，逐格 bbox 中心对齐）
  python3 scripts/tools/scholar_spritesheet.py --strip .tmp/filmstrip.png --grid 4x3 \
      [--frame-max 320] [--flip-interval 5] [--out assets/sprites/scholar]

流程（每一步都可离线复跑，幂等覆盖输出目录）：
  1. 输入解析：ffmpeg 抽帧 / 帧目录 / 网格切分
  2. 逐帧从边界漫灌抠底（S10-6 教训：禁止全局亮度阈值，会抠掉书页白色）
  3. 只保留最大连通不透明分量（角色本体），顺带清除漂浮的水印/格线碎片
  4. 对齐：视频走全帧 union bbox 共享裁窗；胶片图走逐格 bbox 居中到同尺寸画布
  5. 循环缝修剪：尾部帧与首帧差异大时丢弃（上限 25%）
  6. 相邻近重复帧去重，收敛到目标帧数（idle 呼吸帧保真度优先）
  7. 翻页检测（帧间差分峰值）→ 翻页帧短时长、idle 帧均摊剩余时长，
     总时长 = --flip-interval 秒（与 config ui.scholar.flip_interval 对齐）
  8. shelf 装箱到 POT atlas，写 sprite.json（TexturePacker Hash + sprite-gen
     animations 数组，repeat=0 无限循环）
  9. stdout 末尾输出一行 SUMMARY JSON（帧数/体积/kudos_local_frame 等，
     供 config 填写与验收留档）

依赖：ffmpeg（PATH）、Pillow、numpy。
"""
import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

# 背景色容差：视频背景为纯色薄荷绿，容差小一点避免吃掉浅色书页
BG_TOL = 26
# 相邻帧去重阈值（归一化均方差）：低于它视为同一姿态
DEDUP_MSE = 0.0012
# 循环缝：尾帧与首帧 MSE 高于此值则继续丢尾帧
SEAM_MSE = 0.004
# 翻页窗口时长（每帧毫秒）
FLIP_FRAME_MS = 70


def sh(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def extract_frames(video, fps, tmpdir):
    """ffmpeg 抽帧为 PNG，返回按序文件列表。"""
    out = Path(tmpdir) / "f_%04d.png"
    sh(["ffmpeg", "-y", "-i", str(video), "-vf", f"fps={fps}", str(out)])
    return sorted((Path(tmpdir)).glob("f_*.png"))


def flood_cutout(img):
    """从边界漫灌抠底：返回 RGBA numpy 数组（背景 alpha=0）。

    以四边像素的中位色为背景色，BFS 所有与背景色相近的边界种子；
    再做连通域标记，仅保留最大的不透明分量（角色），其余全部清透
    （可清除贴边水印/噪点碎片）。
    """
    a = np.asarray(img.convert("RGB"), dtype=np.int16)
    h, w, _ = a.shape
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)

    dist = np.abs(a - bg).sum(axis=2)
    near = dist < BG_TOL * 3  # 每通道各 tol

    # BFS 漫灌：只从边界出发，避免角色内部同色区域（如衣服）被误抠
    from collections import deque
    visited = np.zeros((h, w), dtype=bool)
    bgmask = np.zeros((h, w), dtype=bool)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near[y, x] and not visited[y, x]:
                visited[y, x] = True
                bgmask[y, x] = True
                dq.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near[y, x] and not visited[y, x]:
                visited[y, x] = True
                bgmask[y, x] = True
                dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
            if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not visited[ny, nx]:
                visited[ny, nx] = True
                bgmask[ny, nx] = True
                dq.append((ny, nx))

    fg = ~bgmask
    # 最大连通分量（4 邻域，两遍扫描法足够快且无递归深度问题）
    labels = np.zeros((h, w), dtype=np.int32)
    cur = 0
    best, best_size = 0, 0
    for sy in range(h):
        row = fg[sy]
        if not row.any():
            continue
        for sx in range(w):
            if row[sx] and labels[sy, sx] == 0:
                cur += 1
                size = 0
                stack = [(sy, sx)]
                labels[sy, sx] = cur
                while stack:
                    y, x = stack.pop()
                    size += 1
                    for ny, nx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
                        if 0 <= ny < h and 0 <= nx < w and fg[ny, nx] and labels[ny, nx] == 0:
                            labels[ny, nx] = cur
                            stack.append((ny, nx))
                if size > best_size:
                    best, best_size = cur, size
    if best == 0:
        return None
    keep = labels == best

    rgba = np.asarray(img.convert("RGBA")).copy()
    rgba[..., 3] = np.where(keep, 255, 0)
    return rgba


def opaque_bbox(rgba, pad=6):
    ys, xs = np.where(rgba[..., 3] > 8)
    if len(xs) == 0:
        return None
    x0, x1 = xs.min(), xs.max()
    y0, y1 = ys.min(), ys.max()
    return (max(0, x0 - pad), max(0, y0 - pad),
            x1 + pad + 1, y1 + pad + 1)


def mse(a, b):
    d = a.astype(np.float32) - b.astype(np.float32)
    return float((d * d).mean() / (255.0 * 255.0))


def slice_strip(path, cols, rows):
    """胶片图按等分网格切分，返回 PIL 帧列表（行优先顺序）。"""
    im = Image.open(path).convert("RGB")
    cw, ch = im.width / cols, im.height / rows
    out = []
    for r in range(rows):
        for c in range(cols):
            cell = im.crop((round(c * cw), round(r * ch),
                            round((c + 1) * cw), round((r + 1) * ch)))
            out.append(cell)
    return out


def bake_from_base(base_png, n, loop_s, frame_max, cfg):
    """零积分烘焙模式：用现有 scholar.png + 翻页/呼吸/轻摇编排直接渲染帧。

    动效参数与 config ui.scholar（image 模式）语义一致：
      breathe_lift/breathe_period：整体上下浮动；sway_degrees：绕椅底轻摇；
      image_page.*：书页贴片位置与翻页角度（rotate 为负值，0°→rotate）。
    呼吸/轻摇按「整循环整数周期」重整（保证循环缝无缝，周期取最接近值）；
    翻页发生在循环 36%~62% 区间，越过中点后的下一帧为 kudos 帧。
    返回 (frames, kudos_frame, flip_set)。
    """
    import math
    from PIL import ImageDraw
    base = Image.open(base_png).convert("RGBA")
    S = base.width  # 512，正方形
    px = cfg["page"]

    # 书页贴片（与 home.lua image 模式同参数：米白底 + 浅棕描边 + 圆角）
    pw, ph = max(2, round(px["w"] * S)), max(2, round(px["h"] * S))
    patch = Image.new("RGBA", (pw * 2, ph * 2), (0, 0, 0, 0))
    ImageDraw.Draw(patch).rounded_rectangle(
        [0, 0, pw * 2 - 1, ph * 2 - 1], 12,
        fill=(255, 252, 240, 235), outline=(214, 190, 152, 200), width=3)
    patch = patch.resize((pw, ph), Image.LANCZOS)

    # 支点居中旋转画布：贴片绕 (org.x, org.y)（比例坐标）旋转后，
    # 支点精确落在 SQ 画布中心，合成时支点对齐书脊即可
    org = (float(px["origin"][0]), float(px["origin"][1]))
    SQ = 2 * (math.ceil(math.hypot(pw, ph)) + 4)
    pcv = Image.new("RGBA", (SQ, SQ), (0, 0, 0, 0))
    pcv.paste(patch, (round(SQ / 2 - org[0] * pw), round(SQ / 2 - org[1] * ph)), patch)
    spine_x = px["x"] * S + org[0] * pw    # 书脊（画布坐标）
    spine_y = px["y"] * S + org[1] * ph

    # 呼吸/轻摇整循环整数周期（无缝），取最接近配置值的整 cycles
    bob_cycles = max(1, round(loop_s / cfg["breathe_period"]))
    sway_cycles = max(1, round(loop_s / (cfg["breathe_period"] * 1.3)))
    flip_from, flip_to = 0.36, 0.62

    frames, kudos_frame, flip_set = [], n - 1, set()
    for i in range(n):
        t = i / n
        bob = -cfg["breathe_lift"] * (0.5 - 0.5 * math.cos(2 * math.pi * t * bob_cycles))
        sway = cfg["sway_degrees"] * math.sin(2 * math.pi * t * sway_cycles)
        body = base.rotate(sway, center=(0.45 * S, 0.95 * S), resample=Image.BICUBIC)
        canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        canvas.paste(body, (0, round(bob)), body)
        if flip_from <= t <= flip_to:
            prog = (t - flip_from) / (flip_to - flip_from)
            ease = prog * prog * (3 - 2 * prog)  # smoothstep，与 easeInOut 近似
            rot = pcv.rotate(px["rotate"] * ease, resample=Image.BICUBIC)
            canvas.alpha_composite(rot, (round(spine_x - SQ / 2),
                                         round(spine_y - SQ / 2 + bob)))
            flip_set.add(i)
            if prog >= 0.5 and kudos_frame == n - 1:
                kudos_frame = min(i + 1, n - 1)  # 首次越过中点后的下一帧
        if frame_max and S != frame_max:
            canvas = canvas.resize((frame_max, frame_max), Image.LANCZOS)
        frames.append(canvas)
    return frames, kudos_frame, flip_set


def pack_shelf(frames):
    """简单 shelf 装箱到 POT 画布，返回 (canvas, placements)。"""
    side = 512
    while True:
        x = y = shelf_h = 0
        placements = []
        for im in frames:
            if x + im.width > side:
                x = 0
                y += shelf_h + 2
                shelf_h = 0
            placements.append((x, y))
            x += im.width + 2
            shelf_h = max(shelf_h, im.height)
        if y + shelf_h <= side or side >= 2048:
            canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            for im, (px, py) in zip(frames, placements):
                canvas.paste(im, (px, py))
            return canvas, placements, side
        side *= 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", help="输入视频 mp4（固定机位：共享裁窗对齐）")
    ap.add_argument("--frames-dir", help="输入帧目录（PNG 按文件名排序，固定机位）")
    ap.add_argument("--strip", help="输入胶片图 PNG（配合 --grid，逐格中心对齐）")
    ap.add_argument("--grid", default="4x3", help="胶片图网格 列x行，默认 4x3")
    ap.add_argument("--from-base", nargs="?", const="assets/Textures/scholar.png",
                    help="零积分烘焙：以现有整图为底渲染帧（默认 assets/Textures/scholar.png）")
    ap.add_argument("--frames", type=int, default=24, help="烘焙模式帧数")
    ap.add_argument("--fps", type=float, default=12)
    ap.add_argument("--frame-max", type=int, default=320,
                    help="单帧最长边（config ui.scholar.sprite.width 对齐）")
    ap.add_argument("--flip-interval", type=float, default=5,
                    help="循环总时长秒数 = config ui.scholar.flip_interval")
    ap.add_argument("--max-frames", type=int, default=20)
    ap.add_argument("--out", default="assets/sprites/scholar")
    args = ap.parse_args()

    tmpdir = tempfile.mkdtemp(prefix="scholar_sheet_")
    try:
        strip_mode = bool(args.strip)
        baked = None
        if args.from_base:
            # 零积分烘焙：动效参数直接读 config.json（与运行时同源）
            conf = json.loads(Path("assets/data/config.json").read_text("utf-8"))
            sc = conf.get("ui", {}).get("scholar", {})
            page = sc.get("image_page", {})
            page.setdefault("x", 0.66); page.setdefault("y", 0.505)
            page.setdefault("w", 0.155); page.setdefault("h", 0.195)
            page.setdefault("origin", [0.08, 0.95]); page.setdefault("rotate", -118)
            cfg = {
                "page": page,
                "breathe_lift": sc.get("breathe_lift", 4),
                "breathe_period": sc.get("breathe_period", 3.4),
                "sway_degrees": sc.get("sway_degrees", 0.8),
            }
            flip_interval = sc.get("flip_interval", args.flip_interval)
            baked = bake_from_base(args.from_base, args.frames, flip_interval,
                                   args.frame_max, cfg)
            print(f"[sheet] 烘焙 {args.frames} 帧（from-base: {args.from_base}）")
            frames, kudos_frame, flip_idx = baked[0], baked[1], set(baked[2])
            n = len(frames)
            arr = [np.asarray(f) for f in frames]
        elif args.video:
            files = extract_frames(args.video, args.fps, tmpdir)
        elif args.frames_dir:
            files = sorted(Path(args.frames_dir).glob("*.png"))
        elif strip_mode:
            files = slice_strip(args.strip, *(int(v) for v in args.grid.lower().split("x")))
        else:
            ap.error("需要 --video / --frames-dir / --strip 之一")
        if baked is None:
            if len(files) < 6:
                sys.exit(f"帧数过少（{len(files)}），输入疑似失败")
            print(f"[sheet] 输入 {len(files)} 帧" + ("（胶片图切分）" if strip_mode else ""))

            # 抠底 + 只留角色分量
            cut = []
            for f in files:
                r = flood_cutout(f if strip_mode else Image.open(f))
                if r is None:
                    print(f"[sheet] 警告：第 {len(cut)+1} 帧无前景，跳过")
                    continue
                cut.append(r)
            if len(cut) < 6:
                sys.exit("抠底后有效帧不足")
            cov = sum(float((r[..., 3] > 8).mean()) for r in cut) / len(cut)
            print(f"[sheet] 抠底完成 {len(cut)} 帧，平均前景覆盖率 {cov:.1%}")

            if strip_mode:
                # 胶片图：逐格 bbox，统一缩放后居中到同尺寸方画布（中心对齐）
                boxes = [opaque_bbox(r, pad=2) for r in cut]
                boxes = [b for b in boxes if b]
                maxside = max(max(b[2] - b[0], b[3] - b[1]) for b in boxes)
                scale = min(1.0, args.frame_max / maxside)
                canvas_side = max(2, int(maxside * scale) // 2 * 2)
                frames = []
                for r, b in zip(cut, boxes):
                    im = Image.fromarray(r).crop(b)
                    im = im.resize((max(1, round(im.width * scale)),
                                    max(1, round(im.height * scale))), Image.LANCZOS)
                    cv = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
                    cv.paste(im, ((canvas_side - im.width) // 2,
                                  (canvas_side - im.height) // 2))
                    frames.append(cv)
                print(f"[sheet] 中心对齐画布 {canvas_side}px")
            else:
                # 视频/帧目录：union bbox 共享裁窗（帧间硬对齐，动作不跳位）
                boxes = [opaque_bbox(r) for r in cut]
                boxes = [b for b in boxes if b]
                x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
                x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
                win = (x0, y0, x1, y1)
                scale = args.frame_max / max(win[2] - win[0], win[3] - win[1])
                if scale > 1.0:
                    scale = 1.0
                frames = []
                for r in cut:
                    im = Image.fromarray(r).crop(win)
                    if scale < 1.0:
                        im = im.resize((max(1, round(im.width * scale)),
                                        max(1, round(im.height * scale))), Image.LANCZOS)
                    frames.append(im)
                print(f"[sheet] 裁窗 {win} → {frames[0].size}")

            # 循环缝修剪：尾帧接近首帧才好无缝循环
            arr = [np.asarray(f) for f in frames]
            trim_cap = len(arr) // 4
            trimmed = 0
            while len(arr) > 8 and trimmed < trim_cap and mse(arr[-1], arr[0]) > SEAM_MSE:
                arr.pop(); frames.pop(); trimmed += 1
            print(f"[sheet] 循环缝修剪 {trimmed} 帧，缝 MSE={mse(arr[-1], arr[0]):.5f}")

            # 相邻去重（保护呼吸微动：阈值很低）
            keep = [0]
            for i in range(1, len(arr)):
                if mse(arr[i], arr[keep[-1]]) > DEDUP_MSE:
                    keep.append(i)
            # 帧数仍超上限：等步长抽稀（首尾帧必留）
            if len(keep) > args.max_frames:
                step = (len(keep) - 1) / (args.max_frames - 1)
                keep = sorted({round(k * step) for k in range(args.max_frames)} |
                              {keep[0], keep[-1]})
            frames = [frames[i] for i in keep]
            arr = [arr[i] for i in keep]
            n = len(frames)
            print(f"[sheet] 去重后 {n} 帧")

            # 帧间差分 → 翻页窗口
            diffs = [mse(arr[i], arr[i - 1]) for i in range(1, n)]
            rank = sorted(range(len(diffs)), key=lambda i: -diffs[i])
            n_flip = max(2, min(4, n // 5))
            flip_set = set(rank[:n_flip])
            # 连续化：翻页帧应该是连续段，把窗口内空洞补上
            lo = min(flip_set); hi = max(flip_set)
            flip_idx = set(range(lo, hi + 1))
            kudos_frame = min(hi + 1, n - 1)  # 翻页完成后的第一帧冒「知识++」
            print(f"[sheet] 翻页窗口 帧{lo}..{hi}，kudos_local_frame={kudos_frame}")
            flip_interval = args.flip_interval

        # 时长编排：总时长 = flip_interval；翻页帧占约 1s（AI 帧用 FLIP_FRAME_MS），
        # 其余 idle 帧均摊剩余时长
        total_ms = int(flip_interval * 1000)
        if baked is not None:
            flip_ms = max(1, 1000 // max(1, len(flip_idx)))
        else:
            flip_ms = FLIP_FRAME_MS
        idle_n = n - len(flip_idx)
        idle_ms = max(60, (total_ms - len(flip_idx) * flip_ms) // max(1, idle_n))
        durations = [flip_ms if i in flip_idx else idle_ms for i in range(n)]
        real_total = sum(durations)
        print(f"[sheet] 时长编排 总 {real_total}ms（目标 {total_ms}ms）"
              f" flip={len(flip_idx)}×{flip_ms}ms idle={idle_n}×{idle_ms}ms")

        # 装箱 + 写 sprite.json（TexturePacker Hash + sprite-gen animations）
        canvas, placements, side = pack_shelf(frames)
        outdir = Path(args.out)
        outdir.mkdir(parents=True, exist_ok=True)
        png_path = outdir / "spritesheet.png"
        canvas.save(png_path, optimize=True)
        kb = png_path.stat().st_size / 1024
        if kb > 600:
            # 平面卡通色数有限：量化降体积（RGBA→FASTOCTREE 保 alpha）
            q = canvas.quantize(colors=160, method=Image.FASTOCTREE)
            q.save(png_path, optimize=True)
            kb = png_path.stat().st_size / 1024

        fw, fh = frames[0].size
        fj = {"frames": {}, "animations": [{
            "name": "read", "direction": "forward", "repeat": 0,
            "fps": round(1000 / (real_total / n), 1),
            "frames": [f"read_{i+1:04d}" for i in range(n)],
            "pivot": {"x": 0.5, "y": 1.0},
        }], "meta": {
            "image": "spritesheet.png", "size": {"w": side, "h": side},
            "pivot": {"x": 0.5, "y": 1.0},
        }}
        for i, (im, (px, py)) in enumerate(zip(frames, placements)):
            fj["frames"][f"read_{i+1:04d}"] = {
                "frame": {"x": px, "y": py, "w": im.width, "h": im.height},
                "rotated": False, "trimmed": True,
                "spriteSourceSize": {"x": 0, "y": 0,
                                     "w": im.width, "h": im.height},
                "sourceSize": {"w": im.width, "h": im.height},
                "duration": durations[i],
            }
        json_path = outdir / "sprite.json"
        json_path.write_text(json.dumps(fj, ensure_ascii=False, indent=1), "utf-8")

        summary = {
            "frames": n, "frame_size": [fw, fh], "atlas_side": side,
            "png_kb": round(kb, 1), "loop_ms": real_total,
            "kudos_local_frame": kudos_frame,
            "flip_frames": sorted(flip_idx),
            "coverage": round(cov, 3) if baked is None else None,
            "out": str(outdir),
        }
        print("SUMMARY " + json.dumps(summary, ensure_ascii=False))
        if kb > 600:
            sys.exit("图集超过 600KB 上限，需降低 frame-max 或帧数后重跑")
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    main()
