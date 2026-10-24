#!/usr/bin/env python3
"""零积分宣传素材生成：10 枚游戏图标候选 + 5 张 9:16 宣传图。

用法：python3 scripts/tools/make_promo.py   # 产出 docs/宣传素材/
依赖：Pillow、fontTools（字体 cmap 校验，防渲染字体子集外的字）。

设计原则：只用已验收资产（scholar.png / NotoSansSC 子集 / config 配色）；
所有待渲染文本先过 cmap 校验，缺字直接报错列出（防线上豆腐块）。
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont
from fontTools.ttLib import TTFont

ROOT = Path(".")
OUT = ROOT / "docs" / "宣传素材"
SCHOLAR = Image.open("assets/Textures/scholar.png").convert("RGBA")
C = {k: tuple(v[:3]) for k, v in
     json.loads((ROOT / "assets/data/config.json").read_text("utf-8"))
     ["ui"]["color"].items()}
FONT_PATH = "assets/Fonts/NotoSansSC-Bold.ttf"
_cmap = TTFont(FONT_PATH).getBestCmap()


def ensure(text, tag):
    miss = [ch for ch in text if ord(ch) > 127 and ord(ch) not in _cmap
            and not ch.isascii()]
    if miss:
        raise SystemExit(f"[{tag}] 字体子集缺字: {''.join(miss)}（改用游戏文案已有的字）")


def font(size):
    return ImageFont.truetype(FONT_PATH, size)


def vgrad(size, top, bottom):
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((w, h))


def scholar_with_shadow(size, blur=10, dy=8):
    sc = SCHOLAR.resize((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size + 60, size + 60), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sh.paste(sc, (30, 30 + dy), sc)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    dark = Image.new("RGBA", sh.size, (40, 70, 55, 0))
    dark.putalpha(sh.split()[3].point(lambda a: a * 45 // 100))
    canvas.alpha_composite(dark)
    canvas.paste(sc, (30, 30), sc)
    return canvas


def paste_center(base, im, cx, cy):
    base.paste(im, (int(cx - im.width / 2), int(cy - im.height / 2)), im)


def text_outline(d, xy, s, f, fill, outline, w, anchor="mm"):
    d.text(xy, s, font=f, fill=fill, anchor=anchor,
           stroke_width=w, stroke_fill=outline)


# ══════════════════════════════ 10 枚图标候选 ══════════════════════════════
S = 512

def icon_01():  # 渐变底 + 书童 + 白字描边标题（线上同款）
    im = vgrad((S, S), C["bg_top"], C["jade"]).convert("RGBA")
    paste_center(im, scholar_with_shadow(330), 256, 300)
    d = ImageDraw.Draw(im)
    ensure("成语小状元", "icon01")
    text_outline(d, (256, 108), "成语小状元", font(92), (255, 255, 255), C["jade_deep"], 8)
    return im

def icon_02():  # 深青底 + 金色圆环 + 书童（无字）
    im = Image.new("RGBA", (S, S), C["jade_deep"] + (255,))
    d = ImageDraw.Draw(im)
    d.ellipse([26, 26, S - 26, S - 26], outline=C["gold"] + (255,), width=14)
    d.ellipse([52, 52, S - 52, S - 52], fill=C["bg_top"] + (255,))
    paste_center(im, scholar_with_shadow(300), 256, 276)
    return im

def icon_03():  # 暖金底 + 朱砂顶带「状元」+ 书童
    im = vgrad((S, S), C["gold"], C["cream"]).convert("RGBA")
    d = ImageDraw.Draw(im)
    ensure("状元", "icon03")
    d.rounded_rectangle([96, 52, S - 96, 148], 32, fill=C["seal_deep"] + (255,))
    d.text((256, 100), "状元", font=font(64), fill=(255, 255, 255), anchor="mm")
    paste_center(im, scholar_with_shadow(310), 256, 320)
    return im

def icon_04():  # 白底 + 薄荷双环 + 底部标题条
    im = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    d = ImageDraw.Draw(im)
    d.ellipse([36, 36, S - 36, S - 36], outline=C["jade"] + (255,), width=18)
    d.ellipse([62, 62, S - 62, S - 62], outline=C["panel_edge"] + (255,), width=6)
    paste_center(im, scholar_with_shadow(280), 256, 240)
    d.rounded_rectangle([76, 402, S - 76, 476], 28, fill=C["jade_deep"] + (255,))
    ensure("成语小状元", "icon04")
    d.text((256, 439), "成语小状元", font=font(52), fill=(255, 255, 255), anchor="mm")
    return im

def icon_05():  # 大字「语」+ 小书童（文字主导）
    im = vgrad((S, S), C["bg_top"], C["bg_bottom"]).convert("RGBA")
    d = ImageDraw.Draw(im)
    ensure("语", "icon05")
    text_outline(d, (200, 210), "语", font(300), C["jade_deep"], (255, 255, 255), 16)
    sc = SCHOLAR.resize((210, 210), Image.LANCZOS)
    im.paste(sc, (288, 236), sc)
    return im

def icon_06():  # 四格成语卡拼贴
    im = Image.new("RGBA", (S, S), C["bg_top"] + (255,))
    d = ImageDraw.Draw(im)
    words = ["一", "鸣", "惊", "人"]
    ensure("一鸣惊人", "icon06")
    cols = [(C["jade_deep"], 60), (C["gold_deep"], 190), (C["seal_deep"], 190), (C["jade"], 60)]
    for i, (ch, (col, y)) in enumerate(zip(words, cols)):
        x = 60 + (i % 2) * 200
        yy = y + 0
        d.rounded_rectangle([x, yy, x + 190, yy + 190], 30, fill=(255, 255, 255, 255),
                            outline=col + (255,), width=8)
        d.text((x + 95, yy + 95), ch, font=font(110), fill=col + (255,), anchor="mm")
    paste_center(im, scholar_with_shadow(150), 396, 424)
    return im

def icon_07():  # 夜读风：深底 + 暖光晕 + 书童
    im = Image.new("RGBA", (S, S), (34, 52, 44, 255))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([76, 60, 436, 420], fill=C["gold"] + (110,))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    im.alpha_composite(glow)
    paste_center(im, scholar_with_shadow(320), 256, 300)
    d = ImageDraw.Draw(im)
    ensure("成语小状元", "icon07")
    text_outline(d, (256, 462), "成语小状元", font(56), C["gold"], (34, 52, 44), 6)
    return im

def icon_08():  # 水彩晕染 + 书童 + 竖题签
    im = vgrad((S, S), C["bg"], C["bg_bottom"]).convert("RGBA")
    wash = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wash)
    for cx, cy, r, col in [(150, 130, 150, C["jade"]), (380, 340, 170, C["gold"]),
                           (200, 420, 130, C["seal"])]:
        wd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (60,))
    wash = wash.filter(ImageFilter.GaussianBlur(50))
    im.alpha_composite(wash)
    paste_center(im, scholar_with_shadow(330), 300, 290)
    d = ImageDraw.Draw(im)
    ensure("成语小状元", "icon08")
    sign = Image.new("RGBA", (120, 420), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sign)
    sd.rounded_rectangle([0, 0, 119, 419], 18, fill=C["seal_deep"] + (235,))
    f = font(72)
    for i, ch in enumerate("成语小状元"):
        sd.text((60, 50 + i * 82), ch, font=f, fill=(255, 255, 255), anchor="mm")
    im.paste(sign, (36, 46), sign)
    return im

def icon_09():  # 极简：纯薄荷底 + 大书童 + 右下角金点
    im = Image.new("RGBA", (S, S), C["bg_top"] + (255,))
    paste_center(im, scholar_with_shadow(420, blur=6, dy=6), 256, 268)
    d = ImageDraw.Draw(im)
    d.ellipse([404, 404, 460, 460], fill=C["gold"] + (255,))
    d.ellipse([416, 416, 448, 448], fill=(255, 255, 255, 255))
    return im

def icon_10():  # 纸纹米白底 + 朱砂竖排大字 + 书童
    im = Image.new("RGBA", (S, S), C["cream"] + (255,))
    noise = Image.effect_noise((S, S), 12).convert("L").point(lambda v: 246 + v // 25)
    im = Image.composite(Image.new("RGBA", (S, S), C["panel"] + (255,)), im,
                         noise.point(lambda v: 255)).convert("RGBA")
    d = ImageDraw.Draw(im)
    ensure("成语小状元", "icon10")
    f = font(86)
    for i, ch in enumerate("成语小状元"):
        text_outline(d, (120, 96 + i * 86), ch, f, C["seal_deep"], (255, 255, 255), 6)
    d.rectangle([176, 60, 182, 470], fill=C["seal_deep"] + (255,))
    paste_center(im, scholar_with_shadow(300), 348, 276)
    return im


# ══════════════════════════════ 5 张宣传图（9:16） ══════════════════════════════
PW, PH = 1080, 1920

def _base(title, sub, scholar_size=760, sc_y=1080):
    im = vgrad((PW, PH), C["bg_top"], C["bg_bottom"]).convert("RGBA")
    wash = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wash)
    wd.ellipse([-200, 1200, 700, 2100], fill=C["jade"] + (46,))
    wd.ellipse([500, -100, 1500, 900], fill=C["gold"] + (36,))
    wash = wash.filter(ImageFilter.GaussianBlur(90))
    im.alpha_composite(wash)
    paste_center(im, scholar_with_shadow(scholar_size, blur=16, dy=12), PW // 2, sc_y)
    d = ImageDraw.Draw(im)
    ensure(title + sub, "promo")
    text_outline(d, (PW // 2, 200), title, font(150), (255, 255, 255), C["jade_deep"], 14)
    if sub:
        d.rounded_rectangle([PW // 2 - 400, 360, PW // 2 + 400, 470], 40,
                            fill=C["jade_deep"] + (255,))
        d.text((PW // 2, 415), sub, font=font(58), fill=(255, 255, 255), anchor="mm")
    return im, d


def promo_01():  # 主视觉
    im, d = _base("成语小状元", "边玩边学 · 从童生到状元")
    d.text((PW // 2, 1770), "三百余关 · 八百余条成语", font=font(56),
           fill=C["ink"] + (255,), anchor="mm")
    return im

def promo_02():  # 玩法示意（程序化棋盘格：一鸣惊人 × 人才辈出 十字交叉）
    im, d = _base("成语交叉填字", "", scholar_size=560, sc_y=1580)
    ensure("一鸣惊人才辈出", "promo2")
    cells = {}
    for i, ch in enumerate("一鸣惊人"):        # 横：cols 1..4 @ row 1
        cells[(1 + i, 1)] = ch
    for i, ch in enumerate("人才辈出"):        # 竖：col 4 @ rows 1..4
        cells[(4, 1 + i)] = ch
    cs, gap = 170, 12
    ox = (PW - (4 * cs + 3 * gap)) // 2
    oy = 520
    for (col, row), ch in cells.items():
        x = ox + (col - 1) * (cs + gap)
        y = oy + (row - 1) * (cs + gap)
        d.rounded_rectangle([x, y, x + cs, y + cs], 30, fill=(255, 255, 255, 255),
                            outline=C["panel_edge"] + (255,), width=6)
        d.text((x + cs // 2, y + cs // 2), ch, font=font(128),
               fill=C["ink"] + (255,), anchor="mm")
    return im

def promo_03():  # 内容量
    im = Image.new("RGBA", (PW, PH), C["jade_deep"] + (255,))
    d = ImageDraw.Draw(im)
    ensure("三百余关八百余条成语天天不重样", "promo3")
    text_outline(d, (PW // 2, 300), "三百余关", font(210), C["gold"], (255, 255, 255), 4)
    text_outline(d, (PW // 2, 580), "八百余条成语", font(150), (255, 255, 255), C["jade"], 10)
    d.text((PW // 2, 800), "天天不重样", font=font(72), fill=C["cream"] + (255,), anchor="mm")
    paste_center(im, scholar_with_shadow(820, blur=18, dy=14), PW // 2, 1400)
    return im

def promo_04():  # 养成系统
    im, d = _base("府邸 · 官职 · 门客", "", scholar_size=520, sc_y=1560)
    ensure("从童生到状元步步高升", "promo4")
    tiers = ["童生", "秀才", "举人", "进士", "状元"]
    bw, gap = 176, 26
    x0 = (PW - (len(tiers) * bw + (len(tiers) - 1) * gap)) // 2
    for i, t in enumerate(tiers):
        x = x0 + i * (bw + gap)
        col = C["gold"] if t == "状元" else C["jade_deep"]
        d.rounded_rectangle([x, 620, x + bw, 760], 26, fill=(255, 255, 255, 255),
                            outline=col + (255,), width=6)
        d.text((x + bw // 2, 690), t, font=font(56), fill=col + (255,), anchor="mm")
        if i < len(tiers) - 1:
            d.polygon([(x + bw + gap // 2 - 12, 676), (x + bw + gap // 2 + 12, 690),
                       (x + bw + gap // 2 - 12, 704)], fill=C["jade_deep"] + (255,))
    d.text((PW // 2, 860), "从童生到状元，步步高升", font=font(64),
           fill=C["ink"] + (255,), anchor="mm")
    return im

def promo_05():  # 图鉴/学习价值
    im, d = _base("图鉴 · 错题本", "", scholar_size=540, sc_y=1560)
    ensure("亡羊补牢画蛇添足守株待兔温故知新看释义记错题", "promo5")
    cards = [("亡羊补牢", C["jade_deep"]), ("画蛇添足", C["gold_deep"]),
             ("守株待兔", C["seal_deep"]), ("温故知新", C["jade"])]
    y = 600
    for i, (w, col) in enumerate(cards):
        x = 120 if i % 2 == 0 else 560
        d.rounded_rectangle([x, y + i * 130, x + 400, y + i * 130 + 106], 24,
                            fill=(255, 255, 255, 255), outline=col + (255,), width=6)
        d.text((x + 200, y + i * 130 + 53), w, font=font(62),
               fill=col + (255,), anchor="mm")
    d.text((PW // 2, 1180), "看释义 · 记错题 · 长知识", font=font(66),
           fill=C["ink"] + (255,), anchor="mm")
    return im


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    icons = [icon_01, icon_02, icon_03, icon_04, icon_05,
             icon_06, icon_07, icon_08, icon_09, icon_10]
    promos = [promo_01, promo_02, promo_03, promo_04, promo_05]

    for i, fn in enumerate(icons, 1):
        p = OUT / f"icon_cand_{i:02d}.png"
        fn().convert("RGB").save(p, optimize=True)
        print(p, p.stat().st_size // 1024, "KB")
    for i, fn in enumerate(promos, 1):
        p = OUT / f"promo_{i:02d}.png"
        fn().convert("RGB").save(p, optimize=True)
        print(p, p.stat().st_size // 1024, "KB")

    # 两张对照总览，方便挑
    sheet = Image.new("RGB", (5 * 220 + 40, 2 * 320 + 60), (250, 250, 250))
    sd = ImageDraw.Draw(sheet)
    for i in range(10):
        im = Image.open(OUT / f"icon_cand_{i + 1:02d}.png").resize((200, 200))
        sheet.paste(im, (30 + (i % 5) * 220, 30 + (i // 5) * 320))
        sd.text((130 + (i % 5) * 220, 240 + (i // 5) * 320), f"#{i + 1}",
                fill=(60, 60, 60), anchor="mm", font=font(28))
    sheet.save(OUT / "icons_contact.png", optimize=True)
    psheet = Image.new("RGB", (5 * 400 + 60, 760), (250, 250, 250))
    for i in range(5):
        im = Image.open(OUT / f"promo_{i + 1:02d}.png").resize((360, 640))
        psheet.paste(im, (30 + i * 400, 60))
    psheet.save(OUT / "promos_contact.png", optimize=True)
    print("SUMMARY icons=10 promos=5 out=" + str(OUT))


if __name__ == "__main__":
    main()
