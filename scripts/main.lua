-- 入口：初始化 UI、加载配置、进入 play 页。
-- 引擎约定：脚本需实现 Start()；Stop() 负责清理。

local UI = require("urhox-libs/UI")
local Config = require("core.config")
local Play = require("ui.pages.play")

-- 启动关卡：M1 阶段固定第 1 关，后续由路由/存档决定
local START_LEVEL = 1

local booted = false

function Start()
    local okCfg, errCfg = Config.load()
    if not okCfg then
        print("[main] 配置加载失败: " .. tostring(errCfg))
    end

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

    local s, err = Play.mount(START_LEVEL)
    if not s then
        print("[main] 进入关卡失败: " .. tostring(err))
        return
    end
    booted = true
    print("[main] play 页已挂载，关卡 " .. tostring(s.levelId))
end

function Stop()
    if booted then
        UI.Shutdown()
        booted = false
    end
end
