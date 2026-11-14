-- 字形预热（B1 风险的 P2 措施）。
--
-- 背景：NanoVG 的字形图集按需光栅化，某字第一次出现时才进图集，
--       首次出现可能有一帧抖动。P2 在「进关瞬间」把本关用到的字一次光栅化掉。
--
-- 关键教训（RISK S1-13）：
--   ① 必须预热 UI 实际使用的 NanoVG 上下文（UI.GetNVGContext()）。
--      早期版本自建临时 ctx 预热完就删 —— 图集是 per-context 的，白预热。
--   ② 字形条目按 (字体 face × 字号 × codepoint) 缓存，face/字号不一致同样白预热。
--      UI.Render 以 DPR=UI.GetScale() 起帧，预热必须复刻同一 DPR。
--   ③ 对 UI 上下文绝不能 nvgDelete。

local Config = require("core.config")

local M = {}

-- headless 兜底校验用的字体：必须是「UI 实际渲染的主字体」。
-- MiSans-*.ttf 只是引擎二进制硬编码加载路径的极小占位（见 assets/Fonts/README.md），
-- 用它预热中文字会全部落空，故此处指向 default-dark 主题注册的 sans 主字体。
local FONT_PATH = "Fonts/NotoSansSC-Regular.ttf"

-- UI 常用文案字（顶栏/工具栏/弹门/横幅等）。level 字由 warmupLevel 另算。
-- 注意：新增 UI 文案后需同步此处；字体子集构建脚本会自动收集 Lua 里的中文字。
local CHROME_CHARS = "第关体力金币提示撤销洗牌下一关成语小状元稍后再来不足看广告得跳过成功失败继续本已通关剩余次数"
local CHROME_SIZES = { 24, 26, 28 }   -- caption / topbar / toolbar

--- 在指定上下文上光栅化一批字（单字号、单字体）。
local function rasterize(ctx, dpr, fontFace, chars, size)
    nvgBeginFrame(ctx, 64, 64, dpr)
    nvgFontSize(ctx, size)
    if fontFace then nvgFontFace(ctx, fontFace) end
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 1))
    for i = 1, #chars do
        nvgText(ctx, -10000, -10000, tostring(chars[i]), nil)
    end
    nvgEndFrame(ctx)
end

local function toChars(s)
    local out = {}
    for _, c in utf8.codes(s) do out[#out + 1] = utf8.char(c) end
    return out
end

--- 预热 UI 上下文。chars+size 指定一批；返回 true/false, 原因, 字数
local function warmupUI(chars, size)
    local okUI, UI = pcall(require, "urhox-libs/UI")
    if not okUI or type(UI.GetNVGContext) ~= "function" then
        return false, "无 UI 上下文"
    end
    local ctx = UI.GetNVGContext()
    if ctx == nil then return false, "UI 未初始化" end
    local dpr = (type(UI.GetScale) == "function" and UI.GetScale()) or 1.0
    local ok, err = pcall(function()
        -- 与主题 FontFace 映射一致：正文 sans，粗体 sans-bold
        rasterize(ctx, dpr, "sans", chars, size)
        rasterize(ctx, dpr, "sans-bold", chars, size)
    end)
    if not ok then return false, tostring(err) end
    return true, nil, #chars
end

--- 预热 UI 骨架文案（顶栏/按钮/弹门）。在 play 页挂载时调用一次即可。
function M.warmupChrome()
    if not Config.get("glyph.warmup_on_level_start", true) then return false, "已关闭" end
    local chars = toChars(CHROME_CHARS)
    for _, size in ipairs(CHROME_SIZES) do
        local ok, err = warmupUI(chars, size)
        if not ok then return false, err end
    end
    return true, nil, #chars
end

--- 预热一批字（关卡用）。返回 true / false, 原因, 字数
function M.warmup(chars, fontSize)
    if type(chars) ~= "table" or #chars == 0 then return false, "无字可预热" end
    local size = fontSize or Config.num("glyph.warmup_font_size", 40)
    local ok, _, n = warmupUI(chars, size)
    if ok then return true, nil, n end

    -- 兜底：无 UI 上下文（headless validate）时退回临时上下文，
    -- 仅为验证字体可读，不产生运行效益。
    if type(nvgCreate) ~= "function" then return false, "当前环境无 NanoVG" end
    local okC, ctx = pcall(nvgCreate, 1)
    if not okC or ctx == nil then return false, "nvgCreate 失败（headless？）" end
    local okFont, fontId = pcall(nvgCreateFont, ctx, "warm", FONT_PATH)
    if okFont and fontId ~= -1 then
        pcall(function()
            nvgFontFaceId(ctx, fontId)
            rasterize(ctx, 1.0, nil, chars, size)
        end)
    end
    pcall(nvgDelete, ctx)   -- 临时上下文可以删；UI 上下文绝不删
    return false, "UI 上下文不可用（已用临时上下文兜底验证）"
end

--- 预热当前关卡（棋盘答案字 + 备选区字）+ UI 骨架文案
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
    M.warmupChrome()
    return M.warmup(out, fontSize)
end

return M
