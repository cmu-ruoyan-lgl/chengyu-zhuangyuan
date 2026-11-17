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
-- 书童动画（S13：序列帧 sprite 模式为默认；S12 整图 image 模式为回退兜底）
-- sprite：UI.Sprite 图集无限循环（呼吸/翻页烘焙于帧），速度按 flip_interval
--   归一后乘 ui.scholar.speed（S20 起 =1.6），知识++ 由翻页帧 onFrameChange 驱动
-- image：单张 scholar.png + 呼吸起伏/坐姿轻摇 + 翻页页片 + 知识++，
--   所有周期与时长统一除以 ui.scholar.speed。
-- 循环一律 loop + alternate（onComplete 链会被 BaseUpdate 完成分支的
-- self.animation_ = nil 杀掉，见 RISK 9.0）。同一 widget 只有一个动画槽，
-- 所以「起伏」与「轻摇」必须分挂两层。
-- （rig 骨骼分支已删除：S10 AI 拟合姿态诡异、S11 程序化绘制太丑，
--   部件资源亦已移除，见 RISK 10.0/11.0/12.0。）
------------------------------------------------------------------------------

local scholarRefs_ = nil       -- { gen, sprite?, page?, kudos? }
local scholarHooked_ = false   -- ticker 只挂一次
local scholarGen_ = 0          -- 每次挂载 +1，旧代际的 tick 到代即停
local scholarFlipIn_ = 0       -- 距下次翻页的秒数（image 模式）

local pct = W.pct

local function cfgNum(key, default)
    return Config.num("ui.scholar." .. key, default)
end

--- 播放倍率（S20：用户指定 1.6 倍）。1 = 原速；所有周期/时长统一除以它，
--- 序列帧的 SetSpeed 则乘以它，保证 sprite 与 image 两种模式视觉节奏一致。
--- 防御非法值（0 / 负数 / 非数字）→ 退回 1，避免除零导致 ticker 永不触发。
local function scholarSpeed()
    local s = tonumber(cfgNum("speed", 1)) or 1
    if s <= 0 then return 1 end
    return s
end

--- 翻页周期（秒）：配置值 ÷ 倍率
local function flipInterval()
    return cfgNum("flip_interval", 5) / scholarSpeed()
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
--- 时长随 speed 缩短，避免倍率提高后飘字相对翻页显得拖沓
local function playKudos(kudos)
    W.anim(kudos, {
        keyframes = {
            [0]    = { opacity = 0, translateY = 8, scale = 0.7 },
            [0.38] = { opacity = 0, translateY = 8, scale = 0.7 },
            [0.56] = { opacity = 1, translateY = 0, scale = 1.12 },
            [0.84] = { opacity = 1, translateY = -24, scale = 1 },
            [1]    = { opacity = 0, translateY = -42, scale = 1 },
        },
        duration = cfgNum("kudos_duration", 1.35) / scholarSpeed(),
        easing = "easeOut",
    })
end

local function scholarTick(dt)
    local r = scholarRefs_
    if not r or r.gen ~= scholarGen_ then return end
    dt = tonumber(dt) or 0

    if not r.kudos then return end

    -- 翻页（image 模式）：书页贴片绕书脊翻动 → 知识++（sprite 模式不走这里，
    -- 其翻页/知识++ 由图集帧与 onFrameChange 驱动）
    scholarFlipIn_ = scholarFlipIn_ - dt
    if scholarFlipIn_ > 0 then return end
    scholarFlipIn_ = flipInterval()

    -- 书页翻动（opacity=0 起始/收尾，避免翻完残留一页）；
    -- 整图模式页片是盖在书上的白色贴片，绕书脊（页片左下角）翻动
    if r.page then
        local flip = cfgNum("image_page.rotate", -118)
        local dur = 0.85 / scholarSpeed()
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
    -- 知识++：前段静止等待，书页翻过一半后冒出、上飘淡出
    playKudos(r.kudos)
end

--- 整图模式（默认，config: ui.scholar.mode = "image"）：
-- scholar.png 单张贴图 + 呼吸起伏/坐姿轻摇 + 翻页页片 + 知识++
local function buildScholarImage()
    local size = cfgNum("size", 320)
    scholarGen_ = scholarGen_ + 1
    scholarFlipIn_ = flipInterval()

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

    scholarRefs_ = { gen = scholarGen_, page = page, kudos = kudos }
    if not scholarHooked_ then
        scholarHooked_ = true
        Ticker.add(scholarTick)
    end

    local bp = cfgNum("breathe_period", 3.4) / scholarSpeed()
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
local function buildScholarSprite(sizeOverride)
    local sp = Config.get("ui.scholar.sprite", nil) or {}
    local src = type(sp.src) == "string" and sp.src or "sprites/scholar/sprite.json"
    if not cache:Exists(src) then
        print("[home] 书童图集缺失，回退整图模式: " .. tostring(src))
        return buildScholarImage()
    end
    local size = sizeOverride or tonumber(sp.width) or cfgNum("size", 320)
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
    -- 循环周期归一：speed = (动画数据时长 / flip_interval) × 播放倍率
    -- （时长以 ms 烘焙进图集，GetDuration 返回秒；S20 乘 ui.scholar.speed=1.6，
    --   循环由 ~5s 缩到 ~3.13s，翻页/知识++ 同步加快）
    local dur = sprite:GetDuration(animName)
    if dur > 0 then
        local base = dur / math.max(0.5, cfgNum("flip_interval", 5))
        sprite:SetSpeed(base * scholarSpeed())
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
local function buildScholar(sizeOverride)
    if Config.get("ui.scholar.mode", "image") == "sprite" then
        return buildScholarSprite(sizeOverride)
    end
    return buildScholarImage()
end

--- 四宫格入口卡（白卡 + 图标 + 主标题 + 状态行；副标题两行手动断行防横向裁断）
local function entryCard(title, sub, onTap, opts)
    opts = opts or {}
    local kids = {}
    if opts.icon then
        -- 列容器居中：noMargin=true，避免行用 marginRight 把图标推偏
        kids[#kids + 1] = W.iconOrDot(opts.icon, Theme.fit(36), opts.iconDot, true)
    end
    kids[#kids + 1] = UI.Label {
        text = title,
        fontSize = Theme.font("toolbar", 28) * 1.15,
        fontColor = opts.titleColor or c("ink"),
        fontWeight = "bold",
        textAlign = "center",
        width = "100%",
        flexShrink = 1,
        marginTop = opts.icon and Theme.fit(8) or nil,
    }
    kids[#kids + 1] = UI.Label {
        text = W.wrapLines(sub or "", 12),
        fontSize = Theme.font("caption", 24),
        fontColor = opts.subColor or c("ink_dim"),
        textAlign = "center",
        width = "100%",
        marginTop = Theme.fit(8),
        flexShrink = 1,
    }
    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        -- S34：设计稿卡片有固定高度（屏高 14%），不能只靠文字撑高，
        -- 否则在瘦长真机上卡片被压扁、四宫格整体上移失衡。
        minHeight = opts.minHeight or nil,
        margin = Theme.fit(8),
        borderRadius = Theme.fit(20),
        backgroundColor = c("panel"),
        borderWidth = 3,
        borderColor = opts.border or c("panel_edge"),
        boxShadow = shadow(18, 7, 110),
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        paddingVertical = Theme.fit(16),
        paddingHorizontal = Theme.fit(12),
        onClick = onTap,
        children = kids,
    }
end

------------------------------------------------------------------------------
-- 右上角操作区（2026-11-16 设计稿）：VIP 胶囊 + 设置齿轮
-- VIP 指向商店（会员/权益入口）；设置提供大字号开关，沿用存档 settings.big_text。
-- 绝对定位到 root，避免占用正文分区高度；top 让开 TapTap 宿主退出胶囊。
------------------------------------------------------------------------------
local function buildTopActions()
    local pillH = Theme.fit(38)

    local gear = W.iconOrDot("settings", Theme.fit(26), nil, true)

    local settingsBtn = UI.Panel {
        id = "homeSettingsBtn",
        width = pillH,
        height = pillH,
        borderRadius = pillH / 2,
        backgroundColor = W.withAlpha(c("ink"), 170),
        justifyContent = "center",
        alignItems = "center",
        onClick = function()
            local ok, Modal = pcall(require, "ui.modal")
            if not ok or type(Modal) ~= "table" or not Modal.alert then return end
            Modal.alert({
                title = "设置",
                message = "大字号模式让文字更易读，点击「切换」后立即生效并保存。",
                buttonText = "切换大字号",
                onClose = function()
                    local save = Game.save()
                    if type(save) ~= "table" then return end
                    save.settings = save.settings or {}
                    local on = not save.settings.big_text
                    save.settings.big_text = on
                    Theme.setBigText(on)
                    Game.persist()
                    Nav.reset("home")
                end,
            })
        end,
        children = { gear },
    }

    local vipBtn = UI.Panel {
        id = "homeVipBtn",
        height = pillH,
        paddingHorizontal = Theme.fit(14),
        borderRadius = pillH / 2,
        backgroundColor = W.withAlpha(c("ink"), 170),
        justifyContent = "center",
        alignItems = "center",
        onClick = function() Nav.go("shop") end,
        children = { UI.Label {
            text = "VIP",
            fontSize = Theme.font("caption", 24) * 0.9,
            lineHeight = 1.0,
            fontColor = c("cream"),
            fontWeight = "bold",
            textAlign = "center",
            flexShrink = 1,
        } },
    }

    return UI.Panel {
        id = "homeTopActions",
        position = "absolute",
        top = math.max(Theme.fit(12), Theme.safeTop() + Theme.fit(6)),
        right = Theme.fit(20),
        flexDirection = "row",
        alignItems = "center",
        children = {
            vipBtn,
            UI.Panel { width = Theme.fit(10) },
            settingsBtn,
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
    -- S27：标题字号按可用宽封顶保证单行；顶部同时避让系统安全区与 TapTap 胶囊
    local header = UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        -- S34：外层锚点段已垂直居中；这里只保留宿主胶囊避让 + 少量余量，
        -- 避免旧的 fit(84) 与段居中叠加把标题推得过低。
        paddingTop = Theme.safeTop() + Theme.fit(10),
        children = {
            UI.Label {
                text = "成语小状元",
                fontSize = Theme.titleFontSize(5, 24, 1.2),
                fontColor = c("jade_deep"),
                fontWeight = "bold",
                textAlign = "center",
                width = "100%",
                flexShrink = 0,
            },
            UI.Label {
                text = "益智填词 · 出口成章",
                fontSize = Theme.font("caption", 24) * 0.9,
                fontColor = c("ink_dim"),
                textAlign = "center",
                width = "100%",
                marginTop = Theme.fit(10),
            },
            UI.Panel {
                marginTop = Theme.fit(14),
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
        -- S34：设计稿按钮宽约屏宽 66%、高约屏高 11.5%（46-57.5%）
        width = string.format("%d%%", math.floor(Config.num("ui.home_button_width", 0.66) * 100)),
        minHeight = (UI.GetHeight() or Config.num("ui.design_height", 1920))
            * Config.num("ui.home_button_min_h_ratio", 0.11),
        paddingVertical = Theme.fit(24),
        borderRadius = Theme.fit(36),
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
                fontSize = Theme.font("title", 56) * 0.92,
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
    -- 2026-11-16 设计稿：书童独立居中一行，闯关按钮在其正下方。
    -- 仍然保持 S30 的单屏目标：真机竖屏 5 段 space-between 一屏看全；
    -- 矮屏/横屏走 ScrollView 兜底，避免固定分区被压出 Layout Warning。
    local vw = UI.GetWidth() or Config.num("ui.design_width", 1080)
    local scholarSize = math.floor(math.min(
        cfgNum("home_size_max", 260),
        vw * cfgNum("home_width_ratio", 0.40)))
    local scholarSection = UI.Panel {
        width = "100%",
        paddingTop = Theme.fit(6),
        children = { buildScholar(scholarSize) },
    }
    local playSection = UI.Panel {
        width = "100%",
        alignItems = "center",
        paddingTop = Theme.fit(8),
        children = { playBtn },
    }

    -- 四宫格：府邸 / 挑战 / 图鉴 / 商店
    local pendingMark = Game.hasPendingDaily() and "（有奖励可领）" or ""
    -- S34：卡片固定最小高度 = 屏高 × home_card_min_h_ratio（设计稿约 14%），
    -- 让卡片饱满、四宫格总高贴合锚点，不再被文字行数牵着走。
    local vhPx = UI.GetHeight() or Config.num("ui.design_height", 1920)
    local cardMinH = vhPx * Config.num("ui.home_card_min_h_ratio", 0.14)
    local grid = UI.Panel {
        width = "100%",
        flexDirection = "column",
        paddingHorizontal = Theme.fit(22),
        marginTop = Theme.fit(28),
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    entryCard("府邸", "官邸门客 · 签到\n任务" .. pendingMark,
                        function() Nav.go("court") end,
                        { icon = "home", minHeight = cardMinH }),
                    entryCard("每日挑战",
                        string.format("限时 %d 词 ·\n今日剩 %d 次",
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
                        { icon = "challenge", titleColor = c("seal_deep"), minHeight = cardMinH }),
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    entryCard("成语图鉴",
                        string.format("已收录 %d 条 ·\n错题本", Game.bookCount()),
                        function() Nav.go("book") end,
                        { icon = "book", minHeight = cardMinH }),
                    entryCard("商店", "金币 · 道具 ·\n免广告",
                        function() Nav.go("shop") end,
                        { icon = "shop", minHeight = cardMinH }),
                },
            },
        },
    }

    -- 底部：体力 / 金币 + 健康忠告
    local footer = UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingBottom = Theme.fit(28),
        children = {
            UI.Panel {
                flexDirection = "row",
                justifyContent = "center",
                children = {
                    W.chip(string.format("体力 %d/%d", Game.stamina(),
                        Config.num("stamina.max", 50)),
                        { icon = "stamina", dotColor = c("jade") }),
                    UI.Panel { width = Theme.fit(16) },
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
                marginTop = Theme.fit(12),
                flexShrink = 1,
            },
        },
    }

    -- S34 设计稿锚点布局：真机竖屏按屏高百分比把 5 段固定分段、段内居中。
    -- 旧 space-between 会把多余空间均分到段间，在瘦长真机（0.463）上把四宫格
    -- 推到 70%（设计稿 60%）、底栏推到 96% 致健康文字被裁。固定分段后各元素
    -- 落回设计稿锚点：header 0-24.5% / 书童 24.5-46% / 按钮 46-58.5% /
    -- 四宫格 58.5-89% / 底栏 89-100%。
    -- 矮屏/横屏（headless 巡检 1322×546）仍走 ScrollView 兜底，避免 Layout Warning。
    local vh = UI.GetHeight() or Config.num("ui.design_height", 1920)
    local singleScreen = not Theme.isBigText()
        and vh >= vw * Config.num("ui.home_single_screen_ratio", 1.5)
    local rawSections = { header, scholarSection, playSection, grid, footer }
    local body
    if singleScreen then
        local ratios = {
            Config.num("ui.home_section.header", 0.245),
            Config.num("ui.home_section.scholar", 0.215),
            Config.num("ui.home_section.button", 0.125),
            Config.num("ui.home_section.grid", 0.305),
            Config.num("ui.home_section.footer", 0.11),
        }
        local anchored = {}
        for i, child in ipairs(rawSections) do
            anchored[#anchored + 1] = UI.Panel {
                width = "100%",
                height = pct(ratios[i]),
                justifyContent = "center",
                children = { child },
            }
        end
        body = UI.Panel {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            flexDirection = "column",
            children = anchored,
        }
    else
        body = UI.ScrollView {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            scrollY = true,
            showScrollbar = false,
            children = { UI.Panel {
                width = "100%",
                flexDirection = "column",
                flexShrink = 1,
                children = rawSections,
            } },
        }
    end

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = c("bg_top"),
        backgroundImage = "Textures/bg_main.png",
        backgroundFit = "cover",
        -- 右上角 VIP / 设置为绝对定位覆盖层，不占正文分区高度
        children = { body, buildTopActions() },
    }
    UI.SetRoot(root, true)
    return root
end

return Home
