-- 【书童动画冒烟入口，随仓库保留】验证主页书童循环动画链路（模式无关）：
--   sprite 模式：UI.Sprite 图集循环常驻存活、每循环翻页帧触发知识++；
--   image 模式：ticker 按 flip_interval/speed 触发翻页 + 知识++。
-- 判定依据：知识++（5 关键帧动画）按 flip_interval/speed 周期重复出现、0 Lua 错误。
-- 用法：VALIDATE_FRAMES=760 bash tools/verify.sh validate_scholar.lua
-- S20：播放倍率 ui.scholar.speed=1.6 → 知识++ 时长与触发间隔同步除以倍率。

local UI = require("urhox-libs/UI")
local Config = require("core.config")
local Game = require("system.game")
local Ticker = require("ui.ticker")
local W = require("ui.widgets")

-- 注意：Config.load() 在 Start() 里才执行，倍率必须延迟到 tick 时再读
local function scholarSpeed()
    local s = tonumber(Config.num("ui.scholar.speed", 1)) or 1
    if s <= 0 then return 1 end
    return s
end
local function kudosDur()
    return Config.num("ui.scholar.kudos_duration", 1.35) / scholarSpeed()
end

local frame = 0
local animLog = {}        -- { { frame, dur } }：全部关键帧动画调用
local kudosFrames = {}    -- 知识++ 触发帧号（kudos 动画专属 duration=kudosDur()）
local reported = false
local realAnim = W.anim

W.anim = function(widget, config)
    local ok, err = realAnim(widget, config)
    animLog[#animLog + 1] = {
        frame = frame, ok = ok, err = err,
        dur = config and config.duration or -1,
    }
    return ok, err
end

function Start()
    Config.load()
    Game.init()
    UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT })
    Game.setRealname(Config.num("compliance.default_adult_age", 25))

    -- 序列帧模式：先断言图集可加载、read 动画存在且时长为正（缓存实例与页面共用）
    if Config.get("ui.scholar.mode", "image") == "sprite" then
        local src = Config.get("ui.scholar.sprite.src", "sprites/scholar/sprite.json")
        local sheet = UI.SpriteSheet.Load(src)
        assert(sheet, "图集加载失败: " .. tostring(src))
        local animName = Config.get("ui.scholar.sprite.anim_read", "read")
        local durMs = sheet:GetAnimationDuration(animName)
        assert(durMs and durMs > 0, "动画缺失或时长为 0: " .. tostring(animName))
        print(string.format("[validate_scholar] 图集 ✅ %s（%d 帧 / %dms）",
            tostring(src), sheet:GetFrameCount(), durMs))
    end

    local Home = require("ui.pages.home")
    Home.mount()
    print("[validate_scholar] frame 0 主页（含书童）挂载 ✅ mode="
        .. tostring(Config.get("ui.scholar.mode", "image")))
end

Ticker.add(function(dt)
    frame = frame + 1
    -- 统计知识++ 触发（playKudos 专属 duration=kudosDur()；关键帧表键非连续整数，
    -- #keyframes 不可用作特征——首版探针在此翻车）
    for _, a in ipairs(animLog) do
        if a.frame == frame - 1 and a.dur == kudosDur() and a.ok then
            kudosFrames[#kudosFrames + 1] = a.frame
            print(string.format("[validate_scholar] 知识++ 第 %d 次触发 @frame %d",
                #kudosFrames, a.frame))
        end
    end
    if frame % 120 == 0 then
        print(string.format("[validate_scholar] frame %d 累计动画 %d 次 / 知识++ %d 次",
            frame, #animLog, #kudosFrames))
    end
    -- 收尾终检（只报一次）
    if frame >= 750 and not reported then
        reported = true
        local n = #kudosFrames
        if n >= 2 then
            local gap = kudosFrames[n] - kudosFrames[n - 1]
            local expect = Config.num("ui.scholar.flip_interval", 5) / scholarSpeed()
            print(string.format(
                "[validate_scholar] ✅ 知识++ 触发 %d 次，最近间隔 %d 帧（speed=%.2f / 期望 %.0f 帧 = %.3fs）",
                n, gap, scholarSpeed(), expect * 60, expect))
        else
            print("[validate_scholar] ❌ 知识++ 触发不足 2 次，循环疑似中断")
        end
    end
end)
