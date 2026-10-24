#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""程序化绘制 Q 版书童「骨骼部件」（不依赖 AI 生成图，比例/关节全部可控）。

设计要点
--------
* 每个部件都画在**整幅 512x512 画布的最终位置**上（透明底），
  引擎侧只要全画幅叠放即可，装配误差为 0（上一版依赖 AI 合成图拟合，
  比例不可控，是动作诡异的根因）。
* 关节坐标由本文件的 SKELETON 定义，并写入 config.json 的 ui.scholar.joints。
* 姿态：坐姿，身体 3/4 朝右（即朝画面右下），低头看书，双手捧书。
* 画风：扁平卡通、统一外描边（填充层 alpha 膨胀取环，避免出现内部杂线）。

用法：python3 scripts/tools/draw_doll.py [--preview]
"""

import os
import sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "Textures", "doll")

SS = 4       # 超采样倍数（抗锯齿）
N = 512      # 输出画幅
C = N * SS   # 实际绘制画布

# ---------------------------------------------------------------- 配色（清新自然）
INK      = (62, 91, 78)        # 统一描边：深墨绿
SKIN     = (255, 224, 194)
SKIN_D   = (243, 201, 170)
HAIR     = (78, 62, 55)
HAIR_L   = (99, 81, 73)
ROBE     = (186, 225, 213)
ROBE_D   = (150, 203, 187)
TRIM     = (255, 253, 245)
SASH     = (243, 172, 66)
SASH_D   = (216, 140, 44)
PANTS    = (133, 190, 172)
PANTS_D  = (109, 167, 151)
SHOE     = (96, 71, 56)
SHOE_D   = (78, 58, 46)
WOOD     = (203, 165, 110)
WOOD_D   = (168, 126, 76)
PAGE     = (255, 253, 245)
PAGE_D   = (228, 211, 178)
TEXT     = (198, 192, 176)
BLUSH    = (255, 176, 166)
EYE      = (58, 76, 68)

# ---------------------------------------------------------------- 骨架（512 空间，y 向下）
SKELETON = {
    "hip":   (232, 332),   # 髋：躯干骨旋转中心（呼吸）
    "neck":  (238, 190),   # 颈：头骨旋转中心（点头）
    "elbow": (322, 272),   # 近侧肘：前臂骨旋转中心（翻页）
    "spine": (248, 278),   # 书脊：书页旋转中心
}

# ---------------------------------------------------------------- 绘制原语
class Pen:
    """坐标一律用 512 空间，内部乘 SS。"""
    def __init__(self, draw):
        self.d = draw

    def _b(self, b):
        return [v * SS for v in b]

    def ellipse(self, b, fill=None, outline=None, w=0):
        self.d.ellipse(self._b(b), fill=fill, outline=outline, width=int(w * SS))

    def rrect(self, b, r, fill=None, outline=None, w=0):
        self.d.rounded_rectangle(self._b(b), radius=r * SS, fill=fill,
                                 outline=outline, width=int(w * SS))

    def poly(self, pts, fill=None, outline=None, w=0):
        p = [(x * SS, y * SS) for x, y in pts]
        if outline is not None:
            self.d.polygon(p, fill=fill, outline=outline, width=int(w * SS))
        else:
            self.d.polygon(p, fill=fill)

    def line(self, pts, fill, w, joint="curve"):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=fill,
                    width=int(w * SS), joint=joint)

    def limb(self, pts, color, w):
        """带描边的粗肢体：外围 INK 线 + 主体色线 + 两端圆头。"""
        r = w / 2.0
        self.line(pts, INK, w + 7)
        self.line(pts, color, w)
        for (x, y) in (pts[0], pts[-1]):
            self.ellipse((x - r - 3.5, y - r - 3.5, x + r + 3.5, y + r + 3.5), fill=INK)
            self.ellipse((x - r, y - r, x + r, y + r), fill=color)


def _dilate(a, iters):
    """布尔膨胀（8 邻域）。"""
    for _ in range(iters):
        b = a.copy()
        b[1:, :] |= a[:-1, :]
        b[:-1, :] |= a[1:, :]
        b[:, 1:] |= a[:, :-1]
        b[:, :-1] |= a[:, 1:]
        b[1:, 1:] |= a[:-1, :-1]
        b[:-1, :-1] |= a[1:, 1:]
        b[1:, :-1] |= a[:-1, 1:]
        b[:-1, 1:] |= a[1:, :-1]
        a = b
    return a


def render(name, shapes, stroke=3.4):
    """画填充 → 由 alpha 膨胀取环生成统一外描边 → 合成输出。"""
    fill = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    shapes(Pen(ImageDraw.Draw(fill)))
    alpha = np.array(fill.split()[-1]) > 8
    if stroke > 0:
        k = max(1, int(round(stroke * SS)))
        ring = _dilate(alpha, k) & (~alpha)
        arr = np.zeros((C, C, 4), np.uint8)
        arr[..., 0], arr[..., 1], arr[..., 2] = INK
        arr[..., 3] = ring.astype(np.uint8) * 255
        out = Image.fromarray(arr, "RGBA")
        out.alpha_composite(fill)
    else:
        out = fill
    out = out.resize((N, N), Image.LANCZOS)
    path = os.path.join(OUT, "scholar_%s.png" % name)
    out.save(path)
    px = int((np.array(out.split()[-1]) > 8).sum())
    print("  %-12s %5d px  -> %s" % (name, px, os.path.basename(path)))
    return out


# ---------------------------------------------------------------- 各部件
def sh_chair(p):
    # 后腿（暗，先画）
    p.rrect((202, 372, 218, 448), 4, fill=WOOD_D)
    # 前腿
    p.rrect((174, 368, 196, 458), 5, fill=WOOD)
    p.rrect((328, 368, 350, 458), 5, fill=WOOD)
    # 横撑
    p.rrect((174, 424, 350, 438), 4, fill=WOOD_D)
    # 座面下沿（暗）→ 上沿（亮）
    p.rrect((156, 360, 368, 376), 6, fill=WOOD_D)
    p.rrect((152, 344, 372, 368), 8, fill=WOOD)


def sh_legs(p):
    # 远腿（后）
    p.limb([(232, 332), (268, 384), (258, 438)], PANTS_D, 38)
    p.ellipse((234, 430, 292, 458), fill=SHOE_D)
    p.line([(240, 438), (286, 438)], (60, 44, 35), 3)
    # 近腿（前）
    p.limb([(250, 334), (302, 388), (296, 446)], PANTS, 44)
    p.ellipse((266, 438, 332, 468), fill=SHOE)
    p.line([(274, 446), (326, 446)], (66, 48, 38), 3)


def sh_torso(p):
    # 颈（最底，会被躯干与头覆盖上端）
    p.ellipse((214, 162, 260, 208), fill=SKIN_D)
    # 躯干主体（上窄下宽）
    p.poly([(200, 198), (282, 204), (298, 300), (312, 356), (156, 358), (174, 300)],
           fill=ROBE)
    p.ellipse((186, 190, 296, 226), fill=ROBE)      # 肩部圆润
    p.ellipse((154, 334, 316, 374), fill=ROBE)      # 衣摆圆润
    p.ellipse((158, 344, 314, 376), fill=ROBE_D)    # 下摆阴影
    p.ellipse((154, 334, 316, 352), fill=ROBE)      # 阴影上沿回收
    # 立领（朝右下的斜襟）
    p.poly([(216, 186), (264, 190), (258, 210), (222, 206)], fill=TRIM, outline=INK, w=2.5)
    p.poly([(222, 204), (256, 208), (250, 246), (228, 232)], fill=TRIM, outline=INK, w=2.5)
    # 腰带
    p.poly([(168, 294), (300, 296), (304, 320), (164, 318)], fill=SASH, outline=INK, w=2.5)
    p.ellipse((226, 296, 254, 326), fill=SASH_D)    # 结
    p.line([(240, 316), (232, 344)], SASH_D, 8)     # 飘带
    p.line([(244, 318), (256, 346)], SASH_D, 8)


def sh_head(p):
    # 发髻（在头后）
    p.ellipse((168, 44, 232, 108), fill=HAIR)
    p.ellipse((244, 50, 308, 114), fill=HAIR)
    p.ellipse((178, 52, 208, 78), fill=HAIR_L)      # 高光
    p.ellipse((256, 58, 286, 84), fill=HAIR_L)
    p.ellipse((190, 92, 214, 112), fill=SASH)       # 发饰
    p.ellipse((262, 98, 286, 118), fill=SASH)
    # 头（发为底）
    p.ellipse((176, 62, 300, 190), fill=HAIR)
    # 脸
    p.ellipse((190, 96, 282, 188), fill=SKIN)
    # 耳（3/4 朝右，右耳可见）
    p.ellipse((272, 124, 298, 152), fill=SKIN, outline=INK, w=3)
    # 腮红
    p.ellipse((198, 156, 226, 174), fill=BLUSH)
    p.ellipse((248, 156, 276, 174), fill=BLUSH)
    # 眉
    p.line([(202, 140), (225, 135)], EYE, 5)
    p.line([(249, 135), (272, 140)], EYE, 5)
    # 嘴（微笑）
    p.line([(228, 162), (238, 169), (248, 162)], INK, 4)
    # 刘海（波浪下沿，最后画以压住额头）
    p.poly([(176, 60), (300, 60), (300, 104), (280, 120), (258, 106),
            (238, 122), (214, 106), (190, 120), (176, 98)], fill=HAIR)


def sh_eyes_open(p):
    # 低头看书：上眼睑弧 + 靠下的眼珠
    p.line([(202, 148), (212, 142), (224, 148)], EYE, 6)
    p.ellipse((208, 150, 222, 164), fill=EYE)
    p.ellipse((211, 152, 217, 158), fill=TRIM)
    p.line([(250, 148), (260, 142), (272, 148)], EYE, 6)
    p.ellipse((256, 150, 270, 164), fill=EYE)
    p.ellipse((259, 152, 265, 158), fill=TRIM)


def sh_eyes_shut(p):
    # 眨眼：向下弯的弧
    p.line([(202, 146), (212, 156), (224, 146)], EYE, 6)
    p.line([(250, 146), (260, 156), (272, 146)], EYE, 6)


def sh_arm_far(p):
    p.limb([(202, 214), (180, 266), (198, 302)], ROBE_D, 38)
    p.line([(184, 288), (214, 294)], TRIM, 11)      # 袖口
    p.ellipse((180, 288, 218, 318), fill=SKIN)      # 手


def sh_arm_upper(p):
    p.ellipse((266, 204, 308, 244), fill=ROBE)      # 肩头
    p.limb([(286, 218), (322, 272)], ROBE, 42)


def sh_arm_fore(p):
    p.limb([(322, 272), (312, 300)], ROBE, 36)
    p.line([(300, 286), (326, 292)], TRIM, 11)      # 袖口
    p.ellipse((290, 286, 330, 318), fill=SKIN)      # 手
    p.line([(300, 306), (300, 314)], INK, 3)        # 手指暗示
    p.line([(312, 308), (312, 316)], INK, 3)


def sh_book(p):
    # 摊开的两页（外侧略上翘，做出透视）
    p.poly([(180, 288), (248, 279), (248, 335), (180, 326)], fill=PAGE)
    p.poly([(250, 279), (318, 288), (318, 326), (250, 335)], fill=PAGE)
    # 书脊
    p.line([(249, 280), (249, 334)], PAGE_D, 7)
    # 外缘（书页厚度）
    p.line([(180, 288), (180, 326)], INK, 3)
    p.line([(318, 288), (318, 326)], INK, 3)
    # 文字线
    for i, dy in enumerate((0, 12, 24)):
        p.line([(190, 298 + dy), (238, 293 + dy)], TEXT, 3)
        p.line([(258, 293 + dy), (306, 298 + dy)], TEXT, 3)


def sh_page(p):
    # 翻起的一页：与右页同形，绕书脊（左边缘）旋转
    p.poly([(250, 279), (318, 288), (318, 326), (250, 335)], fill=PAGE)
    p.line([(318, 288), (318, 326)], INK, 3)
    p.line([(258, 293), (306, 298)], TEXT, 3)
    p.line([(258, 305), (306, 310)], TEXT, 3)


PARTS = [
    ("chair",      sh_chair),
    ("legs",       sh_legs),
    ("torso",      sh_torso),
    ("head",       sh_head),
    ("eyes_open",  sh_eyes_open),
    ("eyes_shut",  sh_eyes_shut),
    ("arm_far",    sh_arm_far),
    ("arm_upper",  sh_arm_upper),
    ("arm_fore",   sh_arm_fore),
    ("book",       sh_book),
    ("page",       sh_page),
]

# 渲染顺序（后画者在上）：远臂在躯干之后（远侧=身后），手在书之前（托着书）
Z_ORDER = ["chair", "arm_far", "legs", "torso", "book", "arm_upper", "arm_fore",
           "head", "eyes_open"]


def main():
    os.makedirs(OUT, exist_ok=True)
    print("绘制部件 ->", OUT)
    imgs = {}
    for name, fn in PARTS:
        imgs[name] = render(name, fn)

    if "--preview" in sys.argv:
        canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        for nm in Z_ORDER:
            canvas.alpha_composite(imgs[nm])
        pv = os.path.join(ROOT, ".tmp", "scholar_rig_preview.png")
        os.makedirs(os.path.dirname(pv), exist_ok=True)
        canvas.save(pv)
        print("预览:", pv)

    print("关节:", ", ".join("%s=%s" % (k, v) for k, v in SKELETON.items()))


if __name__ == "__main__":
    main()
