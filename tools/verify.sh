#!/usr/bin/env bash
# 运行 Lua 逻辑验证（headless），自动过滤引擎已知噪音。
#
# 用法：
#   bash tools/verify.sh [入口脚本名，默认 main.lua]
#
# 判定：只信报告中的真实错误；ShaderError / Frame time spike / audio 均属噪音。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="${1:-main.lua}"
PY="${PYTHON:-python3}"
# 语法检查必须与运行时一致：UrhoXRuntime 内嵌 Lua 5.4
LUAC="${LUAC:-$(command -v luac54 || command -v luac)}"
RT="$ROOT/.cli/UrhoXRuntime"

if [ ! -x "$RT" ]; then
  echo "缺少本地运行时，先执行："
  echo "  $PY $ROOT/.cli/install-urhox-runtime.py --dest $ROOT/.cli"
  exit 2
fi

mkdir -p "$ROOT/.tmp"
LUA="${LUA:-$(command -v lua54 || command -v lua)}"

# 1) 静态语法检查（luac -p，不做链接，快）
if [ -n "$LUAC" ]; then
  echo "--- 语法检查 $("$LUAC" -v 2>&1 | head -1) ---"
  syn_fail=0
  for d in scripts src; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
      if ! "$LUAC" -p "$f" 2>/tmp/luac.err; then
        echo "  ❌ $f"; sed 's/^/     /' /tmp/luac.err | head -3; syn_fail=1
      fi
    done < <(find "$ROOT/$d" -name '*.lua' | sort)
  done
  [ "$syn_fail" -eq 0 ] && echo "  ✅ 全部通过"
fi

# 1.5) 离线核心单测 + 关卡校验（不需要引擎，秒级反馈）
if [ -n "$LUA" ]; then
  echo "--- 核心单测 ---"
  "$LUA" "$ROOT/scripts/tools/run_tests.lua" | tail -1
  echo "--- 关卡校验 ---"
  "$LUA" "$ROOT/scripts/tools/verify_levels.lua" --all | tail -1
fi

# 2) 运行时 validate（headless）
"$RT" "$ENTRY" \
  -tapcode_dir="$ROOT" \
  -tool_mode \
  -graphicsheadless \
  -nosound \
  -validate \
  -validate-frames=60 \
  -validate-timeout=45 \
  -validate-spike-threshold=500 \
  -validate-output="$ROOT/.tmp/validate.json" >"$ROOT/.tmp/validate.log" 2>&1

"$PY" - "$ROOT/.tmp/validate.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    r = json.load(open(path))
except Exception as e:
    print(f"❌ 报告读取失败: {e}")
    sys.exit(2)

s = r.get("summary", {})
NOISE = ("[ShaderError]", "Frame time spike", "Could not initialize audio output")
real = [(ph, e) for ph, v in r.get("phases", {}).items() for e in v.get("errors", [])
        if not any(n in e.get("message", "") for n in NOISE)]

print(f"raw={r.get('result')} frames={r.get('frames_completed')} "
      f"lua={s.get('lua_errors')} res={s.get('resource_errors')} engine={s.get('engine_errors')}")
for ph, e in real:
    print(f"  [{ph}/{e.get('category')}] frame {e.get('frame')}: {e.get('message')}")
if r.get("missing_resources"):
    print("  missing:", r["missing_resources"])

bad = bool(real) or bool(r.get("missing_resources")) or r.get("result") == "TIMEOUT" \
      or r.get("test_result") == "FAILED"
print("❌ 有真实问题" if bad else "✅ 无脚本层问题（仅环境噪音）")
sys.exit(1 if bad else 0)
PYEOF
