#!/usr/bin/env bash
# 获取 OFL 授权的中文字体源（Noto Sans SC），缓存到项目外固定目录。
#
# 为什么需要：
#   出包字体必须可再分发。macOS 系统字体（Arial Unicode / PingFang）受系统软件
#   许可约束，禁止随包分发；本项目统一改用 Noto Sans SC（SIL OFL 1.1）。
#   GitHub raw 在本机不可达，因此走 npm registry（@expo-google-fonts 提供原始 TTF，
#   且是 glyf 轮廓的 TTF —— NanoVG 底层的 stb_truetype 只认 glyf，不认 CFF/OTF）。
#
# 用法：
#   bash tools/fetch_ofl_font.sh          # 缓存缺失时下载，已存在则跳过
#   bash tools/fetch_ofl_font.sh --force  # 强制重新下载
set -uo pipefail

CACHE="$HOME/.cache/maker-fonts"
REGULAR="$CACHE/NotoSansSC-Regular.ttf"
BOLD="$CACHE/NotoSansSC-Bold.ttf"
LICENSE="$CACHE/OFL-NotoSansSC.txt"
PKG="@expo-google-fonts/noto-sans-sc"

if [ "${1:-}" != "--force" ] && [ -s "$REGULAR" ] && [ -s "$BOLD" ] && [ -s "$LICENSE" ]; then
  echo "缓存已存在，跳过下载：$CACHE"
  ls -la "$CACHE" | awk 'NR>1{printf "  %-28s %s bytes\n", $9, $5}'
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "下载 $PKG ..."
( cd "$TMP" && npm pack "$PKG" >/dev/null 2>&1 ) || { echo "❌ npm pack 失败"; exit 1; }
TGZ=$(ls "$TMP"/*.tgz 2>/dev/null | head -1)
[ -n "$TGZ" ] || { echo "❌ 未找到 tarball"; exit 1; }

tar -xzf "$TGZ" -C "$TMP"
SRC="$TMP/package"
[ -f "$SRC/400Regular/NotoSansSC_400Regular.ttf" ] || { echo "❌ 包结构变了，缺少 400Regular"; exit 1; }

mkdir -p "$CACHE"
cp "$SRC/400Regular/NotoSansSC_400Regular.ttf" "$REGULAR"
cp "$SRC/700Bold/NotoSansSC_700Bold.ttf"       "$BOLD"
[ -f "$SRC/LICENSE_FONT" ] && cp "$SRC/LICENSE_FONT" "$LICENSE"

echo "✅ 已就绪："
printf "  Regular  %s (%s bytes)\n" "$REGULAR" "$(stat -f%z "$REGULAR")"
printf "  Bold     %s (%s bytes)\n" "$BOLD" "$(stat -f%z "$BOLD")"
printf "  许可     %s\n" "$LICENSE"
