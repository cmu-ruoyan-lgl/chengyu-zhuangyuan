-- 主页（主菜单）：标题 + 继续闯关 + 府邸/挑战/图鉴/商店 四宫格。
-- 严格分层：只读 Game 状态并发指令；页面跳转一律走 ui.nav。
-- 所有配色/字号读 config（清新自然风），禁止硬编码。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local W = require("ui.widgets")
local Nav = require("ui.nav")
local Ticker = require("ui.ticker")

local Home = {}

--- 结果类提示统一走弹窗（S8）；弹窗组件懒加载避免循环依赖
local function alert(title, message)
    local ok, Modal = pcall(require, "ui.modal")
    if ok and Modal and Modal.alert then
        Modal.alert({ title = title, message = message })
    else
        print("[home] " .. tostring(title) .. ": " .. tostring(message))
    end
end

local c = W.c
local shadow = W.shadow

------------------------------------------------------------------------------
-- 书童动画（S9）：坐姿看书 + 呼吸浮动 + 定时翻页 + 「知识++」飘字
-- 引擎 Animate 无循环参数（实测），用 onComplete 链式衔接实现无限循环；
-- 翻页节奏由 ui/ticker 统一调度（全项目只许 ticker 订阅一次 Update）。
------------------------------------------------------------------------------

local scholarRefs_ = nil      -- { box, body, page, kudos }
local scholarHooked_ = false  -- ticker 只挂一次
local scholarGen_ = 0         -- 每次挂载 +1，旧链式动画到代际即停
local scholarFlipIn_ = 0      -- 距下次翻页的秒数

local function scholarTick(dt)
    local r = scholarRefs_
    if not r or not r.body or r.gen ~= scholarGen_ then return end
    scholarFlipIn_ = scholarFlipIn_ - (tonumber(dt) or 0)
    if scholarFlipIn_ > 0 then return end
    scholarFlipIn_ = Config.num("ui.scholar.flip_interval", 5)

    -- ① 翻页：白色书页从书页右侧向左掠过（引擎不支持 scaleX 插值，
    --    用 translateX + rotate 的「掀页」动效代替，见 RISK 9.0-S1）
    W.anim(r.page, {
        keyframes = {
            [0]   = { opacity = 0, translateX = 16, rotate = -12 },
            [0.3] = { opacity = 1, translateX = 4, rotate = -3 },
            [0.7] = { opacity = 0.95, translateX = -12, rotate = 6 },
            [1]   = { opacity = 0, translateX = -22, rotate = 14 },
        },
        duration = 0.55,
        easing = "easeInOut",
    })
    -- ② 知识++：头顶右上冒出、上飘淡出
    W.anim(r.kudos, {
        keyframes = {
            [0]    = { opacity = 0, translateY = 10, scale = 0.6 },
            [0.25] = { opacity = 1, translateY = 0, scale = 1.15 },
            [0.75] = { opacity = 1, translateY = -30, scale = 1 },
            [1]    = { opacity = 0, translateY = -52, scale = 1 },
        },
        duration = 1.1,
        easing = "easeOut",
    })
end

--- 呼吸浮动：单个 loop + alternate 关键帧动画（引擎原生支持无限循环）。
-- 不要用 onComplete 链式衔接：BaseUpdate 在动画完成分支会执行
-- self.animation_ = nil，把 onComplete 里刚创建的下一个动画立刻清掉
-- （实测链只走两拍就停，见 RISK 9.0-S1）。
local function startScholarBob(body)
    local amp = Config.num("ui.scholar.bob_amplitude", 6)
    local period = Config.num("ui.scholar.bob_period", 3.2)
    W.anim(body, {
        keyframes = {
            [0] = { translateY = 0 },
            [1] = { translateY = -amp },
        },
        duration = period,
        easing = "easeInOut",
        loop = true,
        direction = "alternate",
    })
end

--- 四宫格与底栏之间的书童区（用户指定位置）
-- page/kudos 必须挂在 body（=图片 300×300 同框）上：百分比才与图集部位
-- 一一对应（书页 ≈ 46%~74% 横、48%~68% 纵；头顶右上 ≈ 62% 横、-2% 纵）。
-- 挂在全宽 box 上百分比会随屏宽漂移。
local function buildScholar()
    local size = Config.num("ui.scholar.size", 300)
    scholarGen_ = scholarGen_ + 1
    scholarFlipIn_ = Config.num("ui.scholar.flip_interval", 5)

    -- 翻页高光：盖在书的位置，白色小卡沿页面掠过
    -- 注意用 opacity=0 而不是 visible=false——display:none 会让 opacity 动画完全不可见
    local page = UI.Panel {
        position = "absolute",
        left = "46%", top = "48%",
        width = "28%", height = "20%",
        borderRadius = 8,
        backgroundColor = { 255, 253, 245, 235 },
        borderWidth = 2,
        borderColor = { 214, 190, 152, 200 },
        opacity = 0,
    }
    -- 知识++：头部右上角（起始就在 head 右上，动画只负责浮起淡出）
    local kudos = UI.Panel {
        position = "absolute",
        left = "62%", top = "-2%",
        opacity = 0,
        children = { UI.Label {
            text = "知识++",
            fontSize = Theme.font("toolbar", 28),
            fontColor = c("jade_deep"),
            fontWeight = "bold",
            textAlign = "center",
            flexShrink = 1,
        } },
    }
    -- body 承载贴图与全部动效（呼吸浮动时书页/飘字一起跟随）
    local body = UI.Panel {
        width = size,
        height = size,
        backgroundImage = "Textures/scholar.png",
        backgroundFit = "contain",
        children = { page, kudos },
    }
    scholarRefs_ = { gen = scholarGen_, body = body, page = page, kudos = kudos }

    local box = UI.Panel {
        width = "100%",
        height = size + 40,
        justifyContent = "center",
        alignItems = "center",
        children = { body },
    }

    if not scholarHooked_ then
        scholarHooked_ = true
        Ticker.add(scholarTick)
    end
    startScholarBob(body)
    return box
end

--- 四宫格入口卡（白卡 + 主标题 + 状态行；副标题两行手动断行防横向裁断）
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
                text = W.wrapLines(sub or "", 9),
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
                    string.format("官职 · %s · 已过关 %d", tostring(rank.name), rank.levelsPassed or 0),
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
                            if (ch.remaining or 0) <= 0 then
                                alert("挑战次数已用完", "今日挑战次数已用完，明天再来吧")
                                return
                            end
                            local s, err = Game.startChallenge()
                            if s then
                                Nav.reset("play", { session = s })
                            else
                                print("[home] 挑战开启失败: " .. tostring(err))
                                alert("挑战开启失败", "请稍后再试（" .. tostring(err) .. "）")
                            end
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
            children = { header, middle, grid, buildScholar() },
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
