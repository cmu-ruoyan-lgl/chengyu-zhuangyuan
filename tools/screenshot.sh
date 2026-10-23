#!/usr/bin/env bash
# 渲染截图（视觉验证）。
#
# ⚠️ 必须在你自己的「终端 App」里跑，不要在 WorkBuddy 的会话里跑。
#    原因：本运行时的 macOS 构建没有 surfaceless EGL
#    （`-graphicssurfaceless ignored: this build lacks surfaceless EGL support`），
#    截图必须能开真实窗口；而 Agent 的执行上下文拿不到 GUI 会话，恒定为
#    `graphics headless`，产不出 PNG。
#
# 用法：
#   bash tools/screenshot.sh                      # 默认渲染 glyphtest.lua
#   bash tools/screenshot.sh main.lua             # 指定入口脚本
#   bash tools/screenshot.sh main.lua out.png 120 # 指定输出与帧号
#
# 产物写到 .tmp/ 下，跑完把 PNG 路径发给我，我可以直接看图分析。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="${1:-glyphtest.lua}"
OUT="${2:-$ROOT/.tmp/shot.png}"
FRAME="${3:-60}"
W="${4:-1080}"
H="${5:-1920}"

mkdir -p "$(dirname "$OUT")"

echo "entry : $ENTRY"
echo "output: $OUT (frame $FRAME, ${W}x${H})"

"$ROOT/.cli/UrhoXRuntime" "$ENTRY" \
  -tapcode_dir="$ROOT" \
  -tool_mode \
  -nosound \
  -screenshot="$OUT" \
  -screenshot-frame="$FRAME" \
  -x "$W" -y "$H"

if [ -s "$OUT" ]; then
  echo "✅ 截图成功: $OUT ($(stat -f%z "$OUT") bytes)"
else
  echo "❌ 未产出 PNG。常见原因："
  echo "   1) 在 WorkBuddy 会话内执行（无 GUI 会话）→ 改用系统终端 App"
  echo "   2) 入口脚本在 frame $FRAME 之前就退出了 → 调小 --frame"
  exit 1
fi
