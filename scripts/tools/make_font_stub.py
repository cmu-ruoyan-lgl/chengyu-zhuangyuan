#!/usr/bin/env python3
"""生成引擎硬编码兜底路径的「极小占位字体」。

背景（S19 加载优化）：
  * `main.lua` 用 theme="default-dark"，该主题把 sans / sans-bold 注册到
    `Fonts/NotoSansSC-*.ttf` —— 这两份才是 UI 实际渲染字体，必须保留完整字集。
  * 引擎二进制另外硬编码加载 `Fonts/MiSans-Regular.ttf` / `MiSans-Bold.ttf`
    作为全局 fallback；缺文件会刷 `Could not find resource` 错误。
  * 历史上这两份是 NotoSansSC 的**字节级副本**（各 2.14MB）。但既然字集与主字体
    完全相同，fallback 永远不可能补出主字体没有的字 —— 因此用极小占位零视觉损失。

占位保留 ASCII + 常用中文标点（122 字形 / 约 12KB），足以让 fallback 字体合法加载。
每次重跑 `tools/build_verification_font.py`（它会 cp 覆盖 MiSans-*）之后，
**必须再跑本脚本**，否则包体又涨回 8MB。

用法：
  python3 scripts/tools/make_font_stub.py
  python3 scripts/tools/make_font_stub.py --check   # 只校验当前占位是否合规
"""

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT_DIR = os.path.join(ROOT, "assets", "Fonts")
SRC = os.path.join(FONT_DIR, "NotoSansSC-Bold.ttf")
TARGETS = ["MiSans-Regular.ttf", "MiSans-Bold.ttf"]

# ASCII 可见字符 + 全角空格 + 常用中文/全角标点 + 间隔号
RANGES = [
    (0x20, 0x7E), (0xA0, 0xA0), (0xB7, 0xB7),
    (0x2010, 0x203B), (0x3000, 0x3000), (0xFF01, 0xFF65),
]
UNICODES = sorted({c for lo, hi in RANGES for c in range(lo, hi + 1)})
MAX_BYTES = 64 * 1024


def build(src, dst):
    from fontTools import subset
    opts = subset.Options()
    opts.hinting = False
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    font = subset.load_font(src, opts)
    sub = subset.Subsetter(options=opts)
    sub.populate(unicodes=UNICODES)
    sub.subset(font)
    subset.save_font(font, dst, opts)
    return os.path.getsize(dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只校验不生成")
    args = ap.parse_args()

    if args.check:
        ok = True
        for name in TARGETS:
            p = os.path.join(FONT_DIR, name)
            size = os.path.getsize(p)
            flag = "OK" if size <= MAX_BYTES else "过大（需重跑本脚本）"
            ok &= size <= MAX_BYTES
            print("  %-24s %7d B  %s" % (name, size, flag))
        return 0 if ok else 1

    if not os.path.exists(SRC):
        print("缺少源字体: " + SRC, file=sys.stderr)
        return 2
    for name in TARGETS:
        dst = os.path.join(FONT_DIR, name)
        size = build(SRC, dst)
        print("  %-24s %7d B  占位已生成" % (name, size))
    print("完成。注意：MiSans-* 仅供引擎兜底加载，UI 渲染走 NotoSansSC-*。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
