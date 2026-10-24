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
-- 书童骨骼动画（S9-rig）
-- 骨架层级：root(呼吸浮动) → 躯干骨(绕腰微转) → {头骨(点头) / 书骨(含书页) / 近臂骨(翻页)}，
--           另有静止的凳子与远臂。每根骨 = 与画框同尺寸的透明 Panel，
--           transformOrigin = 关节在画框中的比例坐标 → 旋转即绕关节转，子节点继承变换。
-- 部件与关节坐标由 tools/fit_doll_rig.py 以合成图剪影为真值拟合（覆盖 88.8%），
-- 全部写进 config.json 的 ui.scholar，禁止硬编码。
-- 循环动画一律 loop + direction="alternate"：onComplete 链式会被 BaseUpdate
-- 完成分支的 self.animation_ = nil 杀掉（实测只走两拍，见 RISK 9.0）。
------------------------------------------------------------------------------

local scholarRefs_ = nil      -- { gen, page, armBone, kudos }
local scholarHooked_ = false  -- ticker 只挂一次
local scholarGen_ = 0         -- 每次挂载 +1，旧代际的 tick 到代即停
local scholarFlipIn_ = 0      -- 距下次翻页的秒数

local pct = W.pct

--- 一根骨：与画框同尺寸、绕关节旋转的透明容器（子节点继承其变换）
-- 必须绝对定位：否则多根 100% 高度的骨会在列容器里纵向叠加（实测 320→960 溢出）
local function bone(jointName, children)
    local j = Config.get("ui.scholar.joints." .. jointName, nil)
    return UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%",
        height = "100%",
        transformOrigin = { (j and j[1]) or 0.5, (j and j[2]) or 0.5 },
        pointerEvents = "none",
        children = children,
    }
end

--- 部件贴图：位置/尺寸全部来自 config（相对画框的比例）
local function partPanel(name, img)
    local p = Config.get("ui.scholar.parts." .. name, nil)
    local tex = img or (p and p.img) or nil
    if not tex then return nil end
    local x, y, w, h = 0, 0, 1, 1
    if p then x, y, w, h = p.x or 0, p.y or 0, p.w or 1, p.h or 1 end
    return UI.Panel {
        position = "absolute",
        left = pct(x), top = pct(y),
        width = pct(w), height = pct(h),
        backgroundImage = tex,
        backgroundFit = "contain",
        pointerEvents = "none",
    }
end

--- 常驻循环动画（引擎原生 loop + alternate；不要改用 onComplete 链）
local function loopAnim(widget, prop, to, period, easing)
    W.anim(widget, {
        keyframes = { [0] = { [prop] = 0 }, [1] = { [prop] = to } },
        duration = period,
        easing = easing or "easeInOut",
        loop = true,
        direction = "alternate",
    })
end

local function scholarTick(dt)
    local r = scholarRefs_
    if not r or r.gen ~= scholarGen_ then return end
    scholarFlipIn_ = scholarFlipIn_ - (tonumber(dt) or 0)
    if scholarFlipIn_ > 0 then return end
    scholarFlipIn_ = Config.num("ui.scholar.flip_interval", 5)

    local swing = Config.num("ui.scholar.arm_swing", 7)
    -- ① 书页绕书脊由右向左翻（transformOrigin="left" 已在面板上设好）
    W.anim(r.page, {
        keyframes = {
            [0]    = { opacity = 0, rotate = 0 },
            [0.18] = { opacity = 1, rotate = -12 },
            [0.72] = { opacity = 1, rotate = -150 },
            [1]    = { opacity = 0, rotate = -172 },
        },
        duration = 0.75,
        easing = "easeInOut",
    })
    -- ② 近侧手臂：先伸向书页再收回（骨骼绕肩关节旋转）
    W.anim(r.armBone, {
        keyframes = {
            [0]    = { rotate = 0 },
            [0.35] = { rotate = -swing },
            [0.8]  = { rotate = swing * 0.3 },
            [1]    = { rotate = 0 },
        },
        duration = 0.9,
        easing = "easeInOut",
    })
    -- ③ 知识++：头顶右上冒出、上飘淡出
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

--- 书页：画在书的右半页上，绕书脊旋转（opacity=0 起始，禁用 visible=false）
local function buildPage()
    local pg = Config.get("ui.scholar.page", nil) or {}
    return UI.Panel {
        position = "absolute",
        left = pct(pg.x or 0.647), top = pct(pg.y or 0.565),
        width = pct(pg.w or 0.156), height = pct(pg.h or 0.215),
        borderRadius = 6,
        backgroundColor = { 255, 253, 245, 240 },
        borderWidth = 2,
        borderColor = { 214, 190, 152, 210 },
        transformOrigin = "left",
        opacity = 0,
        pointerEvents = "none",
    }
end

--- 知识++ 飘字：头顶右上角
local function buildKudos()
    local kd = Config.get("ui.scholar.kudos", nil) or {}
    return UI.Panel {
        position = "absolute",
        left = pct(kd.x or 0.60), top = pct(kd.y or 0.03),
        opacity = 0,
        pointerEvents = "none",
        children = { UI.Label {
            text = "知识++",
            fontSize = Theme.font("toolbar", 28),
            fontColor = c("jade_deep"),
            fontWeight = "bold",
            textAlign = "center",
            flexShrink = 1,
        } },
    }
end

--- 骨骼装配（默认）
local function buildScholarRig()
    local size = Config.num("ui.scholar.size", 320)
    scholarGen_ = scholarGen_ + 1
    scholarFlipIn_ = Config.num("ui.scholar.flip_interval", 5)

    local page = buildPage()
    local kudos = buildKudos()

    local headBone = bone("head", { partPanel("head") })
    local armNearBone = bone("arm_near", { partPanel("arm_near") })
    local bookBone = bone("book", { partPanel("book"), page })
    local torsoBone = bone("torso", { partPanel("torso"), headBone, bookBone, armNearBone })

    -- 会呼吸浮动的部分（凳子不跟着飘）
    local rig = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "none",
        children = { partPanel("arm_far"), torsoBone, kudos },
    }
    local box = UI.Panel {
        width = size,
        height = size,
        position = "relative",
        pointerEvents = "none",
        children = { partPanel("chair"), rig },
    }

    scholarRefs_ = { gen = scholarGen_, page = page, armBone = armNearBone, kudos = kudos }
    if not scholarHooked_ then
        scholarHooked_ = true
        Ticker.add(scholarTick)
    end

    local period = Config.num("ui.scholar.bob_period", 3.2)
    loopAnim(rig, "translateY", -Config.num("ui.scholar.bob_amplitude", 6), period)
    loopAnim(torsoBone, "rotate", Config.num("ui.scholar.breathe_degrees", 1.2), period)
    loopAnim(headBone, "rotate", Config.num("ui.scholar.nod_degrees", 2.6),
        Config.num("ui.scholar.nod_period", 2.6))
    -- 外层给个满宽容器把定宽画框居中（父级是列容器，定宽子项不会自动居中）
    return UI.Panel {
        width = "100%",
        height = size + 20,
        alignItems = "center",
        justifyContent = "center",
        pointerEvents = "none",
        children = { box },
    }
end

--- 整图兜底（config: ui.scholar.mode = "image"）：单张贴图 + 书页 + 飘字
local function buildScholarImage()
    local size = Config.num("ui.scholar.size", 320)
    scholarGen_ = scholarGen_ + 1
    scholarFlipIn_ = Config.num("ui.scholar.flip_interval", 5)

    local page = buildPage()
    local kudos = buildKudos()
    local body = UI.Panel {
        width = size,
        height = size,
        backgroundImage = "Textures/scholar.png",
        backgroundFit = "contain",
        pointerEvents = "none",
        children = { page, kudos },
    }
    scholarRefs_ = { gen = scholarGen_, page = page, armBone = nil, kudos = kudos }
    if not scholarHooked_ then
        scholarHooked_ = true
        Ticker.add(scholarTick)
    end
    loopAnim(body, "translateY", -Config.num("ui.scholar.bob_amplitude", 6),
        Config.num("ui.scholar.bob_period", 3.2))
    return body
end

--- 四宫格与底栏之间的书童区（用户指定位置）
local function buildScholar()
    if Config.get("ui.scholar.mode", "rig") == "image" then
        return buildScholarImage()
    end
    return buildScholarRig()
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
