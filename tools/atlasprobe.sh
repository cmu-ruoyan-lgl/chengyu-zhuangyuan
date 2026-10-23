#!/usr/bin/env bash
# NanoVG 字形图集（glyph atlas）容量实测
#
# 背景（很重要，别再用旧方式跑）：
#   1) -validate 模式在本运行时里会强制 headless 渲染
#      （日志必现 `shader compile skipped (graphics headless)`），
#      此时 NanoVG shader 不编译、图集纹理不真实分配 → 图集表现为「无限大」，
#      测出来的「20976 字全过」是假象，不能外推到真机。
#   2) -graphicssurfaceless 在本 macOS 构建里被忽略（缺 surfaceless EGL）。
#   → 唯一能拿到真实渲染上下文的路径：不开 headless，让 BGFX 真实初始化。
#      本脚本因此**不带 -validate**，改用 -screenshot 在第 N 帧出图后自动退出，
#      既能拿到真实 GPU 上下文，又把「能否出图」和「图集容量」一次测完。
#
# 两个必须注意的参数（来自 run-lua-validate SKILL.md）：
#   -tool_mode              资源从随包 pak 加载，不依赖散文件目录 —— **必须**，
#                           缺了会报 `Failed to add resource path 'Data'` 并弹错误框
#   -graphicsheadless       **本脚本绝不能带**，带了就测不出容量
#   -w                      窗口模式，避免真机/桌面跑成全屏
#
# 它必须在「能开窗口的桌面会话」里跑 —— 也就是你自己的终端 App。
# Agent 上下文拿不到 GUI 会话，引擎会自动 fallback 到 headless，数据无效（脚本会自动提示）。
#
# 用法：
#   bash tools/atlasprobe.sh                       # 默认：40px 与 120px 两档，各 4000 字
#   PROBE_COUNT=8000 bash tools/atlasprobe.sh
#   PROBE_SIZES="40 80 120" bash tools/atlasprobe.sh
#   PROBE_TIMEOUT=90 bash tools/atlasprobe.sh      # 单档硬超时（秒），默认 45
#
# 判读：
#   每个字号都会打出 ✅/⚠️：⚠️ 表示本次是 headless，数字不能代表真机
#   fail = 0        → 容量 ≥ 该档字数，题库按该规模设计安全
#   fail > 0        → first_fail_idx 即为该字号下的图集容量（单位：字形数）
#   DPR 换算：真机实际光栅化字号 = fontSize × DPR。
#              40sp 在 DPR=3 的手机上是 120px，所以 120 那一档才是手机真值。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

COUNT="${PROBE_COUNT:-4000}"
SIZES="${PROBE_SIZES:-40 120}"
TIMEOUT="${PROBE_TIMEOUT:-45}"
FRAME="${PROBE_FRAME:-5}"
RT="$ROOT/.cli/UrhoXRuntime"

if [ ! -x "$RT" ]; then
    echo "ERROR: 缺少 $RT，请先跑 python3 .cli/install-urhox-runtime.py --dest .cli"
    exit 1
fi

echo "== 生成字表：$COUNT 个不重复汉字 =="
python3 tools/make_glyphlist.py --count "$COUNT" || exit 1

mkdir -p .tmp
SUMMARY=""
ANY_INVALID=0

for SIZE in $SIZES; do
    LOG="$ROOT/.tmp/atlas-${SIZE}.log"
    PNG="$ROOT/.tmp/atlas-${SIZE}.png"
    rm -f "$PNG"
    echo
    echo "===== 字号 ${SIZE}px ====="

    # 用看门狗兜底：headless 环境下 -screenshot 不会触发退出，进程会挂住
    ATLAS_FONT_SIZE="$SIZE" "$RT" atlasprobe.lua \
        -tapcode_dir="$ROOT" \
        -tool_mode \
        -w -nosound -x 1080 -y 1920 \
        -screenshot="$PNG" -screenshot-frame="$FRAME" >"$LOG" 2>&1 &
    PID=$!
    ( sleep "$TIMEOUT"; kill -9 "$PID" 2>/dev/null ) &
    WD=$!
    wait "$PID" 2>/dev/null
    kill "$WD" 2>/dev/null
    wait "$WD" 2>/dev/null

    RESULT=$(grep "\[atlasprobe\] RESULT" "$LOG" | tail -1 | sed 's/.*\[atlasprobe\] //')
    if [ -z "$RESULT" ]; then
        echo "  ❌ 未拿到结果行。日志尾部："
        tail -8 "$LOG" | sed 's/^/     /'
        SUMMARY="${SUMMARY}\n  ${SIZE}px : 无结果（见 .tmp/atlas-${SIZE}.log）"
        ANY_INVALID=1
        continue
    fi
    echo "  $RESULT"

    # 有效性自检（三重判据，任一命中即判 headless）：
    #   a) 日志出现 headless 标志
    #   b) 日志出现 [Screenshot] 失败信息
    #   c) 没有产出 PNG
    # 注意：本机 grep 是 toybox（非 GNU grep），BRE 的 \| 不生效，必须用 -E
    HEADLESS_FLAG=0
    grep -qE "graphics headless|shader compile skipped" "$LOG" && HEADLESS_FLAG=1
    grep -qE "\[Screenshot\].*(no Graphics|cannot|fail)" "$LOG" && HEADLESS_FLAG=1
    [ -s "$PNG" ] || HEADLESS_FLAG=1

    if [ "$HEADLESS_FLAG" -eq 1 ]; then
        echo "  ⚠️ 本次为 headless（无真实 GPU 上下文）→ 容量数字无效"
        echo "     - 日志标志: $(grep -cE 'graphics headless' "$LOG") 处"
        echo "     - PNG: $([ -s "$PNG" ] && echo "已产出" || echo "未产出（headless 无 Graphics 子系统）")"
        echo "     请在你的终端 App 里重跑（不要用 Agent 会话）"
        echo "     若终端里仍不出 PNG：该机无法测得容量 → 直接按 P2 保守方案执行（无需再测）"
        ANY_INVALID=1
        SUMMARY="${SUMMARY}\n  ${SIZE}px : ⚠️ headless，数据无效"
    else
        echo "  ✅ 真实渲染上下文（PNG 已产出 $(stat -f%z "$PNG") bytes）→ 数字有效"
        FAIL=$(echo "$RESULT" | grep -o "fail=[0-9]*" | cut -d= -f2)
        FIDX=$(echo "$RESULT" | grep -o "first_fail_idx=[-0-9]*" | cut -d= -f2)
        if [ "${FAIL:-1}" -eq 0 ]; then
            SUMMARY="${SUMMARY}\n  ${SIZE}px : ✅ 容量 ≥ ${COUNT}（fail=0）"
        else
            SUMMARY="${SUMMARY}\n  ${SIZE}px : 容量 ≈ ${FIDX} 字（fail=${FAIL}）"
        fi
    fi
done

echo
echo "===== 汇总 ====="
printf "%b\n" "$SUMMARY"
echo
echo "===== 判读 ====="
echo "  fail=0                → 容量 ≥ ${COUNT}，该规模题库安全"
echo "  fail>0                → first_fail_idx 就是容量上限（字形数）"
if [ "$ANY_INVALID" -eq 1 ]; then
    echo
    echo "  ⚠️ 至少有一档没拿到真实渲染上下文，结论不可用。"
    echo "     请在「终端 App」里重跑本脚本（WorkBuddy 会话内拿不到 GUI 会话）。"
    echo "     若终端里也出不来 PNG → 结论定为「本机测不了」，直接按 P2 保守方案落地，"
    echo "     P2 不阻塞任何开发，也不需要这个数字。"
fi
echo
echo "  重点关注 120 那一档：40sp 汉字在 DPR=3 的真机上按 120px 光栅化，"
echo "  容量与 DPR² 成反比，手机端才是真正的压力场景。"
