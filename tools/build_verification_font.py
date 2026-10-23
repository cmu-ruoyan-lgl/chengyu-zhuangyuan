#!/usr/bin/env python3
"""构建项目字体（本地验证 + 出包两用）。

背景：
  本地 UrhoXRuntime 是精简运行时，不含任何字体资源，启动时会报
  `Could not load global fallback font Fonts/MiSans-Regular.ttf`，
  中文完全渲染不出来。引擎资源路径 `Fonts/xxx.ttf` 映射到项目的
  `assets/Fonts/xxx.ttf`，因此项目自带一份字体即可同时满足本地验证与出包。

字体来源（默认）：
  Noto Sans SC —— SIL Open Font License 1.1，可自由再分发。
  由 `bash tools/fetch_ofl_font.sh` 缓存到 ~/.cache/maker-fonts/。
  ⚠️ 严禁再用 macOS 系统字体（PingFang / Arial Unicode）派生，那是不可分发的。

产物命名：
  NotoSansSC-Regular.ttf —— 与引擎 default-dark 主题期望的文件名一致
  NotoSansSC-Bold.ttf    —— 真实粗体（引擎库里的 sans-bold 是 Placeholder）

用法：
  python3 tools/build_verification_font.py                 # 默认 3500 字 Regular + Bold
  python3 tools/build_verification_font.py --chars 1500
  python3 tools/build_verification_font.py --regular-only
"""
import argparse
import os
import sys

from fontTools.ttLib import TTFont
from fontTools.subset import Subsetter, Options

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.expanduser("~/.cache/maker-fonts")
DEFAULT_SRC = os.path.join(CACHE_DIR, "NotoSansSC-Regular.ttf")
BOLD_SRC = os.path.join(CACHE_DIR, "NotoSansSC-Bold.ttf")
FONT_OUT_DIR = os.path.join(PROJECT_ROOT, "assets", "Fonts")

# CJK 基本区 + 常用中文标点 + ASCII
EXTRA_CHARS = "，。、；：？！“”‘’（）《》〈〉—…·、０１２３４５６７８９"


def pick_cjk(font, limit):
    """取 CJK 基本区中该字体实际覆盖的码点（码点序）。"""
    cmap = font.getBestCmap()
    chars = [cp for cp in range(0x4E00, 0x9FFF + 1) if cp in cmap]
    return sorted(chars)[:limit]


def subset(src, out, chars, label):
    if not os.path.exists(src):
        print(f"ERROR: 源字体不存在: {src}", file=sys.stderr)
        print("       先执行: bash tools/fetch_ofl_font.sh", file=sys.stderr)
        return False

    font = TTFont(src, lazy=False)
    keep = set(range(0x20, 0x7F))
    keep.update(ord(c) for c in EXTRA_CHARS)
    keep.update(chars)

    options = Options()
    options.layout_features = []      # 丢弃复杂排版特性，减小体积
    options.notdef_outline = True
    options.recalc_bounds = True
    options.drop_tables += ["DSIG"]
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.notdef_glyph = True

    subsetter = Subsetter(options=options)
    subsetter.populate(text="".join(chr(c) for c in sorted(keep)))
    subsetter.subset(font)

    os.makedirs(os.path.dirname(out), exist_ok=True)
    font.save(out)
    print(f"  [{label}] {os.path.basename(out)}: "
          f"{len(keep)} 字, {os.path.getsize(out) / 1e6:.2f} MB")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", default=DEFAULT_SRC)
    parser.add_argument("--bold-src", default=BOLD_SRC)
    parser.add_argument("--chars", type=int, default=3500, help="保留的 CJK 汉字数量上限")
    parser.add_argument("--regular-only", action="store_true", help="只出 Regular")
    args = parser.parse_args()

    probe = TTFont(args.src, lazy=True)
    cjk = pick_cjk(probe, args.chars)
    print(f"source: {args.src}")
    print(f"CJK kept: {len(cjk)} / requested {args.chars}")

    ok = subset(args.src, os.path.join(FONT_OUT_DIR, "NotoSansSC-Regular.ttf"),
                cjk, "Regular")
    if ok and not args.regular_only:
        ok = subset(args.bold_src, os.path.join(FONT_OUT_DIR, "NotoSansSC-Bold.ttf"),
                    cjk, "Bold")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
