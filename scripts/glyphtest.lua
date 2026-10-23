-- 字形图集容量 / 中文渲染验证脚本（M0 技术验证用，非游戏逻辑）
--
-- 渲染 N 个不重复汉字，用于：
--   ① 中文字形是否真的渲染出来（无豆腐块/空白）
--   ② NanoVG 字形图集（glyph atlas）容量上限 —— 图集装满后新字形不再光栅化，表现为缺字
--   ③ 大量文本控件的帧率观察
--
-- 用法（项目根）：
--   验证（无窗口，快）：
--     .cli/UrhoXRuntime glyphtest.lua -tapcode_dir=<根> -tool_mode -graphicsheadless -nosound \
--       -validate -validate-frames=60 -validate-output=<根>/.tmp/validate-glyph.json
--   截图（macOS 需桌面窗口，输出真实像素）：
--     .cli/UrhoXRuntime glyphtest.lua -tapcode_dir=<根> -tool_mode -nosound \
--       -screenshot=<根>/.tmp/shot.png -screenshot-frame=140 -x 1080 -y 1920
local UI = require("urhox-libs/UI")

local ok, chars = pcall(require, "_glyphchars")
if not ok or type(chars) ~= "table" then
    chars = { "成", "语", "小", "秀", "才" }
    print("[glyphtest] WARN: 未找到 _glyphchars，使用 5 字回退列表")
end

local N = #chars
local FONT_SIZE = 40

-- 百分比布局：不依赖具体分辨率，保证所有字形都在可视区内被真正渲染
local cols = math.ceil(math.sqrt(N * 9 / 16))
local rows = math.ceil(N / cols)
local cellWPct = tostring(100 / cols) .. "%"
local rowHPct = tostring(100 / rows) .. "%"

UI.Init({
    theme = "default-dark",
    scale = UI.Scale.DEFAULT,
    -- 显式指定字体：本地运行时不含 NotoSansSC，不指定会 fallback 失败
    fonts = {
        { family = "sans", weights = { normal = "Fonts/NotoSansSC-Regular.ttf", bold = "Fonts/NotoSansSC-Bold.ttf" } },
    },
})

local idx = 1
local rowChildren = {}
for r = 1, rows do
    local cells = {}
    for c = 1, cols do
        if idx <= N then
            cells[c] = UI.Label {
                text = chars[idx],
                fontSize = FONT_SIZE,
                fontColor = { 255, 255, 255, 255 },
                width = cellWPct,
                height = "100%",
                flexShrink = 1,
                textAlign = "center",
                verticalAlign = "middle",
            }
            idx = idx + 1
        end
    end
    rowChildren[r] = UI.Panel {
        width = "100%",
        height = rowHPct,
        flexDirection = "row",
        flexShrink = 1,
        children = cells,
    }
end

local root = UI.Panel {
    width = "100%",
    height = "100%",
    flexDirection = "column",
    backgroundColor = { 18, 18, 22, 255 },
    children = rowChildren,
}

UI.SetRoot(root)

print(string.format(
    "[glyphtest] chars=%d fontSize=%d grid=%dx%d cellW=%s rowH=%s",
    N, FONT_SIZE, cols, rows, cellWPct, rowHPct))
