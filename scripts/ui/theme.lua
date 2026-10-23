-- 主题：字号 / 颜色 / 间距 / 布局比例。
-- 所有数值来自 data/config.json（ui.*），大字模式按 ui.big_text_scale 整体缩放。
-- UI 层任何硬编码颜色、字号都视为缺陷。

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

--- 字号（hanzi / topbar / toolbar / caption）
function M.font(key, default)
    return Config.num("ui.font_size." .. key, default or 24) * M.scaleFactor()
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
