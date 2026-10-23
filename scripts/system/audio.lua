-- 音效播放（T11 反馈通道的音频侧）。
-- 引擎内自建 Scene + SoundSource 播放 assets/Sounds/*.wav；
-- 引擎文档要求：自己 new 的 Scene 必须模块级持有，否则 GC 随机闪退。
-- 触觉按裁决 #20 视为不可用，由 UI 层视觉抖动替代。
-- 全部 pcall 降级：无引擎/无资源/无音频设备时静默失败，不阻塞玩法。

local M = {}

-- 事件 → 资源路径（引擎资源路径 Sounds/x.wav → assets/Sounds/x.wav）
local NAMES = {
    fill_ok    = "Sounds/fill_ok.wav",
    fill_err   = "Sounds/fill_err.wav",
    idiom_done = "Sounds/idiom_done.wav",
    cross_ok   = "Sounds/cross_ok.wav",
    level_win  = "Sounds/level_win.wav",
}

local scene_ = nil   -- 模块级持有，防 GC
local source_ = nil
local sounds_ = {}
local enabled_ = true

--- 初始化（main.lua Start 时调用一次）。opts.sound=false 时静音。
--- 返回 true=可用；false+原因=降级（静默，非错误）。
function M.init(opts)
    enabled_ = not (opts and opts.sound == false)
    if not enabled_ then return false, "muted" end
    if type(_G.Scene) ~= "table" or type(_G.cache) ~= "table" then
        return false, "no_engine"
    end
    local ok, err = pcall(function()
        scene_ = _G.Scene()
        local node = scene_:CreateChild("SFX")
        source_ = node:CreateComponent("SoundSource")
        for name, resPath in pairs(NAMES) do
            local okRes, snd = pcall(function() return _G.cache:GetResource("Sound", resPath) end)
            if okRes and snd then
                sounds_[name] = snd
            else
                print("[audio] 音效缺失，跳过: " .. resPath)
            end
        end
    end)
    if not ok then
        scene_, source_, sounds_ = nil, nil, {}
        return false, tostring(err)
    end
    return true
end

--- 播放一个事件音。gain 可省。失败返回 false（静默降级）。
function M.play(name, gain)
    if not enabled_ then return false end
    local snd = sounds_[name]
    if not snd or not source_ then return false end
    -- frequency=0 表示用素材采样率原速播放（引擎 Audio 文档约定）
    local ok = pcall(function() source_:Play(snd, 0, gain or 0.6) end)
    return ok
end

function M.setEnabled(on)
    enabled_ = on and true or false
end

function M.isEnabled()
    return enabled_
end

function M.available()
    return source_ ~= nil and next(sounds_) ~= nil
end

return M
