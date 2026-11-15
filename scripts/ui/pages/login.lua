-- 登录 / 实名页（T23 合规入口）。
-- 规则：未实名禁入；未成年人受时段与时长限制，不允许进入时给出明确提示。
-- ⚠️ 边界：本页是**占位认证**（自报年龄段），不构成法律意义上的实名认证。
--   正式上线必须接入实名 SDK（姓名+身份证号 → 公安核验），并在回调里调用
--   Game.setRealname(真实年龄)。交付文档中列为待用户接入项。
-- 布局纪律（S6 踩坑）：
--   ① 多行复合按钮一律用 UI.Panel + onClick——UI.Button 内部为单行 text
--      做了 auto-fit 管线，children 两行时副标题会溢出按钮外（实测截图重合）；
--   ② 列容器里的定宽子项要显式 alignItems="center"，否则靠左；
--   ③ Label 不自动换行，长文案必须手动断行（见 wrapLines）。
-- S27 真机重排：字号走 Theme.font（按视口自适应），标题字号再由 titleFontSize 按可用宽封顶，
--   保证「成语小状元」单行；主按钮标题缩短、信息下沉到副标题；顶部留足平台胶囊安全区。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local W = require("ui.widgets")

local Login = {}

local function c(key, default)
    return W.c(key, default)
end

local wrapLines = W.wrapLines

--- 多行大按钮（Panel 实现，两行文案不溢出；触控区 = 整张卡）
local function bigButton(text, sub, onTap, opts)
    opts = opts or {}
    local fit = Theme.fit
    local kids = {
        UI.Label {
            text = text,
            fontSize = Theme.font("toolbar", 28) * 0.95,
            fontColor = opts.fg or c("ink"),
            fontWeight = "bold",
            textAlign = "center",
            width = "100%",
            flexShrink = 1,
        },
    }
    if sub then
        kids[#kids + 1] = UI.Label {
            text = sub,
            fontSize = Theme.font("caption", 24) * 0.82,
            fontColor = opts.subColor or c("ink_dim"),
            textAlign = "center",
            width = "100%",
            marginTop = fit(8),
            flexShrink = 1,
        }
    end
    return UI.Panel {
        width = "86%",
        marginVertical = fit(9),
        paddingVertical = fit(18),
        paddingHorizontal = fit(16),
        borderRadius = fit(28),
        backgroundColor = opts.bg,
        backgroundGradient = opts.gradient or {
            direction = "to-bottom", from = c("gold"), to = c("gold_deep"),
        },
        borderWidth = 2,
        borderColor = opts.border or c("gold_dark"),
        boxShadow = W.shadow(fit(16), fit(6), 130, opts.glow or "gold_dark"),
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        onClick = onTap,
        children = kids,
    }
end

--- 未实名：年龄选择
local function buildAgeGate()
    local info = Game.compliance()
    local fit = Theme.fit
    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        paddingHorizontal = 30,
        paddingTop = Theme.safeTop(),
        children = {
            -- 单行标题：字号按可用宽封顶（5 字 + 字距余量），杜绝「元」字折到第二行
            UI.Label {
                text = "成语小状元",
                fontSize = Theme.titleFontSize(5, 30, 1.15),
                fontColor = c("jade_deep"),
                fontWeight = "bold",
                textAlign = "center",
                width = "100%",
                flexShrink = 0,
            },
            UI.Label {
                text = wrapLines(info.agePrompt, 15),
                fontSize = Theme.font("caption", 24) * 0.88,
                fontColor = c("ink_dim"),
                textAlign = "center",
                width = "100%",
                marginTop = fit(20),
                flexShrink = 1,
            },
            UI.Panel {
                width = "100%",
                marginTop = fit(44),
                flexDirection = "column",
                alignItems = "center",
                children = {
                    bigButton("我已成年", "18 岁及以上，可正常游玩与付费", function()
                        Game.setRealname(Config.num("compliance.default_adult_age", 25))
                        Login.afterVerify()
                    end, {
                        gradient = {
                            direction = "to-bottom", from = c("jade"), to = c("jade_deep"),
                        },
                        fg = c("cream"),
                        subColor = c("cream_dim"),
                        border = c("jade_deep"),
                        glow = "jade_deep",
                    }),
                    bigButton("我未满 18 岁", "受防沉迷时段与时长限制", function()
                        Game.setRealname(Config.num("compliance.default_minor_age", 12))
                        Login.afterVerify()
                    end, {
                        gradient = {
                            direction = "to-bottom", from = c("panel"), to = c("panel_edge"),
                        },
                        fg = c("ink"),
                        subColor = c("ink_dim"),
                        border = c("panel_edge"),
                        glow = nil,
                    }),
                },
            },
            UI.Label {
                text = wrapLines(
                    "按国家规定，未完成实名认证无法进入游戏。\n本版为占位认证，正式上线需接入实名 SDK。",
                    18),
                fontSize = Theme.font("caption", 24) * 0.8,
                fontColor = c("ink_dim"),
                textAlign = "center",
                width = "100%",
                marginTop = fit(34),
                flexShrink = 1,
            },
        },
    }
end

--- 已实名但当前不可进入（未成年时段/时长）
local function buildBlocked(info)
    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        paddingHorizontal = 40,
        paddingTop = Theme.safeTop(),
        children = {
            UI.Label {
                text = "暂时无法进入",
                fontSize = Theme.font("title", 56) * 0.9,
                fontColor = c("ink"),
                fontWeight = "bold",
                textAlign = "center",
            },
            UI.Label {
                text = info.reasonText,
                fontSize = Theme.font("toolbar", 28),
                fontColor = c("seal_deep"),
                textAlign = "center",
                marginTop = Theme.fit(20),
                flexShrink = 1,
            },
            UI.Label {
                text = wrapLines(info.notice, 18),
                fontSize = Theme.font("caption", 24) * 0.85,
                fontColor = c("ink_dim"),
                textAlign = "center",
                marginTop = Theme.fit(30),
                flexShrink = 1,
            },
            UI.Panel { height = Theme.fit(26) },
            -- 占位认证期允许重选年龄段（接入真实实名 SDK 后删除该入口）
            bigButton("重新选择年龄段", "返回实名认证页", function()
                Game.resetRealname()
                Login.mount()
            end, {
                gradient = {
                    direction = "to-bottom", from = c("jade"), to = c("jade_deep"),
                },
                fg = c("cream"),
                subColor = c("cream_dim"),
                border = c("jade_deep"),
                glow = "jade_deep",
            }),
        },
    }
end

--- 认证完成后的路由：可游玩 → 主页（主菜单）
function Login.afterVerify()
    local info = Game.compliance()
    if info.canPlay then
        local ok, Nav = pcall(require, "ui.nav")
        if ok and Nav and Nav.reset then
            Nav.reset("home")
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

    -- 隐私政策（PRD §5.1）：URL 未配置时不渲染，避免展示占位/假链接
    local footer = {
        UI.Label {
            text = wrapLines(info.notice, 20),
            fontSize = Theme.font("caption", 24) * 0.78,
            fontColor = c("ink_dim"),
            textAlign = "center",
            width = "100%",
            paddingBottom = Theme.fit(36),
            flexShrink = 1,
        },
    }
    if type(info.privacyUrl) == "string" and info.privacyUrl ~= "" then
        footer[#footer + 1] = UI.Label {
            text = "隐私政策：" .. info.privacyUrl,
            fontSize = Theme.font("caption", 24) * 0.72,
            fontColor = c("ink_dim"),
            textAlign = "center",
            width = "100%",
            paddingBottom = Theme.fit(24),
            flexShrink = 1,
        }
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
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                alignItems = "center",
                flexShrink = 0,
                children = footer,
            },
        },
    }
    UI.SetRoot(root, true)
    return root
end

return Login
