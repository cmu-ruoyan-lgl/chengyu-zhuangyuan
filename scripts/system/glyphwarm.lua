-- 字形预热（B1 风险的 P2 兜底措施）。
--
-- 背景：NanoVG 的字形图集是按需光栅化的，某个字第一次出现时才进图集，
--       首次出现会有一帧抖动/掉帧。P2 方案在「进关瞬间」把本关会用到的字
--       一次性光栅化掉，之后整关都命中缓存，成本可控、风险为零。
--
-- 实现：开一个临时 NanoVG 上下文，把字逐个 nvgText 一遍（位置无关，
--       fontstash 在 text 迭代阶段就会为字形分配图集节点并光栅化），然后立即销毁。

local Config = require("core.config")

local M = {}

local FONT_PATH = "Fonts/MiSans-Regular.ttf"

--- 预热一批字。返回 true / false, 原因
function M.warmup(chars, fontSize)
    if type(chars) ~= "table" or #chars == 0 then return false, "无字可预热" end
    if type(nvgCreate) ~= "function" then return false, "当前环境无 NanoVG" end

    local size = fontSize or Config.num("glyph.warmup_font_size", 40)
    local ok, ctx = pcall(nvgCreate, 1)
    if not ok or ctx == nil then
        return false, "nvgCreate 失败（headless？）"
    end

    local okFont, fontId = pcall(nvgCreateFont, ctx, "warm", FONT_PATH)
    if not okFont or fontId == -1 then
        pcall(nvgDelete, ctx)
        return false, "字体加载失败: " .. FONT_PATH
    end

    local okFrame = pcall(function()
        nvgBeginFrame(ctx, 64, 64, 1.0)
        nvgFontSize(ctx, size)
        nvgFontFaceId(ctx, fontId)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 1))
        for i = 1, #chars do
            nvgText(ctx, -1000, -1000, tostring(chars[i]), nil)
        end
        nvgEndFrame(ctx)
    end)

    pcall(nvgDelete, ctx)
    if not okFrame then return false, "预热绘制失败" end
    return true, nil, #chars
end

--- 预热当前关卡（棋盘答案字 + 备选区字）
function M.warmupLevel(grid, bank, fontSize)
    local chars = {}
    if grid and grid.distinctChars then
        for _, ch in ipairs(grid:distinctChars()) do chars[#chars + 1] = ch end
    end
    for _, ch in ipairs(bank or {}) do chars[#chars + 1] = ch end
    -- 去重
    local seen, out = {}, {}
    for _, ch in ipairs(chars) do
        if not seen[ch] then seen[ch] = true; out[#out + 1] = ch end
    end
    -- P2 上限保护：超了就只预热前 N 个，避免单帧开销过大
    local cap = Config.num("glyph.max_distinct_chars_per_level", 80)
    if #out > cap then
        local trimmed = {}
        for i = 1, cap do trimmed[i] = out[i] end
        out = trimmed
    end
    return M.warmup(out, fontSize)
end

return M
