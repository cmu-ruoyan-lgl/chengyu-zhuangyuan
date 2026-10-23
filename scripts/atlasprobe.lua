-- NanoVG 字形图集（glyph atlas）容量探针 · M0 技术验证用，非游戏逻辑
--
-- 原理：
--   nvgText() 走 fontstash 的 FONS_GLYPH_BITMAP_REQUIRED 路径，会为字形在图集上分配
--   节点并光栅化；其返回值是 horizontal advance。若图集分配失败（满 / 未初始化），
--   字形不会被光栅化，advance 塌为 0。因此 advance>0 即为「该字形成功进图集」。
--   对照实验：把同一个已光栅化字形重复绘制 N 次，若图集真在工作，命中缓存应显著快于
--   N 个不同字形；两者耗时接近则说明当前环境根本不做光栅化（探针无效）。
--
-- 用法（项目根）：
--   python3 tools/make_glyphlist.py --count 3000
--   PYTHON=python3 LUAC=luac54 bash tools/verify.sh atlasprobe.lua
--   然后看 .tmp/validate-atlasprobe.json 与 stdout 中的 [atlasprobe] 行
local ok, chars = pcall(require, "_glyphchars")
if not ok or type(chars) ~= "table" then
    print("[atlasprobe] ERROR: 未找到 scripts/_glyphchars.lua，请先跑 make_glyphlist.py")
    return
end

local N = #chars
-- 字号可通过环境变量覆盖，用于做「必然撑爆图集」的对照实验：
--   ATLAS_FONT_SIZE=200 时，20976 字需 ~839M px²，任何真实图集都装不下；
--   若此时仍 fail=0，说明当前环境的图集无真实容量约束（headless 下测量值不可外推到真机）。
local FONT_SIZE = tonumber(os.getenv("ATLAS_FONT_SIZE") or "") or 40
local FONT_PATH = "Fonts/NotoSansSC-Regular.ttf"

print(string.format("[atlasprobe] start N=%d fontSize=%d font=%s", N, FONT_SIZE, FONT_PATH))

local ctx = nvgCreate(1)
if ctx == nil then
    print("[atlasprobe] ERROR: nvgCreate 返回 nil（BGFX 后端未初始化？）")
    return
end
print("[atlasprobe] nvgCreate ok")

local fontId = nvgCreateFont(ctx, "probe", FONT_PATH)
print("[atlasprobe] fontId=" .. tostring(fontId))
if fontId == -1 then
    print("[atlasprobe] ERROR: 字体加载失败，中止")
    return
end

-- 探针主体：一帧内把所有字形各绘制一次，逐个记录 advance
nvgBeginFrame(ctx, 1080, 1920, 1.0)
nvgFontSize(ctx, FONT_SIZE)
nvgFontFaceId(ctx, fontId)

local t0 = os.clock()
local okCount, failCount = 0, 0
local firstFailIdx, firstFailChar, firstFailAdv = -1, nil, nil
local sampleFails = {}
for i, ch in ipairs(chars) do
    local adv = nvgText(ctx, 10, 10, ch, nil)
    if type(adv) == "number" and adv > 0.5 then
        okCount = okCount + 1
    else
        failCount = failCount + 1
        if firstFailIdx < 0 then
            firstFailIdx, firstFailChar, firstFailAdv = i, ch, adv
        end
        if #sampleFails < 12 then
            sampleFails[#sampleFails + 1] = string.format("%d=%s(adv=%s)", i, tostring(ch), tostring(adv))
        end
    end
end
local t1 = os.clock()

-- 对照 A：重复绘制第 1 个字形 N 次（已光栅化，应命中缓存）
local t2 = os.clock()
local repAdv = -1
for _ = 1, N do
    repAdv = nvgText(ctx, 10, 10, chars[1], nil)
end
local t3 = os.clock()

-- 对照 B：回测最早的一批字形。若图集满了之后是「整体重置/淘汰」而非「拒绝新字形」，
--         这些早期字形已被挤出，重绘耗时应与新字形同级（而非命中缓存的近乎零成本）。
local backN = math.min(1000, N)
local t4 = os.clock()
local backOk = 0
for i = 1, backN do
    local adv = nvgText(ctx, 10, 10, chars[i], nil)
    if type(adv) == "number" and adv > 0.5 then backOk = backOk + 1 end
end
local t5 = os.clock()

nvgEndFrame(ctx)

print(string.format(
    "[atlasprobe] BACKTEST n=%d ok=%d ms=%.2f per_glyph_ms=%.4f (cache 级应 <0.001，若接近 %.4f 说明早期字形已被挤出图集)",
    backN, backOk, (t5 - t4) * 1000, (t5 - t4) * 1000 / backN, (t1 - t0) * 1000 / N))

print(string.format(
    "[atlasprobe] RESULT N=%d ok=%d fail=%d first_fail_idx=%d char=%s adv=%s distinct_ms=%.1f repeat_ms=%.1f repAdv=%.2f",
    N, okCount, failCount, firstFailIdx, tostring(firstFailChar), tostring(firstFailAdv),
    (t1 - t0) * 1000, (t3 - t2) * 1000, type(repAdv) == "number" and repAdv or -1))
if #sampleFails > 0 then
    print("[atlasprobe] sample_fails: " .. table.concat(sampleFails, " "))
end
print("[atlasprobe] done")
