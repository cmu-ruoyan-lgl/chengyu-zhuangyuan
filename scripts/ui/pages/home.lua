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
-- 书童动画（S12：回归 AI 整图 scholar.png；骨骼方案 S10/S11 已被用户否决）
-- 整图模式（默认）：scholar.png + 呼吸起伏/坐姿轻摇 + 翻页页片 + 知识++。
-- 翻页页片是盖在书上（右页区域）的白色贴片，绕书脊（页片左下角）翻动。
-- 循环一律 loop + alternate（onComplete 链会被 BaseUpdate 完成分支的
-- self.animation_ = nil 杀掉，见 RISK 9.0）。同一 widget 只有一个动画槽，
-- 所以「起伏」与「轻摇」必须分挂两层。
-- （buildScholarRig 骨骼分支保留但默认不走：S10 AI 图拟合姿态诡异、
--   S11 程序化绘制风格太丑，分别见 RISK 10.0 / 11.0；部件资源已移除。）
------------------------------------------------------------------------------

local scholarRefs_ = nil       -- { gen, page, foreBone, kudos, eyesOpen, eyesShut }
local scholarHooked_ = false   -- ticker 只挂一次
local scholarGen_ = 0          -- 每次挂载 +1，旧代际的 tick 到代即停
local scholarFlipIn_ = 0       -- 距下次翻页的秒数
local scholarBlinkIn_ = 3      -- 距下次眨眼的秒数
local scholarBlinkLeft_ = 0    -- 闭眼剩余时长

local pct = W.pct

local function cfgNum(key, default)
    return Config.num("ui.scholar." .. key, default)
end

--- 关节坐标（比例 0..1）：config 优先，缺失时用传入兜底
local function jointOf(name, fx, fy)
    local j = Config.get("ui.scholar.joints." .. name, nil)
    if type(j) == "table" and tonumber(j[1]) then
        return { tonumber(j[1]), tonumber(j[2]) }
    end
    return { fx, fy }
end

--- 一根骨：与画框同尺寸的透明容器，绕关节旋转，子节点继承其变换。
-- 必须绝对定位：否则多层 100% 高度的骨会在列容器里纵向叠加（实测 320→960 溢出）
local function bone(jointName, fx, fy, children)
    return UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        transformOrigin = jointOf(jointName, fx, fy),
        pointerEvents = "none",
        children = children,
    }
end

--- 部件贴图：整幅画布、已就位，故恒为 0,0,100%,100%
local function part(name)
    local img = Config.get("ui.scholar.parts." .. name, nil)
    if type(img) ~= "string" then
        img = "Textures/doll/scholar_" .. name .. ".png"
    end
    return UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        backgroundImage = img,
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

--- 知识++ 飘字：头顶右上角（opacity=0 起始，禁用 visible=false）
local function buildKudos()
    local kd = Config.get("ui.scholar.kudos", nil) or {}
    return UI.Panel {
        position = "absolute",
        left = pct(tonumber(kd.x) or 0.58),
        top = pct(tonumber(kd.y) or 0.06),
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

--- 知识++ 飘字动效（整图/序列帧共用；关键帧参数已冒烟验证，勿改）
local function playKudos(kudos)
    W.anim(kudos, {
        keyframes = {
            [0]    = { opacity = 0, translateY = 8, scale = 0.7 },
            [0.38] = { opacity = 0, translateY = 8, scale = 0.7 },
            [0.56] = { opacity = 1, translateY = 0, scale = 1.12 },
            [0.84] = { opacity = 1, translateY = -24, scale = 1 },
            [1]    = { opacity = 0, translateY = -42, scale = 1 },
        },
        duration = 1.35,
        easing = "easeOut",
    })
end

local function scholarTick(dt)
    local r = scholarRefs_
    if not r or r.gen ~= scholarGen_ then return end
    dt = tonumber(dt) or 0

    -- 眨眼：睁/闭两套眼睛贴图互斥切换（离散状态，不走关键帧）
    if r.eyesOpen and r.eyesShut then
        if scholarBlinkLeft_ > 0 then
            scholarBlinkLeft_ = scholarBlinkLeft_ - dt
            if scholarBlinkLeft_ <= 0 then
                r.eyesOpen.opacity = 1
                r.eyesShut.opacity = 0
                local lo = cfgNum("blink_min", 2.2)
                local hi = cfgNum("blink_max", 4.5)
                scholarBlinkIn_ = lo + math.random() * math.max(0, hi - lo)
            end
        else
            scholarBlinkIn_ = scholarBlinkIn_ - dt
            if scholarBlinkIn_ <= 0 then
                r.eyesOpen.opacity = 0
                r.eyesShut.opacity = 1
                scholarBlinkLeft_ = cfgNum("blink_hold", 0.12)
            end
        end
    end

    if not r.kudos then return end

    -- 翻页：（骨骼模式先抬手）→ 书页翻动 → 知识++（翻过一半时冒出）
    scholarFlipIn_ = scholarFlipIn_ - dt
    if scholarFlipIn_ > 0 then return end
    scholarFlipIn_ = cfgNum("flip_interval", 5)

    -- ① 骨骼模式：前臂绕肘抬起，等书页翻过去再落回（保持段略微回弹，避免僵直）
    if r.foreBone then
        local lift = cfgNum("arm_lift", 40)
        W.anim(r.foreBone, {
            keyframes = {
                [0]    = { rotate = 0 },
                [0.22] = { rotate = lift },
                [0.78] = { rotate = lift * 0.92 },
                [1]    = { rotate = 0 },
            },
            duration = 1.15,
            easing = "easeInOut",
        })
    end
    -- ② 书页翻动（opacity=0 起始/收尾，避免翻完残留一页）；
    --    整图模式页片是盖在书上的白色贴片，绕书脊（页片左下角）翻动
    if r.page then
        local flip, dur
        if r.foreBone then
            flip, dur = cfgNum("flip_degrees", -168), 1.0
            W.anim(r.page, {
                keyframes = {
                    [0]    = { opacity = 0, rotate = 0 },
                    [0.20] = { opacity = 1, rotate = -12 },
                    [0.80] = { opacity = 1, rotate = flip + 18 },
                    [1]    = { opacity = 0, rotate = flip },
                },
                duration = dur,
                easing = "easeInOut",
            })
        else
            flip, dur = cfgNum("image_page.rotate", -118), 0.85
            W.anim(r.page, {
                keyframes = {
                    [0]    = { opacity = 0, rotate = 0 },
                    [0.18] = { opacity = 0.95, rotate = -10 },
                    [0.72] = { opacity = 0.95, rotate = flip + 14 },
                    [1]    = { opacity = 0, rotate = flip },
                },
                duration = dur,
                easing = "easeInOut",
            })
        end
    end
    -- ③ 知识++：前段静止等待，书页翻过一半后冒出、上飘淡出
    playKudos(r.kudos)
end

--- 骨骼装配（默认）
local function buildScholarRig()
    local size = cfgNum("size", 320)
    scholarGen_ = scholarGen_ + 1
    scholarFlipIn_ = cfgNum("flip_interval", 5)
    scholarBlinkLeft_ = 0
    scholarBlinkIn_ = cfgNum("blink_min", 2.2)

    -- 头：两套眼睛互斥（闭眼初始隐藏）
    local eyesOpen = part("eyes_open")
    local eyesShut = part("eyes_shut")
    eyesShut.opacity = 0
    local headBone = bone("neck", 0.4648, 0.3711, { part("head"), eyesOpen, eyesShut })

    -- 书：书页是全画幅贴图，故骨绕「书脊」的比例坐标旋转
    local page = part("page")
    page.opacity = 0
    local pageBone = bone("spine", 0.4844, 0.543, { page })

    -- 近侧手臂：前臂绕肘抬起翻页
    local foreBone = bone("elbow", 0.6289, 0.5312, { part("arm_fore") })

    local kudos = buildKudos()

    -- 上半身：呼吸时整体绕髋微转，头/书/手臂作为子节点一起跟随
    local rootBone = bone("hip", 0.4531, 0.6484, {
        part("torso"),
        part("book"), pageBone,
        part("arm_upper"), foreBone,
        headBone,
    })
    -- 呼吸起伏单独一层：同一 widget 只有一个动画槽，rotate 已占用 rootBone
    local liftBone = UI.Panel {
        position = "absolute",
        left = 0, top = 0,
        width = "100%", height = "100%",
        pointerEvents = "none",
        children = { rootBone },
    }

    local box = UI.Panel {
        width = size, height = size,
        position = "relative",
        pointerEvents = "none",
        children = { part("chair"), part("arm_far"), part("legs"), liftBone, kudos },
    }

    scholarRefs_ = { gen = scholarGen_, page = page, foreBone = foreBone,
                     kudos = kudos, eyesOpen = eyesOpen, eyesShut = eyesShut }
    if not scholarHooked_ then
        scholarHooked_ = true
        Ticker.add(scholarTick)
    end

    local bp = cfgNum("breathe_period", 3.4)
    loopAnim(liftBone, "translateY", -cfgNum("breathe_lift", 4), bp)
    loopAnim(rootBone, "rotate", cfgNum("breathe_degrees", 1.1), bp)
    loopAnim(headBone, "rotate", cfgNum("nod_degrees", 2.4), cfgNum("nod_period", 2.8))

    -- 外层满宽容器把定宽画框居中（父级是列容器，定宽子项不会自动居中）
    return UI.Panel {
        width = "100%",
        height = size + 20,
        alignItems = "center",
        justifyContent = "center",
        pointerEvents = "none",
        children = { box },
    }
end

--- 整图模式（默认，config: ui.scholar.mode = "image"）：
-- scholar.png 单张贴图 + 呼吸起伏/坐姿轻摇 + 翻页页片 + 知识++
local function buildScholarImage()
    local size = cfgNum("size", 320)
    scholarGen_ = scholarGen_ + 1
    scholarFlipIn_ = cfgNum("flip_interval", 5)
    scholarBlinkLeft_ = 0

    -- 翻页页片：盖在摊开的书上，绕书脊（页片左下角）翻动；opacity=0 起始
    local pc = Config.get("ui.scholar.image_page", nil) or {}
    local origin = type(pc.origin) == "table" and pc.origin or { 0.08, 0.95 }
    local page = UI.Panel {
        position = "absolute",
        left = pct(tonumber(pc.x) or 0.66),
        top = pct(tonumber(pc.y) or 0.505),
        width = pct(tonumber(pc.w) or 0.155),
        height = pct(tonumber(pc.h) or 0.195),
        borderRadius = 6,
        backgroundColor = { 255, 252, 240, 235 },
        borderWidth = 1.5,
        borderColor = { 214, 190, 152, 200 },
        transformOrigin = { tonumber(origin[1]) or 0.08, tonumber(origin[2]) or 0.95 },
        opacity = 0,
        pointerEvents = "none",
    }
    local kudos = buildKudos()

    local body = UI.Panel {
        width = size, height = size,
        position = "relative",
        backgroundImage = "Textures/scholar.png",
        backgroundFit = "contain",
        pointerEvents = "none",
        children = { page, kudos },
    }
    -- 同一 widget 只有一个动画槽：起伏(translateY)与轻摇(rotate)分两层
    local swayBone = UI.Panel {
        width = size, height = size,
        position = "relative",
        transformOrigin = { 0.45, 0.95 },   -- 绕椅子底部轻摇
        pointerEvents = "none",
        children = { body },
    }
    local liftBone = UI.Panel {
        width = size, height = size,
        position = "relative",
        pointerEvents = "none",
        children = { swayBone },
    }

    scholarRefs_ = { gen = scholarGen_, page = page, foreBone = nil, kudos = kudos }
    if not scholarHooked_ then
        scholarHooked_ = true
        Ticker.add(scholarTick)
    end

    local bp = cfgNum("breathe_period", 3.4)
    loopAnim(liftBone, "translateY", -cfgNum("breathe_lift", 4), bp)
    loopAnim(swayBone, "rotate", cfgNum("sway_degrees", 0.8), bp * 1.3)

    -- 外层满宽容器把定宽画框居中（父级是列容器，定宽子项不会自动居中）
    return UI.Panel {
        width = "100%",
        height = size + 20,
        alignItems = "center",
        justifyContent = "center",
        pointerEvents = "none",
        children = { liftBone },
    }
end

--- 序列帧模式（config: ui.scholar.mode = "sprite"）：assets/sprites/scholar/ 图集
-- 无限循环播放，呼吸/点头/翻页已内嵌于动画帧。播放速度按
-- 「动画时长 / flip_interval」归一，翻页周期仍由 config 控制；
-- 知识++ 由翻页完成帧（onFrameChange）驱动，与画面天然同步。
-- 图集缺失时自动回退整图模式（包内资源探测只能走 cache:Exists，见 RISK S7-1）。
local function buildScholarSprite()
    local sp = Config.get("ui.scholar.sprite", nil) or {}
    local src = type(sp.src) == "string" and sp.src or "sprites/scholar/sprite.json"
    if not cache:Exists(src) then
        print("[home] 书童图集缺失，回退整图模式: " .. tostring(src))
        return buildScholarImage()
    end
    local size = tonumber(sp.width) or cfgNum("size", 320)
    local animName = sp.anim_read or "read"
    local kudosFrame = tonumber(sp.kudos_local_frame) or -1
    local gen = scholarGen_ + 1
    scholarGen_ = gen

    local kudos = buildKudos()
    local sprite = UI.Sprite {
        src = src,
        defaultAnimation = animName,
        width = size, height = size,
        objectFit = "contain",
        onFrameChange = function(_frame, localFrame)
            if localFrame == kudosFrame and gen == scholarGen_ then
                playKudos(kudos)
            end
        end,
    }
    -- 循环周期归一：speed = 动画数据时长 / flip_interval（时长以 ms 烘焙进图集）
    local dur = sprite:GetDuration(animName)
    if dur > 0 then
        sprite:SetSpeed(dur / math.max(0.5, cfgNum("flip_interval", 5)))
    end
    -- 序列帧模式不注册翻页/眨眼引用：scholarTick 对 kudos=nil 直接让位，
    -- 知识++ 完全由 onFrameChange 驱动（与帧画面同步，不另起计时器）
    scholarRefs_ = { gen = gen, sprite = sprite }

    -- 外层满宽容器把定宽画框居中（父级是列容器，定宽子项不会自动居中）
    return UI.Panel {
        width = "100%",
        height = size + 20,
        alignItems = "center",
        justifyContent = "center",
        pointerEvents = "none",
        children = { sprite },
    }
end

--- 四宫格与底栏之间的书童区（用户指定位置）
local function buildScholar()
    local mode = Config.get("ui.scholar.mode", "image")
    if mode == "sprite" then
        return buildScholarSprite()
    end
    if mode == "image" then
        return buildScholarImage()
    end
    return buildScholarRig()
end

--- 四宫格入口卡（白卡 + 图标 + 主标题 + 状态行；副标题两行手动断行防横向裁断）
local function entryCard(title, sub, onTap, opts)
    opts = opts or {}
    local kids = {}
    if opts.icon then
        kids[#kids + 1] = W.iconOrDot(opts.icon, 44, opts.iconDot)
    end
    kids[#kids + 1] = UI.Label {
        text = title,
        fontSize = Theme.font("toolbar", 28) * 1.15,
        fontColor = opts.titleColor or c("ink"),
        fontWeight = "bold",
        textAlign = "center",
        width = "100%",
        flexShrink = 1,
        marginTop = opts.icon and 10 or nil,
    }
    kids[#kids + 1] = UI.Label {
        text = W.wrapLines(sub or "", 9),
        fontSize = Theme.font("caption", 24),
        fontColor = opts.subColor or c("ink_dim"),
        textAlign = "center",
        width = "100%",
        marginTop = 10,
        flexShrink = 1,
    }
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
        children = kids,
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
                        function() Nav.go("court") end,
                        { icon = "home" }),
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
                        { icon = "challenge", titleColor = c("seal_deep") }),
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    entryCard("成语图鉴",
                        string.format("已收录 %d 条 · 错题本", Game.bookCount()),
                        function() Nav.go("book") end,
                        { icon = "book" }),
                    entryCard("商店", "金币 · 道具 · 免广告",
                        function() Nav.go("shop") end,
                        { icon = "shop" }),
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
                        Config.num("stamina.max", 50)),
                        { icon = "stamina", dotColor = c("jade") }),
                    UI.Panel { width = 16 },
                    W.chip("金币 " .. tostring(Game.gold()),
                        { icon = "gold", dotColor = c("coin"), fg = c("gold_dark") }),
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
