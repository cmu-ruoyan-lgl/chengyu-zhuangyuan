#!/usr/bin/env python3
"""零积分首版图标生成器：统一「浅色圆角底 + 深色简笔图形」扁平风格。

用法（项目根执行）：
  python3 scripts/tools/make_icons.py                 # 生成 assets/sprites/icons/
  python3 scripts/tools/make_icons.py --only gold,home # 只重生成指定键

- 配色一律取 assets/data/config.json 的 ui.color（浅色底 = 主色向白混合，
  图形 = 对应 deep/dark 色），保证与全局主题一致。
- 4x 超采样（512 画布）绘制后降到 128px，边缘平滑。
- 产出后须补 .meta：
  node tools/maker_call.mjs call generate_resource_meta '{"target_dir":"<绝对路径>","paths":[...]}'
- 充值后可用 ImageGen 逐个替换同名 PNG（尺寸不变），UI 代码零改动。
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

CFG = json.loads(Path("assets/data/config.json").read_text("utf-8"))
C = {k: tuple(v[:3]) for k, v in CFG["ui"]["color"].items()}
OUT = Path("assets/sprites/icons")
SS = 4  # 超采样倍数：512 画布 → 128 输出


def tint(c, ratio):
    """向白混合：ratio 越大越浅。"""
    return tuple(int(v + (255 - v) * ratio) for v in c)


def rrect(d, box, r, fill):
    d.rounded_rectangle(box, radius=r, fill=fill)


def poly(d, pts, fill):
    d.polygon(pts, fill=fill)


# ---------------------------------------------------------------- 图形库（512 画布坐标系）

def g_home(d, g, bg):
    poly(d, [(256, 96), (108, 240), (404, 240)], g)          # 屋顶
    d.rectangle([150, 240, 362, 416], fill=g)                 # 屋身
    d.rectangle([224, 316, 288, 416], fill=bg)                # 门（透底色）


def g_challenge(d, g, bg):
    rrect(d, [150, 168, 362, 344], 22, g)                     # 卷纸
    rrect(d, [120, 120, 392, 160], 20, g)                     # 上轴
    rrect(d, [120, 352, 392, 392], 20, g)                     # 下轴
    d.ellipse([104, 108, 160, 164], fill=g)                   # 轴头
    d.ellipse([344, 348, 408, 412], fill=g)
    for x in (196, 244, 292):                                 # 纸面三点
        d.ellipse([x, 244, x + 20, 264], fill=bg)


def g_book(d, g, bg):
    poly(d, [(256, 168), (136, 208), (136, 400), (256, 356)], g)   # 左页
    poly(d, [(256, 168), (376, 208), (376, 400), (256, 356)], g)   # 右页
    d.rectangle([250, 172, 262, 356], fill=bg)                # 中缝


def g_shop(d, g, bg):
    d.rounded_rectangle([156, 208, 356, 416], 26, fill=g)     # 袋身
    d.arc([190, 128, 322, 260], 180, 360, fill=g, width=22)   # 提手
    d.rectangle([228, 300, 284, 356], fill=bg)                # 袋上小方孔装饰


def g_stamina(d, g, bg):
    poly(d, [(292, 88), (168, 280), (240, 280), (212, 424),
             (344, 224), (268, 224)], g)                      # 闪电


def g_gold(d, g, bg):
    d.ellipse([104, 104, 408, 408], fill=g)                   # 古钱外圆
    d.rectangle([224, 224, 288, 288], fill=bg)                # 方孔


def g_back(d, g, bg):
    poly(d, [(318, 110), (232, 110), [138, 256], (232, 402), (318, 402),
             (224, 256)], g)                                  # 左箭头 chevron


def g_close(d, g, bg):
    w = 42
    for a, b in (((150, 150), (362, 362)), ((362, 150), (150, 362))):
        # 粗斜线用旋转矩形近似：四点多边形
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = (dx * dx + dy * dy) ** 0.5
        ux, uy = dx / L, dy / L
        nx, ny = -uy, ux
        poly(d, [(a[0] + nx * w, a[1] + ny * w), (b[0] + nx * w, b[1] + ny * w),
                 (b[0] - nx * w, b[1] - ny * w), (a[0] - nx * w, a[1] - ny * w)], g)


def g_hint(d, g, bg):
    d.ellipse([146, 106, 366, 326], fill=g)                   # 灯泡
    poly(d, [(224, 318), (288, 318), (300, 386), (212, 386)], g)  # 灯颈
    d.rectangle([212, 394, 300, 420], fill=g)                 # 灯座
    d.arc([180, 150, 240, 210], 200, 340, fill=bg, width=16)  # 高光


def g_shuffle(d, g, bg):
    d.rectangle([140, 176, 322, 214], fill=g)                 # 上箭杆→
    poly(d, [(322, 140), (396, 195), (322, 250)], g)
    d.rectangle([190, 298, 372, 336], fill=g)                 # 下箭杆←
    poly(d, [(190, 262), (116, 317), (190, 372)], g)


def g_skip(d, g, bg):
    for cx in (196, 316):                                     # 双 chevron →
        poly(d, [(cx - 40, 122), (cx + 44, 256), (cx - 40, 390),
                 (cx - 88, 390), (cx - 4, 256), (cx - 88, 122)], g)


def g_double(d, g, bg):
    f = ImageFont.truetype("assets/Fonts/NotoSansSC-Bold.ttf", 150)
    d.text((256, 256), "×2", font=f, fill=g, anchor="mm")


def g_undo(d, g, bg):
    d.arc([140, 140, 372, 372], 60, 300, fill=g, width=44)    # 弧
    poly(d, [(150, 92), (268, 150), (160, 226)], g)           # 箭头


def g_medal(d, g, bg):
    poly(d, [(180, 330), (232, 330), (204, 428), (152, 428)], g)   # 绶带左
    poly(d, [(332, 330), (280, 330), (308, 428), (360, 428)], g)   # 绶带右
    d.ellipse([136, 128, 376, 368], fill=g)                   # 章
    # 五角星（透底色）
    import math
    cx, cy, R, r = 256, 248, 86, 34
    pts = []
    for i in range(10):
        rad = R if i % 2 == 0 else r
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    poly(d, pts, bg)


# 底色（ui.color 键）→ 图形色（ui.color 键）
ICONS = {
    "home":      (g_home, "jade", "jade_deep"),
    "challenge": (g_challenge, "seal", "seal_deep"),
    "book":      (g_book, "accent", "gold_dark"),
    "shop":      (g_shop, "gold", "gold_dark"),
    "stamina":   (g_stamina, "jade", "jade_deep"),
    "gold":      (g_gold, "gold", "gold_dark"),
    "back":      (g_back, "panel_edge", "ink"),
    "close":     (g_close, "panel_edge", "ink"),
    "hint":      (g_hint, "accent", "gold_dark"),
    "shuffle":   (g_shuffle, "jade", "jade_deep"),
    "skip":      (g_skip, "jade", "jade_deep"),
    "double":    (g_double, "gold", "gold_dark"),
    "undo":      (g_undo, "jade", "jade_deep"),
    "medal":     (g_medal, "seal", "gold"),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="逗号分隔的键，缺省全部")
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()
    keys = args.only.split(",") if args.only else list(ICONS)

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    made = []
    for key in keys:
        glyph, bgk, gk = ICONS[key]
        bg = tint(C[bgk], 0.80)
        g = C[gk]
        canvas = Image.new("RGBA", (128 * SS, 128 * SS), (0, 0, 0, 0))
        d = ImageDraw.Draw(canvas)
        d.rounded_rectangle([8 * SS, 8 * SS, 120 * SS, 120 * SS],
                            radius=28 * SS, fill=bg + (255,))
        glyph(d, g + (255,), bg + (255,))
        img = canvas.resize((128, 128), Image.LANCZOS)
        p = outdir / f"icon_{key}.png"
        img.save(p, optimize=True)
        made.append(f"{p} {p.stat().st_size // 1024}KB")
    print("\n".join(made))
    print(f"SUMMARY {{\"made\": {len(made)}, \"out\": \"{outdir}\"}}")


if __name__ == "__main__":
    main()
