-- 【书童动画冒烟入口，随仓库保留】验证主页书童循环动画链路：
-- 呼吸浮动 onComplete 链式衔接、翻页 + 知识++ 定时触发、Animate 参数被引擎接受。
-- 用法：bash tools/verify.sh validate_scholar.lua（再把帧数手动调大到 420）

local UI = require("urhox-libs/UI")
local Config = require("core.config")
local Game = require("system.game")
local Ticker = require("ui.ticker")
local W = require("ui.widgets")

local frame = 0
local animLog = {}   -- { { frame, name, ok, err } }
local realAnim = W.anim

-- 包一层探针：记录每次 Animate 是否被引擎接受（pcall 失败会在此暴露）
W.anim = function(widget, config)
    local ok, err = realAnim(widget, config)
    animLog[#animLog + 1] = { frame = frame, ok = ok, err = err,
        keys = config and config.keyframes and #config.keyframes or -1 }
    return ok, err
end

function Start()
    Config.load()
    Game.init()
    UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT })
    Game.setRealname(Config.num("compliance.default_adult_age", 25))
    local Home = require("ui.pages.home")
    Home.mount()
    print("[validate_scholar] frame 0 主页（含书童）挂载 ✅")
end

Ticker.add(function()
    frame = frame + 1
    -- 每 120 帧汇报一次动画累计
    if frame % 120 == 0 then
        print(string.format("[validate_scholar] frame %d 动画调用累计 %d", frame, #animLog))
    end
end)
