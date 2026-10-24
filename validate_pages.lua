-- 【页面巡检入口，随仓库保留】让 headless validate 覆盖所有页面：
-- 登录（合规闸门）→ 棋盘 → 府邸 → 商店 → 图鉴。
-- 用法：bash tools/verify.sh validate_pages.lua
-- 注意：默认入口 main.lua 的 validate 只会走到登录页（未实名禁入），
--       棋盘与各系统页的布局巡检必须靠本入口。

local UI = require("urhox-libs/UI")
local Config = require("core.config")
local Game = require("system.game")
local Ticker = require("ui.ticker")

local frame = 0
local stage = 0

local function mount(tag, modName)
    local ok, Page = pcall(require, modName)
    if ok and type(Page) == "table" and Page.mount then
        Page.mount()
        print(string.format("[validate_pages] frame %d 挂载 %s ✅", frame, tag))
    else
        print(string.format("[validate_pages] frame %d 挂载 %s ❌ %s", frame, tag, tostring(Page)))
    end
end

function Start()
    Config.load()
    Game.init()
    UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT })

    -- 阶段 0：未实名 → 登录/合规闸门页
    mount("登录页", "ui.pages.login")

    -- 逐帧巡检：全项目统一走 ui/ticker（Update 事件是单槽的，禁止各页自行订阅）
    Ticker.add(function(dt)
        frame = frame + 1
        if frame % 5 == 0 then
            print(string.format("[validate_pages] tick frame %d stage %d dt=%.4f played=%.1fs",
                frame, stage, dt or -1, Game.compliance().playedSeconds))
        end
        if stage == 0 and frame >= 10 then
            stage = 1
            -- 模拟实名通过（成年），进入主页（主菜单）
            Game.setRealname(Config.num("compliance.default_adult_age", 25))
            mount("主页", "ui.pages.home")
        elseif stage == 1 and frame >= 16 then
            stage = 2
            mount("棋盘页", "ui.pages.play")
        elseif stage == 2 and frame >= 24 then
            stage = 3
            mount("府邸页", "ui.pages.court")
        elseif stage == 3 and frame >= 32 then
            stage = 4
            mount("商店页", "ui.pages.shop")
        elseif stage == 4 and frame >= 38 then
            stage = 5
            mount("图鉴页", "ui.pages.book")
        elseif stage == 5 and frame >= 44 then
            stage = 6
            -- 回到棋盘，验证重复挂载不炸
            mount("棋盘页（二次）", "ui.pages.play")
        elseif stage == 6 and frame >= 49 then
            stage = 7
            -- 第 3 段是 7×7（T24 新增 151–300 关）：验证棋盘按 rows/cols 自适应
            local ok151, err = Game.enterLevel(151)
            print(string.format("[validate_pages] enterLevel(151) %s %s",
                tostring(ok151), tostring(err)))
            local g = Game.session() and Game.session().grid
            if g then
                local r, c2 = g:size()
                print(string.format("[validate_pages] 151 关棋盘尺寸 %dx%d", r, c2))
            end
            mount("棋盘页（7×7 第151关）", "ui.pages.play")
        elseif stage == 7 and frame >= 55 then
            stage = 8
            -- 每日挑战是 8×8：验证最大棋盘不溢出
            local okCh, errCh = Game.startChallenge()
            print(string.format("[validate_pages] startChallenge %s %s",
                tostring(okCh), tostring(errCh)))
            local g = Game.session() and Game.session().grid
            if g then
                local r, c2 = g:size()
                print(string.format("[validate_pages] 挑战棋盘尺寸 %dx%d", r, c2))
            end
            mount("棋盘页（8×8 挑战）", "ui.pages.play")
        elseif stage == 8 and frame >= 58 then
            stage = 9
            -- 收尾：回主页，验证 Nav 栈外的直挂也正常
            mount("主页（二次）", "ui.pages.home")
        elseif stage == 9 and frame >= 59 then
            stage = 10
            -- 统一弹窗（S8）：验证挂载无布局告警
            local okM, Modal = pcall(require, "ui.modal")
            if okM and Modal and Modal.alert then
                Modal.alert({ title = "挑战次数已用完", message = "今日挑战次数已用完，明天再来吧" })
                print(string.format("[validate_pages] frame %d 弹窗挂载 ✅", frame))
            else
                print(string.format("[validate_pages] frame %d 弹窗挂载 ❌", frame))
            end
        end
    end)
end

function Stop()
    UI.Shutdown()
end
