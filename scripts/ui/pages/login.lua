-- 登录 / 实名页（T23 合规入口）。
-- 规则：未实名禁入；未成年人受时段与时长限制，不允许进入时给出明确提示。
-- ⚠️ 边界：本页是**占位认证**（自报年龄段），不构成法律意义上的实名认证。
--   正式上线必须接入实名 SDK（姓名+身份证号 → 公安核验），并在回调里调用
--   Game.setRealname(真实年龄)。交付文档中列为待用户接入项。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local W = require("ui.widgets")

local Login = {}

local function c(key, default)
    return W.c(key, default)
end

--- 主按钮（描金大按钮，触控区足够大）
local function bigButton(text, sub, onTap, opts)
    opts = opts or {}
    local kids = {
        UI.Label {
            text = text,
            fontSize = Theme.font("toolbar", 28) * 1.1,
            fontColor = opts.fg or c("ink"),
            fontWeight = "bold",
            textAlign = "center",
            width = "100%",
        },
    }
    if sub then
        kids[#kids + 1] = UI.Label {
            text = sub,
            fontSize = Theme.font("caption", 24),
            fontColor = opts.subColor or c("ink_dim"),
            textAlign = "center",
            width = "100%",
            marginTop = 6,
        }
    end
    -- Button 默认 height=44（胶囊），两行文案必须显式给高度，否则触发 Layout Warning
    return UI.Button {
        width = "88%",
        height = opts.height or (sub and 104 or 78),
        marginVertical = 10,
        paddingVertical = 20,
        borderRadius = 30,
        backgroundGradient = opts.gradient or {
            direction = "to-bottom", from = c("gold"), to = c("gold_deep"),
        },
        borderWidth = 2,
        borderColor = opts.border or c("gold_dark"),
        boxShadow = W.shadow(16, 6, 130, opts.glow or "gold_dark"),
        flexDirection = "column",
        alignItems = "center",
        onClick = onTap,
        children = kids,
    }
end

--- 未实名：年龄选择
local function buildAgeGate()
    local info = Game.compliance()
    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        paddingHorizontal = 30,
        children = {
            UI.Label {
                text = "成语小秀才",
                fontSize = Theme.font("title", 56) * 1.3,
                fontColor = c("gold"),
                fontWeight = "bold",
                textAlign = "center",
            },
            UI.Label {
                text = info.agePrompt,
                fontSize = Theme.font("caption", 24),
                fontColor = c("text_light_dim"),
                textAlign = "center",
                marginTop = 12,
            },
            UI.Panel {
                width = "100%",
                marginTop = 40,
                children = {
                    bigButton("我已成年（18 岁及以上）", "可正常游玩与付费", function()
                        Game.setRealname(Config.num("compliance.default_adult_age", 25))
                        Login.afterVerify()
                    end),
                    bigButton("我未满 18 岁", "受防沉迷时段与时长限制", function()
                        Game.setRealname(Config.num("compliance.default_minor_age", 12))
                        Login.afterVerify()
                    end, {
                        gradient = {
                            direction = "to-bottom", from = c("panel_edge"), to = c("ink_dim"),
                        },
                        fg = c("cream"),
                        subColor = c("text_light_dim"),
                        glow = nil,
                    }),
                },
            },
            UI.Label {
                text = "按国家规定，未完成实名认证无法进入游戏。\n"
                    .. "本版为占位认证，正式上线需接入实名 SDK。",
                fontSize = Theme.font("caption", 24),
                fontColor = c("text_light_dim"),
                textAlign = "center",
                marginTop = 30,
            },
        },
    }
end

--- 已实名但当前不可进入（未成年时段/时长）
local function buildBlocked(info)
    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        paddingHorizontal = 40,
        children = {
            UI.Label {
                text = "暂时无法进入",
                fontSize = Theme.font("title", 56),
                fontColor = c("text_light"),
                fontWeight = "bold",
                textAlign = "center",
            },
            UI.Label {
                text = info.reasonText,
                fontSize = Theme.font("toolbar", 28),
                fontColor = c("gold"),
                textAlign = "center",
                marginTop = 20,
            },
            UI.Label {
                text = info.notice,
                fontSize = Theme.font("caption", 24),
                fontColor = c("text_light_dim"),
                textAlign = "center",
                marginTop = 30,
            },
            bigButton("返回", nil, function() Login.mount() end, {
                gradient = {
                    direction = "to-bottom", from = c("panel_edge"), to = c("ink_dim"),
                },
                fg = c("cream"),
                glow = nil,
            }),
        },
    }
end

--- 认证完成后的路由
function Login.afterVerify()
    local info = Game.compliance()
    if info.canPlay then
        local ok, Play = pcall(require, "ui.pages.play")
        if ok and Play and Play.mount then
            Play.mount()
            return
        end
    end
    Login.mount()
end

function Login.mount()
    local info = Game.compliance()
    local body
    if not info.verified and info.required then
        body = buildAgeGate()
    elseif not info.canPlay then
        body = buildBlocked(info)
    else
        Login.afterVerify()
        return nil
    end

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = c("bg_top"),
        backgroundImage = "Textures/bg_main.png",
        backgroundFit = "cover",
        justifyContent = "space-between",
        children = {
            body,
            UI.Label {
                text = info.notice,
                fontSize = Theme.font("caption", 24),
                fontColor = c("text_light_dim"),
                textAlign = "center",
                width = "100%",
                paddingBottom = 40,
            },
        },
    }
    UI.SetRoot(root, true)
    return root
end

return Login
