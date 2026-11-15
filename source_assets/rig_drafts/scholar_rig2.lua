------------------------------------------------------------------------------
-- 书童骨骼动画（S11：程序化骨架）
-- 部件由 scripts/tools/draw_doll.py 按解剖学绘制：每个部件都是整幅 512 画布、
-- 且已处于最终位置的透明贴图 → 引擎侧全画幅叠放，装配误差为 0。
-- （S10 版本由 AI 合成图拟合而来，比例/关节不可控、动作诡异，已废弃。）
-- 骨架层级（变换沿渲染树继承，父骨动会带动子部件）：
--   box
--   ├ chair / arm_far / legs                静态（凳子、远侧手臂在身后、腿）
--   └ liftBone（呼吸起伏 translateY）
--       └ rootBone（绕髋微转 = 吸气，头/书/手臂作为子节点跟随）
--           ├ torso
--           ├ book → pageBone(绕书脊) → page
--           ├ arm_upper → foreBone(绕肘) → arm_fore
--           └ headBone(绕颈 点头) → head / eyes_open / eyes_shut
--   └ kudos「知识++」
-- 循环一律 loop + alternate（onComplete 链会被 BaseUpdate 完成分支的
-- self.animation_ = nil 杀掉，见 RISK 9.0）。同一 widget 只有一个动画槽，
-- 所以「起伏」与「旋转」必须分挂两层骨。
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

    if not (r.page and r.foreBone and r.kudos) then return end

    -- 翻页：抬手 → 书页绕书脊翻过去 → 手落回 → 知识++（翻过一半时冒出）
    scholarFlipIn_ = scholarFlipIn_ - dt
    if scholarFlipIn_ > 0 then return end
    scholarFlipIn_ = cfgNum("flip_interval", 5)

    local lift = cfgNum("arm_lift", -32)
    local flip = cfgNum("flip_degrees", -168)
    -- ① 前臂绕肘抬起，等书页翻过去再落回（保持段略微回弹，避免僵直）
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
    -- ② 书页绕书脊由右翻向左（opacity=0 起始/收尾，避免翻完残留一页）
    W.anim(r.page, {
        keyframes = {
            [0]    = { opacity = 0, rotate = 0 },
            [0.20] = { opacity = 1, rotate = -12 },
            [0.80] = { opacity = 1, rotate = flip + 18 },
            [1]    = { opacity = 0, rotate = flip },
        },
        duration = 1.0,
        easing = "easeInOut",
    })
    -- ③ 知识++：前段静止等待，书页翻过一半后冒出、上飘淡出
    W.anim(r.kudos, {
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

--- 整图兜底（config: ui.scholar.mode = "image"）：单张贴图 + 呼吸 + 知识++
local function buildScholarImage()
    local size = cfgNum("size", 320)
    scholarGen_ = scholarGen_ + 1
    scholarFlipIn_ = cfgNum("flip_interval", 5)
    scholarBlinkLeft_ = 0

    local kudos = buildKudos()
    local body = UI.Panel {
        width = size, height = size,
        position = "relative",
        backgroundImage = "Textures/scholar.png",
        backgroundFit = "contain",
        pointerEvents = "none",
        children = { kudos },
    }
    scholarRefs_ = { gen = scholarGen_, page = nil, foreBone = nil, kudos = kudos }
    if not scholarHooked_ then
        scholarHooked_ = true
        Ticker.add(scholarTick)
    end
    loopAnim(body, "translateY", -cfgNum("breathe_lift", 4), cfgNum("breathe_period", 3.4))
    return body
end
