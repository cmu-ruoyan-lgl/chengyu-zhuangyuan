-- 图鉴页（T18）：成语图鉴 + 错题本，支持查看释义/出处。
-- 只读 Game.bookList() / Game.wrongList()，不持有状态。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Game = require("system.game")
local W = require("ui.widgets")

local BookPage = {}

local function c(key, default)
    return W.c(key, default)
end

local function fs(key, default)
    return Theme.font(key, default)
end

--- 一条成语卡片：词 + 拼音 + 释义 + 出处
local function entryCard(entry, opts)
    opts = opts or {}
    local kids = {
        UI.Label {
            text = string.format("%s  %s", entry.word or "", entry.pinyin or ""),
            fontSize = fs("toolbar", 28),
            fontColor = opts.titleColor or c("ink"),
            fontWeight = "bold",
            width = "100%",
            flexShrink = 1,
        },
        UI.Label {
            text = "释义：" .. ((entry.meaning and entry.meaning ~= "") and entry.meaning or "暂无"),
            fontSize = fs("caption", 24),
            fontColor = c("ink_dim"),
            width = "100%",
            marginTop = 4,
            flexShrink = 1,
        },
    }
    if entry.source and entry.source ~= "" then
        kids[#kids + 1] = UI.Label {
            text = "出处：" .. entry.source,
            fontSize = fs("caption", 24),
            fontColor = c("ink_dim"),
            width = "100%",
            marginTop = 2,
            flexShrink = 1,
        }
    end
    return UI.Panel {
        width = "100%",
        borderRadius = 18,
        backgroundColor = opts.bg or W.withAlpha(W.c("bank_block"), 235),
        borderWidth = 2,
        borderColor = opts.border or W.c("panel_edge"),
        paddingHorizontal = 18,
        paddingVertical = 12,
        marginBottom = 10,
        children = kids,
    }
end

local function sectionCard(title, subtitle, children)
    return W.sectionCard(title, children, { subtitle = subtitle })
end

function BookPage.mount()
    local unlocked = Game.bookList()
    local wrong = Game.wrongList()

    local bookKids = {}
    if #unlocked == 0 then
        bookKids[#bookKids + 1] = UI.Label {
            text = "还没有收录成语，通关后自动解锁",
            fontSize = fs("caption", 24),
            fontColor = W.c("ink_dim"),
            width = "100%",
        }
    else
        for _, e in ipairs(unlocked) do
            bookKids[#bookKids + 1] = entryCard(e)
        end
    end

    local wrongKids = {}
    if #wrong == 0 then
        wrongKids[#wrongKids + 1] = UI.Label {
            text = "错题本是空的，保持住",
            fontSize = fs("caption", 24),
            fontColor = W.c("ink_dim"),
            width = "100%",
        }
    else
        for _, e in ipairs(wrong) do
            wrongKids[#wrongKids + 1] = entryCard(e, {
                titleColor = W.c("seal_deep"),
                bg = W.withAlpha(W.c("cell_error"), 60),
            })
        end
    end

    local body = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = true,
        paddingHorizontal = 24,
        paddingVertical = 10,
        children = {
            sectionCard("错题本", string.format("共 %d 条", #wrong), wrongKids),
            sectionCard("成语图鉴", string.format("已收录 %d 条", #unlocked), bookKids),
        },
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = c("bg_top"),
        backgroundImage = "Textures/bg_main.png",
        backgroundFit = "cover",
        children = {
            W.pageHeader("图鉴", nil, function()
                local ok, Court = pcall(require, "ui.pages.court")
                if ok and Court and Court.mount then Court.mount() end
            end),
            body,
        },
    }
    UI.SetRoot(root, true)
    return root
end

return BookPage
