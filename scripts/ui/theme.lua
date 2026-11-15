-- 主题：字号 / 颜色 / 间距 / 布局比例。
-- 所有数值来自 data/config.json（ui.*），大字模式按 ui.big_text_scale 整体缩放。
-- UI 层任何硬编码颜色、字号都视为缺陷。
--
-- S27：新增「视口字号自适应」与「顶部安全区」。
--   项目样式基准是 ui.design_width(1080)，但引擎默认缩放（DPR_DENSITY_ADAPTIVE）在真机上
--   给出的逻辑视口只有约 550~560 base px；固定字号不随视口收缩就会相对屏幕放大近一倍，
--   表现为启动页标题折行、提示字过大、顶栏胶囊挤成一团。字号按 vw/design_width 等比缩放，
--   容器用百分比布局不受影响，因此只缩字、不改棋盘/按钮的物理尺寸。

local UI = require("urhox-libs/UI")
local Config = require("core.config")

local M = {
    bigText = false,
}

--- 大字模式开关（settings.big_text 驱动，切换后重建当前页）
function M.setBigText(enabled)
    M.bigText = enabled and true or false
end

function M.isBigText()
    return M.bigText
end

function M.scaleFactor()
    if not M.bigText then return 1 end
    return Config.num("ui.big_text_scale", 1.2)
end

--- 视口字号系数：桌面/本地 validate（vw ≥ design_width）恒为 1；窄屏按宽度等比缩小并限幅。
--- 任何取数失败都退化为 1，保证 validate / 无 UI 上下文的调用不炸。
function M.viewportFontScale()
    if not Config.get("ui.font_auto_fit", true) then return 1 end
    local ok, vw = pcall(function() return UI.GetWidth() end)
    if not ok or type(vw) ~= "number" or vw <= 0 then return 1 end
    local design = Config.num("ui.design_width", 1080)
    if design <= 0 then return 1 end
    local lo = Config.num("ui.font_fit_min", 0.58)
    local hi = Config.num("ui.font_fit_max", 1.0)
    return math.max(lo, math.min(hi, vw / design))
end

--- 字号（hanzi / topbar / toolbar / caption / title ...）
function M.font(key, default)
    return Config.num("ui.font_size." .. key, default or 24)
        * M.scaleFactor() * M.viewportFontScale()
end

--- 与「固定尺寸容器」绑定的字（棋子/汉字）：只随大字模式缩放，不随视口收缩。
--- 棋盘格、字块的边长是按宽∩高算出来的物理尺寸，汉字必须跟着格子走；
--- 若也乘 viewportFontScale，真机上会出现「大格子里一个很小的字」。
function M.fontRaw(key, default)
    return Config.num("ui.font_size." .. key, default or 24) * M.scaleFactor()
end

--- 供固定间距/内边距使用：与字号同比例收缩，避免「字小了但胶囊还是鼓的」。
function M.fit(value)
    return value * M.viewportFontScale()
end

--- 顶部安全区（刘海 + TapTap 宿主退出胶囊），单位 base px。
--- UI.GetSafeAreaInsets() 只给系统安全区；胶囊要单独从 sdk:GetNativeExitMenuRect() 合并，
--- 算法与引擎 UI.SafeAreaView 的 nativeMenuInset 一致。无 sdk（Web/validate）时自动退化为 0。
function M.safeTop()
    local top = 0
    local ok, insets = pcall(function() return UI.GetSafeAreaInsets() end)
    if ok and type(insets) == "table" and type(insets.top) == "number" then
        top = insets.top
    end
    local host = _G.sdk
    if host ~= nil then
        pcall(function()
            if host.GetNativeExitMenuRect == nil then return end
            local rect = host:GetNativeExitMenuRect()
            if not rect or not rect.bottom then return end
            local scale = UI.GetScale() or 1
            if scale <= 0 then return end
            local bottom = rect.bottom * graphics.height / scale
            if bottom > top then top = bottom end
        end)
    end
    if top > 0 then
        top = top + Config.num("ui.safe_top_extra", 18)
    end
    return top
end

--- 标题单行安全字号：按「可用宽 / (字数 + 字距余量)」封顶，杜绝最后一个字折行。
function M.titleFontSize(chars, sidePadding, multiplier)
    local base = M.font("title", 56) * (multiplier or 1.15)
    local ok, vw = pcall(function() return UI.GetWidth() end)
    if not ok or type(vw) ~= "number" or vw <= 0 then return base end
    local usable = vw - (sidePadding or 30) * 2
    local byWidth = usable / ((chars or 5) + 0.7)
    return math.min(base, byWidth)
end

--- 颜色（config 里存 [r,g,b,a]）
function M.color(key, default)
    return Config.color("ui.color." .. key, default or { 0, 0, 0, 255 })
end

--- 布局比例（topbar / board / bank / toolbar）
function M.ratio(key, default)
    return Config.num("ui.layout_ratio." .. key, default or 0.1)
end

--- 其它 UI 数值（cell_gap / cell_radius / bank_block_min ...）
function M.num(key, default)
    return Config.num("ui." .. key, default or 0)
end

return M
