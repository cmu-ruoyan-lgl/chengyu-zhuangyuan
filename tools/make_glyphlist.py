#!/usr/bin/env python3
"""生成字形图集容量测试用的汉字列表（输出 Lua 模块，供 scripts/glyphtest.lua 使用）。

用途：
  从系统字体 cmap 中抽取 N 个不重复的 CJK 基本区汉字，写成 scripts/_glyphchars.lua。
  渲染该列表可实测 NanoVG 字形图集（glyph atlas）的容量上限。

用法：
  python3 tools/make_glyphlist.py --count 1500 [--out scripts/_glyphchars.lua]
"""
import argparse
import os
import sys

from fontTools.ttLib import TTFont, TTCollection

# 候选字体（按顺序尝试，取第一个可用的）
# 首选 OFL 授权的 Noto Sans SC 缓存（可再分发）；
# 系统字体仅作兜底 —— 它们不可分发，但用于生成"测试字表"本身不涉及分发。
CANDIDATE_FONTS = [
    os.path.expanduser("~/.cache/maker-fonts/NotoSansSC-Regular.ttf"),
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
]

CJK_RANGE = (0x4E00, 0x9FFF)  # CJK 统一表意文字基本区


def load_cjk_chars(font_path, limit):
    """从字体 cmap 抽取 CJK 基本区汉字，按码点排序，最多 limit 个。"""
    chars = []
    if font_path.endswith(".ttc"):
        collection = TTCollection(font_path, lazy=True)
        fonts = collection.fonts
    else:
        fonts = [TTFont(font_path, lazy=True)]

    for font in fonts:
        for table in font["cmap"].tables:
            for codepoint in table.cmap.keys():
                if CJK_RANGE[0] <= codepoint <= CJK_RANGE[1]:
                    chars.append(chr(codepoint))
        if chars:
            break

    # 去重 + 排序（码点序，仅用于容量测试，不代表使用频率）
    chars = sorted(set(chars))
    return chars[:limit]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=1500, help="要抽取的汉字数量")
    parser.add_argument("--out", default="scripts/_glyphchars.lua", help="输出 Lua 文件路径")
    parser.add_argument("--font", default=None, help="指定字体路径（默认自动挑选）")
    args = parser.parse_args()

    font_path = args.font
    if font_path is None:
        for candidate in CANDIDATE_FONTS:
            if os.path.exists(candidate):
                font_path = candidate
                break
    if font_path is None or not os.path.exists(font_path):
        print("ERROR: 找不到可用的中文字体", file=sys.stderr)
        sys.exit(1)

    chars = load_cjk_chars(font_path, args.count)
    if len(chars) < args.count:
        print(f"WARN: 字体仅提供 {len(chars)} 个汉字（请求 {args.count}）", file=sys.stderr)

    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("-- 自动生成，勿手工编辑。来源字体: %s\n" % font_path)
        f.write("return {\n")
        for i in range(0, len(chars), 20):
            f.write("    " + ",".join('"%s"' % c for c in chars[i:i + 20]) + ",\n")
        f.write("}\n")

    print(f"source_font: {font_path}")
    print(f"chars_written: {len(chars)}")
    print(f"output: {args.out}")


if __name__ == "__main__":
    main()
