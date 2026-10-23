-- 特效层：爆星星 / 金币雨 / 扩散光环 / 浮字。
-- 全部由 UI 关键帧动画驱动（opacity / translateX / translateY / scale / rotate），
-- 不依赖图片素材（素材配额受限时的程序化方案，裁决 #17 精神）。
--
-- 用法：
--   local layer = FX.newLayer()          -- 挂到 root（绝对定位全屏，默认隐藏）
--   FX.starBurst(layer, { x, y, count, radius, color })
--   FX.coinShower(layer, { count })
--   FX.ring(layer, { x, y, color })
--   FX.floatText(layer, { x, y, text, color })
--
-- 注意：特效层默认 visible=false —— 全屏 Panel 会拦截点击，
--       有活跃粒子时才显示，最后一个粒子结束自动隐藏。

local UI = require("urhox-libs/UI")
local Config = require("core.config")
local Theme = require("ui.theme")

local FX = {}

local function fxNum(key, default)
    return Config.num("ui.fx." .. key, default)
end

local function fxColor(key, default)
    return Config.color("ui.color." .. key, default)
end

--- 建特效层（调用方负责塞进 root 的 children）
function FX.newLayer()
    local layer = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        visible = false,
    }
    layer.fxActive_ = 0
    return layer
end

local function acquire(layer)
    if not layer then return false end
    layer.fxActive_ = (layer.fxActive_ or 0) + 1
    layer:SetVisible(true)
    return true
end

--- 粒子结束：计数归零时隐藏整层（避免拦截点击）
local function release(layer, child)
    if not layer then return end
    if child then pcall(function() layer:RemoveChild(child) end) end
    layer.fxActive_ = math.max(0, (layer.fxActive_ or 1) - 1)
    if layer.fxActive_ == 0 then
        layer:SetVisible(false)
        pcall(function() layer:ClearChildren() end)
    end
end

local function center(opts)
    local w = UI.GetWidth() or Config.num("ui.design_width", 1080)
    local h = UI.GetHeight() or Config.num("ui.design_height", 1920)
    return opts and opts.x or (w * 0.5), opts and opts.y or (h * 0.5)
end

--- 爆星星：从中心向四周放射，末段淡出缩小
function FX.starBurst(layer, opts)
    if not layer then return end
    opts = opts or {}
    local cx, cy = center(opts)
    local count = opts.count or fxNum("star_count", 14)
    local radius = opts.radius or fxNum("star_radius", 230)
    local dur = opts.duration or fxNum("star_duration", 0.75)
    local size = opts.size or fxNum("star_size", 18)
    local color = opts.color or fxColor("star", { 255, 216, 120, 255 })
    local glow = fxNum("star_glow", 16)
    local rot0 = opts.rotate or 0

    for i = 1, count do
        local ang = rot0 + (i - 1) * (2 * math.pi / count)
        -- 半径抖动，避免过于规整
        local r = radius * (0.72 + 0.28 * ((i * 37 % 13) / 13))
        local dx, dy = math.cos(ang) * r, math.sin(ang) * r
        local p = UI.Panel {
            position = "absolute",
            left = cx - size * 0.5, top = cy - size * 0.5,
            width = size, height = size,
            backgroundColor = color,
            borderRadius = size * 0.5,
            boxShadow = { {
                x = 0, y = 0, blur = glow, spread = 0,
                color = { color[1], color[2], color[3], 190 },
            } },
        }
        layer:AddChild(p)
        acquire(layer)
        pcall(function()
            p:Animate({
                keyframes = {
                    [0]    = { opacity = 1, scale = 0.2, translateX = 0, translateY = 0 },
                    [0.35] = { opacity = 1, scale = 1.25, translateX = dx * 0.45, translateY = dy * 0.45 },
                    [1]    = { opacity = 0, scale = 0.3, translateX = dx, translateY = dy },
                },
                duration = dur,
                easing = "easeOut",
                onComplete = function() release(layer, p) end,
            })
        end)
    end
end

--- 扩散光环：一圈金色描边从中心放大淡出
function FX.ring(layer, opts)
    if not layer then return end
    opts = opts or {}
    local cx, cy = center(opts)
    local size = opts.size or 160
    local color = opts.color or fxColor("gold", { 242, 190, 96, 255 })
    local dur = opts.duration or fxNum("ring_duration", 0.6)
    local p = UI.Panel {
        position = "absolute",
        left = cx - size * 0.5, top = cy - size * 0.5,
        width = size, height = size,
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 6,
        borderColor = color,
        borderRadius = size * 0.5,
    }
    layer:AddChild(p)
    acquire(layer)
    pcall(function()
        p:Animate({
            keyframes = {
                [0] = { opacity = 0.95, scale = 0.25 },
                [1] = { opacity = 0, scale = 2.6 },
            },
            duration = dur,
            easing = "easeOut",
            onComplete = function() release(layer, p) end,
        })
    end)
end

--- 金币雨：从顶部随机位置落下并旋转
function FX.coinShower(layer, opts)
    if not layer then return end
    opts = opts or {}
    local w = UI.GetWidth() or Config.num("ui.design_width", 1080)
    local h = UI.GetHeight() or Config.num("ui.design_height", 1920)
    local count = opts.count or fxNum("coin_count", 16)
    local dur = opts.duration or fxNum("coin_duration", 1.1)
    local size = opts.size or fxNum("coin_size", 26)
    local color = opts.color or fxColor("coin", { 255, 198, 72, 255 })

    math.randomseed(os.time() % 100000)
    for i = 1, count do
        local x = (w * (i - 0.5) / count) + (math.random() - 0.5) * (w / count) * 0.6
        local delay = math.random() * 0.25
        local p = UI.Panel {
            position = "absolute",
            left = x - size * 0.5, top = -size,
            width = size, height = size,
            backgroundColor = color,
            borderRadius = size * 0.5,
            borderWidth = 3,
            borderColor = fxColor("gold_dark", { 150, 102, 32, 255 }),
        }
        layer:AddChild(p)
        acquire(layer)
        pcall(function()
            p:Animate({
                keyframes = {
                    [0]      = { opacity = 0, translateY = 0, rotate = 0 },
                    [0.12]   = { opacity = 1, translateY = h * 0.12, rotate = 90 },
                    [0.5]    = { opacity = 1, translateY = h * 0.55, rotate = 360 },
                    [0.88]   = { opacity = 1, translateY = h * 0.95, rotate = 630 },
                    [1]      = { opacity = 0, translateY = h + size * 2, rotate = 720 },
                },
                duration = dur + delay,
                easing = "linear",
                onComplete = function() release(layer, p) end,
            })
        end)
    end
end

--- 浮字：上浮 + 淡出（用于「成语达成 / 金币 +N」）
function FX.floatText(layer, opts)
    if not layer then return end
    opts = opts or {}
    local _, cy = center(opts)
    local text = opts.text or ""
    local color = opts.color or fxColor("star", { 255, 216, 120, 255 })
    local dur = opts.duration or 0.9
    local fontSize = opts.fontSize or Theme.font("caption", 24)
    local p = UI.Panel {
        position = "absolute",
        left = 0, top = cy,
        width = "100%",
        backgroundColor = { 0, 0, 0, 0 },
        alignItems = "center",
        children = { UI.Label {
            text = text,
            fontSize = fontSize,
            fontColor = color,
            fontWeight = "bold",
            textAlign = "center",
        } },
    }
    layer:AddChild(p)
    acquire(layer)
    pcall(function()
        p:Animate({
            keyframes = {
                [0]    = { opacity = 0, translateY = 20, scale = 0.7 },
                [0.25] = { opacity = 1, translateY = 0, scale = 1.1 },
                [1]    = { opacity = 0, translateY = -110, scale = 1.0 },
            },
            duration = dur,
            easing = "easeOut",
            onComplete = function() release(layer, p) end,
        })
    end)
end

--- 通关连击：星星 + 双光环 + 金币雨
function FX.levelClear(layer, opts)
    if not layer then return end
    opts = opts or {}
    local cx, cy = center(opts)
    FX.ring(layer, { x = cx, y = cy, size = 200 })
    FX.ring(layer, { x = cx, y = cy, size = 200, duration = fxNum("ring_duration", 0.6) * 1.5 })
    FX.starBurst(layer, { x = cx, y = cy })
    FX.starBurst(layer, { x = cx, y = cy, count = 10, radius = 150, rotate = 0.4, duration = 1.0 })
    FX.coinShower(layer)
end

return FX
