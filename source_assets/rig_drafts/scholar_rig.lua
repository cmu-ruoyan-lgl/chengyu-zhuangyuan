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
local function bone(jointName, children)
    local j = Config.get("ui.scholar.joints." .. jointName, nil)
    return UI.Panel {
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
    return box
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
