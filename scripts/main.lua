-- 入口：初始化 存档/体力/音频 → 挂载 play 页。
-- 引擎约定：脚本需实现 Start()；Stop() 负责清理（写中断快照）。

local UI = require("urhox-libs/UI")
local Config = require("core.config")
local Game = require("system.game")
local SFX = require("system.audio")
local Play = require("ui.pages.play")

local booted = false

function Start()
    -- 【临时诊断】探测资源路径映射（远端 runtime.log 可见）。
    -- 注意：wasm 端引擎全局绑定是 userdata 而非 table，禁止 type()=="table" 判断，
    -- 一律 pcall 兜底。
    do
        local function try(tag, fn)
            local ok, res = pcall(fn)
            if ok then
                print(string.format("[probe] %s => %s", tag, tostring(res)))
            else
                print(string.format("[probe] %s => ERR %s", tag, tostring(res)))
            end
            return ok and res or nil
        end
        -- 1) 候选路径 Exists 探测（比 GetFile 轻量，不落错误日志）
        for _, p in ipairs({
            "data/config.json", "assets/data/config.json", "config.json",
            "Data/config.json", "data/levels/0001.json", "levels/0001.json",
            "Sounds/fill_ok.wav", "assets/Sounds/fill_ok.wav",
            "Fonts/MiSans-Regular.ttf", "fonts/MiSans-Regular.ttf",
        }) do
            try("exists:" .. p, function() return cache:Exists(p) end)
        end
        -- 3) 目录列举：直接看打包内各目录有什么（绕过 GetFile 语义）
        for _, d in ipairs({ "", "data/", "assets/", "Sounds/", "Fonts/", "levels/" }) do
            try("ls:" .. d, function()
                local files = fileSystem:ScanDir(d, "*", SCAN_ALL or 3, false)
                local n = 0
                local first = ""
                if files then
                    for _, name in ipairs(files) do
                        n = n + 1
                        if first == "" then first = tostring(name) end
                    end
                end
                return string.format("count=%d first=%s", n, first)
            end)
        end
        try("globals", function()
            return string.format("Scene=%s io=%s cache=%s fileSystem=%s",
                tostring(_G.Scene ~= nil), tostring(io ~= nil),
                tostring(_G.cache ~= nil), tostring(_G.fileSystem ~= nil))
        end)
    end

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
