-- 共享 UI 组件（中国风「漆底 + 宣纸 + 描金」）。
-- 集中配色/字号/圆角/投影的读取口径，避免各页重复实现导致风格漂移。
-- 所有数值读 config（ui.color / ui.font_size / ui.fx），禁止硬编码。
-- 本模块属 UI 层：不读游戏状态，只做样式与布局。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")

local W = {}

------------------------------------------------------------------------------
-- 基础工具
------------------------------------------------------------------------------

function W.pct(x)
    return string.format("%.4f%%", x * 100)
end

--- 颜色统一走 config
function W.c(key, default)
    return Config.color("ui.color." .. key, default or { 0, 0, 0, 255 })
end

function W.withAlpha(color, alpha)
    return { color[1], color[2], color[3], alpha }
end

--- 投影（卡片/棋子统一风格）
function W.shadow(blur, y, alpha, colorKey)
    local col = colorKey and W.c(colorKey) or { 0, 0, 0, 255 }
    return { { x = 0, y = y or 6, blur = blur or 18, spread = 0,
               color = W.withAlpha(col, alpha or 90) } }
end

--- 棋子/字块基础质感：落影 + 顶部内高光
function W.pieceShadow()
    return {
        { x = 0, y = 3, blur = 8, spread = 0, color = { 60, 40, 20, 60 } },
        { x = 0, y = 2, blur = 0, spread = 0, color = { 255, 255, 255, 60 }, inset = true },
    }
end

--- 跑一个关键帧动画（失败静默降级为静态呈现）
function W.anim(widget, config)
    if not widget or not widget.Animate then return false end
    local ok = pcall(function() widget:Animate(config) end)
    return ok
end

--- 长文案手动断行：按字符数切成每行 ≤ perLine 字（Label 不会自动换行，
--- 一行长文案会被横向裁断——S6-3/S7 实测）。UTF-8 安全。
function W.wrapLines(text, perLine)
    local lines, cur, n = {}, "", 0
    for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if ch == "\n" then
            lines[#lines + 1] = cur
            cur, n = "", 0
        else
            cur = cur .. ch
            n = n + 1
            if n >= perLine then
                lines[#lines + 1] = cur
                cur, n = "", 0
            end
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------------
-- 组件
------------------------------------------------------------------------------

--- 图标贴片：assets/sprites/icons/icon_<key>.png 存在则显示贴图，
--- 缺失时回退纯色圆点（图标资产不齐不破版，后续可无脑补 PNG）。
function W.iconOrDot(key, size, dotColor)
    size = size or 22
    local src = "sprites/icons/icon_" .. key .. ".png"
    if cache:Exists(src) then
        return UI.Panel {
            width = size, height = size,
            backgroundImage = src,
            backgroundFit = "contain",
            marginRight = 10,
        }
    end
    return UI.Panel {
        width = size, height = size,
        borderRadius = size / 2,
        backgroundColor = dotColor,
        marginRight = 10,
    }
end

--- 顶栏信息胶囊（漆底 + 描金边）
function W.chip(label, opts)
    opts = opts or {}
    local fontSize = opts.fontSize or Theme.font("topbar", 26) * 0.85
    local dot = nil
    if opts.icon then
        dot = W.iconOrDot(opts.icon, opts.iconSize or 22, opts.dotColor)
    elseif opts.dotColor then
        dot = UI.Panel {
            width = 18, height = 18,
            borderRadius = 9,
            backgroundColor = opts.dotColor,
            marginRight = 10,
        }
    end
    local text = UI.Label {
        text = label,
        fontSize = fontSize,
        fontColor = opts.fg or W.c("text_light"),
        fontWeight = opts.bold and "bold" or nil,
        flexShrink = 1,
    }
    local kids = {}
    if dot then kids[#kids + 1] = dot end
    kids[#kids + 1] = text
    local self = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 16,
        paddingVertical = 4,
        flexShrink = 1,
        borderRadius = 28,
        backgroundColor = opts.bg or W.c("chip_bg"),
        borderWidth = 2,
        borderColor = opts.border or W.c("chip_edge"),
        boxShadow = W.shadow(10, 3, 70, opts.glow),
        onClick = opts.onClick,
        children = kids,
    }
    self._label = text
    return self
end

--- 更新胶囊文案（保留圆点与样式）
function W.chipText(chipWidget, text)
    if not chipWidget or not chipWidget._label then return end
    chipWidget._label:SetStyle({ text = text })
end

--- 道具胶囊按钮（描金渐变 + 投影）
function W.pillButton(text, onTap, opts)
    opts = opts or {}
    return UI.Button {
        text = text,
        fontSize = opts.fontSize or Theme.font("toolbar", 28),
        flexGrow = opts.grow or 1,
        marginHorizontal = opts.marginHorizontal or 7,
        paddingVertical = opts.paddingVertical or 14,
        paddingHorizontal = opts.paddingHorizontal or 0,
        borderRadius = 30,
        backgroundColor = opts.bg or W.c("gold_deep"),
        backgroundGradient = opts.gradient or {
            direction = "to-bottom",
            from = W.c("gold"),
            to = W.c("gold_deep"),
        },
        textColor = opts.fg or W.c("ink"),
        fontWeight = "bold",
        boxShadow = {
            { x = 0, y = 6, blur = 16, spread = 0, color = W.withAlpha(W.c(opts.glow or "gold_dark"), 130) },
            { x = 0, y = 2, blur = 0, spread = 0, color = { 255, 248, 230, 90 }, inset = true },
        },
        borderWidth = 2,
        borderColor = W.c("gold_dark"),
        disabled = opts.disabled == true,
        onClick = onTap,
    }
end

------------------------------------------------------------------------------
-- 分页/卡片（S2 各系统页共用）
------------------------------------------------------------------------------

--- 分区卡片：宣纸底 + 标题条
function W.sectionCard(title, children, opts)
    opts = opts or {}
    local header = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            UI.Label {
                text = title,
                fontSize = Theme.font("topbar", 26),
                fontColor = W.c("ink"),
                fontWeight = "bold",
                flexShrink = 1,
            },
        },
    }
    if opts.subtitle then
        header:AddChild(UI.Label {
            text = opts.subtitle,
            fontSize = Theme.font("caption", 24),
            fontColor = W.c("ink_dim"),
            flexShrink = 1,
        })
    end
    local kids = { header }
    for _, ch in ipairs(children or {}) do kids[#kids + 1] = ch end
    return UI.Panel {
        width = "100%",
        borderRadius = 26,
        backgroundColor = W.c("panel"),
        borderWidth = 3,
        borderColor = W.c("panel_edge"),
        boxShadow = W.shadow(20, 8, 110),
        paddingHorizontal = 24,
        paddingVertical = 20,
        marginBottom = 18,
        children = kids,
    }
end

--- 一行信息：左文案 + 右数值
function W.infoRow(label, value, opts)
    opts = opts or {}
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        marginTop = opts.marginTop or 8,
        children = {
            UI.Label {
                text = label,
                fontSize = Theme.font("caption", 24),
                fontColor = opts.labelColor or W.c("ink_dim"),
                flexShrink = 1,
            },
            UI.Label {
                text = value,
                fontSize = Theme.font("caption", 24),
                fontColor = opts.valueColor or W.c("ink"),
                fontWeight = "bold",
                flexShrink = 1,
            },
        },
    }
end

--- 进度条（ratio 0~1）
function W.progressBar(ratio, opts)
    opts = opts or {}
    local fill = UI.Panel {
        width = W.pct(math.max(0, math.min(1, ratio or 0))),
        height = "100%",
        borderRadius = 8,
        backgroundGradient = opts.gradient or {
            direction = "to-right",
            from = W.c("gold"),
            to = W.c("gold_deep"),
        },
    }
    return UI.Panel {
        width = "100%",
        height = opts.height or 16,
        marginTop = opts.marginTop or 12,
        borderRadius = 8,
        backgroundColor = W.withAlpha(W.c("chip_bg"), 235),
        borderWidth = 2,
        borderColor = W.c("chip_edge"),
        flexDirection = "row",
        children = { fill },
    }
end

--- 顶栏：返回按钮 + 标题 + 右侧胶囊（space-between 三段，左右对称）
function W.pageHeader(title, chips, onBack)
    local kids = {
        UI.Button {
            text = "返回",
            fontSize = Theme.font("topbar", 26),
            paddingHorizontal = 22,
            paddingVertical = 8,
            borderRadius = 26,
            backgroundColor = W.c("chip_bg"),
            borderWidth = 2,
            borderColor = W.c("chip_edge"),
            textColor = W.c("ink"),
            fontWeight = "bold",
            boxShadow = W.shadow(12, 4, 90),
            onClick = onBack,
        },
        UI.Label {
            text = title,
            fontSize = Theme.font("topbar", 26) * 1.05,
            fontColor = W.c("ink"),
            fontWeight = "bold",
            flexShrink = 1,
        },
    }
    local list = chips or {}
    if #list == 0 then
        list = { W.chip("金币 " .. tostring(require("system.game").gold()),
            { dotColor = W.c("coin"), fg = W.c("gold_dark") }) }
    end
    for _, ch in ipairs(list) do kids[#kids + 1] = ch end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = 24,
        paddingVertical = 12,
        flexShrink = 1,
        children = kids,
    }
end

return W
