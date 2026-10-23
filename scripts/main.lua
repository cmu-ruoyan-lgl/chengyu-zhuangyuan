-- 入口：初始化 存档/体力/音频 → 挂载 play 页。
-- 引擎约定：脚本需实现 Start()；Stop() 负责清理（写中断快照）。

local UI = require("urhox-libs/UI")
local Config = require("core.config")
local Game = require("system.game")
local SFX = require("system.audio")
local Play = require("ui.pages.play")
local Login = require("ui.pages.login")

local booted = false

function Start()
    local okCfg, errCfg = Config.load()
    if not okCfg then
        print("[main] 配置加载失败: " .. tostring(errCfg))
    end

    -- 读档 + 体力离线恢复结算（进任何 UI 前完成，杀进程不丢）
    local save = Game.init()

    local okAudio, whyAudio = SFX.init({ sound = save.settings and save.settings.sound })
    print("[main] 音效通道 " .. (okAudio and "就绪" or ("降级: " .. tostring(whyAudio))))

    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })

    -- 竖屏基准（config.ui.design_*），实际由运行时窗口决定
    local dw = Config.num("ui.design_width", 1080)
    local dh = Config.num("ui.design_height", 1920)
    print(string.format("[main] 设计基准 %dx%d", dw, dh))
    local vw, vh = UI.GetViewportSize()
    print(string.format("[main] viewport(base)=%.0fx%.0f scale=%.3f screen=%dx%d",
        vw or -1, vh or -1, UI.GetScale() or -1,
        UI.GetScreenWidth() or -1, UI.GetScreenHeight() or -1))

    -- 云档启动合并（best-effort，异步；失败不影响本地档）
    Game.tryCloudMerge(function(adopted)
        if adopted then
            print("[main] 已采纳云端存档")
        end
    end)

    -- 合规闸门（T23）：未实名禁入；未成年非开放时段/超时长不得进入
    local info = Game.compliance()
    if not info.canPlay then
        print("[main] 合规闸门生效：" .. tostring(info.reason))
        Login.mount()
        booted = true
        return
    end

    local s = Play.mount()
    if s then
        print("[main] play 页已挂载，关卡 " .. tostring(s.levelId)
            .. string.format("（体力 %d，金币 %d）", Game.stamina(), Game.gold()))
    else
        print("[main] 体力不足，已挂体力门（当前体力 " .. tostring(Game.stamina()) .. "）")
    end
    booted = true
end

function Stop()
    if booted then
        -- 中断快照：杀进程/退出时保留当前关进度
        Game.abandon()
        UI.Shutdown()
        booted = false
    end
end
