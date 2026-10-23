-- 【临时校验入口，不入库】用来让 headless validate 覆盖府邸页与图鉴页的布局。
-- 用法：bash tools/verify.sh validate_pages.lua

local UI = require("urhox-libs/UI")
local Config = require("core.config")
local Game = require("system.game")

local frame = 0
local switched = false

function Start()
    Config.load()
    Game.init()
    UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT })

    local ok1, Court = pcall(require, "ui.pages.court")
    if ok1 and Court and Court.mount then
        Court.mount()
        print("[validate_pages] 府邸页已挂载")
    else
        print("[validate_pages] 府邸页加载失败: " .. tostring(Court))
    end

    if _G.SubscribeToEvent ~= nil then
        pcall(function()
            _G.SubscribeToEvent("Update", function()
                frame = frame + 1
                if not switched and frame >= 20 then
                    switched = true
                    local ok2, BookPage = pcall(require, "ui.pages.book")
                    if ok2 and BookPage and BookPage.mount then
                        BookPage.mount()
                        print("[validate_pages] 图鉴页已挂载")
                    else
                        print("[validate_pages] 图鉴页加载失败: " .. tostring(BookPage))
                    end
                end
            end)
        end)
    end
end

function Stop()
    UI.Shutdown()
end
