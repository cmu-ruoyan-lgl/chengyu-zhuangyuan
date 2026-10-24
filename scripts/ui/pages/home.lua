-- 主页（主菜单）：标题 + 继续闯关 + 府邸/挑战/图鉴/商店 四宫格。
-- 严格分层：只读 Game 状态并发指令；页面跳转一律走 ui.nav。
-- 所有配色/字号读 config（清新自然风），禁止硬编码。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local W = require("ui.widgets")
local Nav = require("ui.nav")

local Home = {}

local c = W.c
local shadow = W.shadow

--- 四宫格入口卡（白卡 + 主标题 + 状态行）
local function entryCard(title, sub, onTap, opts)
    opts = opts or {}
    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        margin = 10,
        borderRadius = 26,
        backgroundColor = c("panel"),
        borderWidth = 3,
        borderColor = opts.border or c("panel_edge"),
        boxShadow = shadow(18, 7, 110),
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        paddingVertical = 26,
        paddingHorizontal = 12,
        onClick = onTap,
        children = {
            UI.Label {
                text = title,
                fontSize = Theme.font("toolbar", 28) * 1.15,
                fontColor = opts.titleColor or c("ink"),
                fontWeight = "bold",
                textAlign = "center",
                width = "100%",
                flexShrink = 1,
            },
            UI.Label {
                text = sub or "",
                fontSize = Theme.font("caption", 24),
                fontColor = opts.subColor or c("ink_dim"),
                textAlign = "center",
                width = "100%",
                marginTop = 10,
                flexShrink = 1,
            },
        },
    }
end

function Home.mount()
    local rank = Game.rank()
    local info = Game.compliance()
    local ch = Game.challengeInfo()
    local levelId = Game.currentLevelId()
    local inProgress = Game.hasInProgress()
    local maxLevel = Game.maxLevel()

    -- 顶部：标题 + 官职胶囊
    local header = UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 84,
        children = {
            UI.Label {
                text = "成语小秀才",
                fontSize = Theme.font("title", 56) * 1.35,
                fontColor = c("jade_deep"),
                fontWeight = "bold",
                textAlign = "center",
            },
            UI.Label {
                text = "益智填词 · 出口成章",
                fontSize = Theme.font("caption", 24),
                fontColor = c("ink_dim"),
                textAlign = "center",
                marginTop = 14,
            },
            UI.Panel {
                marginTop = 22,
                children = { W.chip(
                    string.format("官职 · %s　已过关 %d", tostring(rank.name), rank.levelsPassed or 0),
                    { bold = true }) },
            },
        },
    }

    -- 中部：闯关大按钮（Panel 实现——Button 的单行 auto-fit 管线会让两行 children 溢出）
    local playLabel = inProgress and "继续闯关" or "开始闯关"
    local playSub = inProgress
        and string.format("回到第 %d 关（进度已保留）", levelId)
        or (levelId > 1 and string.format("第 %d 关 / 共 %d 关", levelId, maxLevel)
            or string.format("共 %d 关等你挑战", maxLevel))
    local playBtn = UI.Panel {
        width = "80%",
        paddingVertical = 26,
        borderRadius = 40,
        backgroundGradient = { direction = "to-bottom", from = c("jade"), to = c("jade_deep") },
        borderWidth = 3,
        borderColor = c("jade_deep"),
        boxShadow = shadow(22, 9, 150, "jade_deep"),
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        onClick = function() Nav.reset("play") end,
        children = {
            UI.Label {
                text = playLabel,
                fontSize = Theme.font("title", 56) * 0.82,
                fontColor = c("cream"),
                fontWeight = "bold",
                textAlign = "center",
                width = "100%",
                flexShrink = 1,
            },
            UI.Label {
                text = playSub,
                fontSize = Theme.font("caption", 24),
                fontColor = c("cream_dim"),
                textAlign = "center",
                width = "100%",
                marginTop = 8,
                flexShrink = 1,
            },
        },
    }
    local middle = UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 64,
        children = { playBtn },
    }

    -- 四宫格：府邸 / 挑战 / 图鉴 / 商店
    local pendingMark = Game.hasPendingDaily() and "（有奖励可领）" or ""
    local grid = UI.Panel {
        width = "100%",
        flexDirection = "column",
        paddingHorizontal = 22,
        marginTop = 56,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    entryCard("府邸", "官职门客 · 签到任务" .. pendingMark,
                        function() Nav.go("court") end),
                    entryCard("每日挑战",
                        string.format("限时 %d 词 · 今日剩 %d 次",
                            ch.target or 0, ch.remaining or 0),
                        function()
                            if (ch.remaining or 0) <= 0 then return end
                            local s = Game.startChallenge()
                            if s then Nav.reset("play", { session = s }) end
                        end,
                        { titleColor = c("seal_deep") }),
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    entryCard("成语图鉴",
                        string.format("已收录 %d 条 · 错题本", Game.bookCount()),
                        function() Nav.go("book") end),
                    entryCard("商店", "金币 · 道具 · 免广告",
                        function() Nav.go("shop") end),
                },
            },
        },
    }

    -- 底部：体力 / 金币 + 健康忠告
    local footer = UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingBottom = 40,
        children = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "center",
                children = {
                    W.chip(string.format("体力 %d/%d", Game.stamina(),
                        Config.num("stamina.max", 50)), { dotColor = c("jade") }),
                    UI.Panel { width = 16 },
                    W.chip("金币 " .. tostring(Game.gold()),
                        { dotColor = c("coin"), fg = c("gold_dark") }),
                },
            },
            UI.Label {
                text = info.notice,
                fontSize = Theme.font("caption", 24) * 0.85,
                fontColor = c("ink_dim"),
                textAlign = "center",
                width = "100%",
                marginTop = 24,
                flexShrink = 1,
            },
        },
    }

    -- 主体放 ScrollView：矮屏/横屏（如 headless 巡检窗口 1322×546）不溢出、可滚动
    local body = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = false,
        children = { UI.Panel {
            width = "100%",
            flexDirection = "column",
            flexShrink = 1,
            children = { header, middle, grid },
        } },
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = c("bg_top"),
        backgroundImage = "Textures/bg_main.png",
        backgroundFit = "cover",
        justifyContent = "space-between",
        children = { body, footer },
    }
    UI.SetRoot(root, true)
    return root
end

return Home
