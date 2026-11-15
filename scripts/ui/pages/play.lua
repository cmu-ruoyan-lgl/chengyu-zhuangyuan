-- play 页：状态条 + 进度条 + 矩阵 + 备选区 + 道具栏 + 通关特效 + 体力门（DEV §10.2）。
-- 严格分层：本页只订阅 Session 事件渲染 + 调用 Game 逻辑层，不持有游戏状态。
-- T11 反馈通道：音效（system/audio）+ 关键帧动效（ui/fx）；触觉按裁决 #20 视为不可用。
-- 视觉：清新薄荷绿系（S5-4 定稿），所有配色/字号/动效参数读 config，禁止硬编码。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local SFX = require("system.audio")
local Warm = require("system.glyphwarm")
local FX = require("ui.fx")
local W = require("ui.widgets")
local Ticker = require("ui.ticker")

-- 样式/组件统一走 ui/widgets（与府邸页、图鉴页共享同一套清新风格）
local pct, c, withAlpha, shadow, pieceShadow, anim =
    W.pct, W.c, W.withAlpha, W.shadow, W.pieceShadow, W.anim
local chip, pillButton = W.chip, W.pillButton

local Play = {}

local refs = {
    root = nil,
    session = nil,
    cells = {},      -- [r][c] = { panel, label }
    bank = {},       -- [i] = { panel, label }
    levelChip = nil,
    progressFill = nil,
    topStamina = nil,
    topGold = nil,
    banner = nil,
    bannerBox = nil,
    nextBtn = nil,
    gate = nil,
    gateInfo = nil,
    hintBtn = nil,
    fxLayer = nil,
    clear = nil,
    clearCard = nil,
    clearReward = nil,
    clearCards = nil,
    challengeChip = nil,
    compliance = nil,
    complianceNotice = nil,
}

------------------------------------------------------------------------------
-- 工具
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- 单元格样式
------------------------------------------------------------------------------

local function cellStyle(grid, r, cc, selected, flashWrong)
    local cell = grid:getCell(r, cc)
    if not cell then
        -- 非格子位置（成语字以外的空白）必须完全隐形：底色/描边都与卡片同色，
        -- 且不加投影（S7：此前渲染成白块，整个棋盘像 N×N 个空格，误导点击）
        return c("panel"), c("panel"), c("ink")
    end
    if flashWrong then
        return c("cell_error"), c("seal"), c("cream")
    end
    if selected then
        return c("gold"), c("gold_dark"), c("ink")
    end
    if cell.isPreset then
        return c("cell_fixed"), c("gold_deep"), c("ink")
    end
    if cell.value ~= nil then
        local allDone = true
        for _, id in ipairs(cell.owners) do
            if not grid.idioms[id].done then allDone = false; break end
        end
        return allDone and c("cell_done") or c("cell_filled"),
               allDone and c("jade_deep") or c("panel_edge"),
               c("ink")
    end
    return c("cell_empty"), c("panel_edge"), c("ink")
end

local function cellText(grid, r, col)
    local cell = grid:getCell(r, col)
    if not cell or cell.answer == nil then return "" end
    return cell.value or ""
end

--- 错填抖动（裁决 #20：触觉不可用 → 视觉抖动增强）
local function shakeCell(r, col)
    local ref = refs.cells[r] and refs.cells[r][col]
    if not ref then return end
    anim(ref.panel, {
        keyframes = {
            [0]   = { translateX = 0, borderColor = c("seal") },
            [0.2] = { translateX = -9, borderColor = c("seal") },
            [0.4] = { translateX = 9, borderColor = c("seal") },
            [0.6] = { translateX = -5, borderColor = c("seal") },
            [0.8] = { translateX = 5, borderColor = c("seal") },
            [1]   = { translateX = 0, borderColor = c("panel_edge") },
        },
        duration = 0.32,
        easing = "linear",
    })
end

--- 正确填字：弹性放大 + 暖金闪一下
local function popCell(r, col)
    local ref = refs.cells[r] and refs.cells[r][col]
    if not ref then return end
    anim(ref.panel, {
        keyframes = {
            [0]   = { scale = 0.72 },
            [0.5] = { scale = 1.12 },
            [0.75] = { scale = 0.96 },
            [1]   = { scale = 1 },
        },
        duration = 0.28,
        easing = "easeOut",
    })
    anim(ref.label, {
        keyframes = {
            [0] = { fontColor = c("gold_dark") },
            [1] = { fontColor = c("ink") },
        },
        duration = 0.4,
        easing = "easeOut",
    })
end

------------------------------------------------------------------------------
-- 构建：顶栏 / 进度条 / 棋盘 / 备选区 / 道具栏 / 横幅
------------------------------------------------------------------------------

-- S27：真机上原先 5 个胶囊等距挤满一行、且右上角被 TapTap 宿主胶囊压住。
-- 改为「左组（导航 / 关卡 / 挑战）+ 右组（体力 / 金币）」两簇，中间由 space-between
-- 拉开大留白；整条状态栏再由 root 的顶部安全区占位下移，避开平台胶囊。
-- 不用上下两行：矮视口（headless 横屏）下两行内容会撑破 pct 高度产生 Layout Warning。
local function buildTopBar(session)
    local isChallenge = (Game.mode() == "challenge")
    local fit = Theme.fit
    refs.levelChip = chip(isChallenge and "每日挑战"
        or (session and ("第 " .. tostring(session.levelId) .. " 关") or "成语小状元"), {
        bg = c("gold_deep"), border = c("gold_dark"), fg = c("ink"), bold = true,
        glow = "gold",
    })
    refs.topStamina = chip("体力 --", { dotColor = c("jade") })
    refs.topGold = chip("金币 --", { dotColor = c("coin"), fg = c("gold_dark") })
    -- 挑战倒计时（仅挑战模式可见，由 Play.tick 每秒刷新）
    refs.challengeChip = chip("剩余 --", { dotColor = c("seal"), fg = c("text_light") })
    if not isChallenge then refs.challengeChip:SetVisible(false) end

    local spacer = function()
        return UI.Panel { width = fit(12), flexShrink = 0 }
    end
    local navGroup = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        flexShrink = 1,
        children = {
            chip("主页", {
                bg = withAlpha(c("chip_bg"), 235),
                border = c("chip_edge"), fg = c("ink"), bold = true,
                onClick = function() Play.goHome() end,
            }),
            spacer(), refs.levelChip, spacer(), refs.challengeChip,
        },
    }
    local statGroup = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        flexShrink = 1,
        children = { refs.topStamina, spacer(), refs.topGold },
    }
    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("topbar", 0.105)),
        flexShrink = 1,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = fit(28),
        children = { navGroup, statGroup },
    }
end

local function buildProgressBar()
    refs.progressFill = UI.Panel {
        width = "0%",
        height = "100%",
        borderRadius = 8,
        backgroundGradient = {
            direction = "to-right",
            from = c("gold"),
            to = c("gold_deep"),
        },
    }
    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("progress", 0.014)),
        flexShrink = 1,
        flexDirection = "row",
        paddingHorizontal = 30,
        children = { UI.Panel {
            width = "100%", height = "100%",
            borderRadius = 8,
            backgroundColor = withAlpha(c("chip_bg", { 58, 40, 28, 255 }), 235),
            borderWidth = 2,
            borderColor = c("chip_edge"),
            flexDirection = "row",
            children = { refs.progressFill },
        } },
    }
end

local function buildBoard(session)
    local radius = Theme.num("cell_radius", 14)
    if not session then
        return UI.Panel {
            width = "100%",
            height = pct(Theme.ratio("board", 0.446)),
            flexShrink = 1,
            paddingHorizontal = 24,
            children = { UI.Panel {
                width = "100%",
                height = "100%",
                backgroundColor = c("panel"),
                borderRadius = 26,
                boxShadow = shadow(26, 10, 120),
                justifyContent = "center",
                alignItems = "center",
                children = { UI.Label {
                    text = "体力恢复后即可闯关",
                    fontSize = Theme.font("caption", 24),
                    fontColor = c("ink_dim"),
                } },
            } },
        }
    end

    local grid = session.grid
    local rows, cols = grid:size()
    local gap = Theme.num("cell_gap", 8)

    -- 格子边长：同时受卡片可用宽/高约束（窄屏时按宽收缩，保证棋盘不溢出、左右对称）
    local vw = UI.GetWidth() or Config.num("ui.design_width", 1080)
    local vh = UI.GetHeight() or Config.num("ui.design_height", 1920)
    local cardW = vw - 48 - 32                    -- 卡片外边距 24*2 + 内边距 16*2
    local cardH = vh * Theme.ratio("board", 0.446) - 28
    local cellSize = math.floor(math.min(
        (cardW - gap * (cols - 1)) / cols,
        (cardH - gap * (rows - 1)) / rows))
    -- 汉字与格子边长绑定，用 fontRaw：不随 UI 文案的视口字号系数缩小
    local fontSize = math.min(Theme.fontRaw("hanzi", 40), cellSize * 0.52)

    local rowPanels = {}
    for r = 0, rows - 1 do
        refs.cells[r] = {}
        local cellPanels = {}
        for cIdx = 0, cols - 1 do
            local bg, border, fg = cellStyle(grid, r, cIdx, false, false)
            local isReal = grid:getCell(r, cIdx) ~= nil
            -- Label 不要写 width/height="100%"：百分比高度会撑满父容器可用高度导致溢出。
            -- 居中交给父 Panel 的 justifyContent/alignItems，格子用 aspectRatio=1 保证正方形。
            local label = UI.Label {
                text = cellText(grid, r, cIdx),
                fontSize = fontSize,
                fontColor = fg,
                textAlign = "center",
                verticalAlign = "middle",
                fontWeight = "bold",
                lineHeight = 1.0,
                flexShrink = 1,
            }
            local panel = UI.Panel {
                width = cellSize,
                height = cellSize,
                margin = gap / 2,
                backgroundColor = bg,
                borderWidth = 2,
                borderColor = border,
                borderRadius = radius,
                boxShadow = isReal and pieceShadow() or nil,
                justifyContent = "center",
                alignItems = "center",
                onClick = function() Play.onCellTapped(r, cIdx) end,
                children = { label },
            }
            refs.cells[r][cIdx] = { panel = panel, label = label }
            cellPanels[#cellPanels + 1] = panel
        end
        rowPanels[#rowPanels + 1] = UI.Panel {
            flexDirection = "row",
            justifyContent = "center",
            alignItems = "center",
            children = cellPanels,
        }
    end

    -- 注意：卡片不能直接写 width="100%" + marginHorizontal——Yoga 与 CSS 一样，
    -- 100% 宽不会为 margin 收缩，会向右溢出父容器（实测右留白被吃掉，整体右偏）。
    -- 正确姿势：外层 section 用 paddingHorizontal，卡片 width="100%" 内嵌。
    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("board", 0.446)),
        flexShrink = 1,
        paddingHorizontal = 24,
        paddingVertical = 6,
        children = { UI.Panel {
            width = "100%",
            height = "100%",
            flexDirection = "column",
            justifyContent = "center",
            alignItems = "center",
            paddingHorizontal = 16,
            paddingVertical = 8,
            backgroundColor = c("panel"),
            borderRadius = 26,
            borderWidth = 3,
            borderColor = c("panel_edge"),
            boxShadow = shadow(26, 10, 120),
            children = rowPanels,
        } },
    }
end

local function buildBank(session)
    local gap = Theme.num("cell_gap", 8)
    local block = Theme.num("bank_block_min", 88)
    -- 汉字跟着字块边长走，不随视口字号系数缩小（否则真机上大块里一个很小的字）
    local fontSize = math.min(Theme.fontRaw("hanzi", 40), block * 0.56)
    local vw = select(1, UI.GetViewportSize()) or 1080
    local usable = vw - 60
    local perRow = math.max(1, math.floor(usable / (block + gap)))
    -- 窄屏（真机）算出的列数不稳定，固定成 2 行 × 4 列的稳定节奏，点击区也更宽松。
    -- 宽屏（headless 横屏巡检）不能限列：本来 1 行能放完，限成 4 列会变 2~4 行
    -- 撑破 bank 的 pct 高度，产生 Layout Warning（S27 实测）。
    if vw < Config.num("ui.design_width", 1080) * 0.7 then
        perRow = math.min(Theme.num("bank_per_row_max", 4), perRow)
    end

    refs.bank = {}
    if not session then
        return UI.Panel {
            width = "100%", height = pct(Theme.ratio("bank", 0.25)),
            flexShrink = 1,
        }
    end

    local rows, rowChildren, current = {}, {}, nil
    for i, item in ipairs(session.bank) do
        if not current or #current >= perRow then
            current = {}
            rowChildren[#rowChildren + 1] = current
        end
        local label = UI.Label {
            text = item.char,
            fontSize = fontSize,
            fontColor = c("ink"),
            textAlign = "center",
            verticalAlign = "middle",
            fontWeight = "bold",
            lineHeight = 1.0,
            width = "100%",
            height = "100%",
            flexShrink = 1,
        }
        local idx = i
        local panel = UI.Panel {
            width = block,
            height = block,
            margin = gap / 2,
            backgroundColor = c("bank_block"),
            borderWidth = 2,
            borderColor = c("panel_edge"),
            borderRadius = Theme.num("cell_radius", 14),
            boxShadow = pieceShadow(),
            justifyContent = "center",
            alignItems = "center",
            onClick = function() Play.onBankTapped(idx) end,
            children = { label },
        }
        refs.bank[i] = { panel = panel, label = label }
        current[#current + 1] = panel
    end

    for _, children in ipairs(rowChildren) do
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            children = children,
        }
    end

    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("bank", 0.25)),
        flexShrink = 1,
        flexDirection = "column",
        justifyContent = "center",
        children = rows,
    }
end

local function buildToolBar(session)
    local isChallenge = (Game.mode() == "challenge")
    refs.hintBtn = pillButton("提示", function() Play.onHint() end)
    -- 府邸入口（S2：官职/门客/签到/图鉴/挑战都在这里）
    local courtBtn = pillButton("府邸", function() Play.openCourt() end, {
        gradient = { direction = "to-bottom", from = c("jade"), to = c("jade_deep") },
        fg = c("cream"),
        glow = "jade_deep",
    })
    local shuffleBtn = pillButton("洗牌", function() Play.onShuffle() end)
    -- 挑战模式：交卷提前结束并结算（限时到也会自动结算）
    local challengeBtn = pillButton("交卷", function() Play.onFinishChallenge() end, {
        gradient = { direction = "to-bottom", from = c("seal"), to = c("seal_deep") },
        fg = c("cream"),
        glow = "seal_deep",
    })
    if isChallenge then
        courtBtn:SetVisible(false)
        shuffleBtn:SetVisible(false)
    else
        challengeBtn:SetVisible(false)
    end
    refs.nextBtn = UI.Button {
        text = "下一关",
        fontSize = Theme.font("toolbar", 28),
        visible = false,
        marginHorizontal = 7,
        paddingHorizontal = 26,
        paddingVertical = 14,
        borderRadius = 30,
        backgroundGradient = { direction = "to-bottom", from = c("jade"), to = c("jade_deep") },
        textColor = c("cream"),
        fontWeight = "bold",
        boxShadow = shadow(16, 6, 130, "jade_deep"),
        borderWidth = 2,
        borderColor = c("jade_deep"),
        onClick = function() Play.onNextLevel() end,
    }
    if not session then
        return UI.Panel {
            width = "100%",
            height = pct(Theme.ratio("toolbar", 0.142)),
            flexShrink = 1,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            children = { refs.nextBtn },
        }
    end
    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("toolbar", 0.15)),
        flexShrink = 1,
        flexDirection = "column",
        justifyContent = "center",
        paddingHorizontal = Theme.fit(28),
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                children = {
                    challengeBtn,
                    courtBtn,
                    refs.hintBtn,
                    pillButton("撤销", function() Play.onUndo() end),
                    shuffleBtn,
                    refs.nextBtn,
                },
            },
        },
    }
end

--- 回主页：闯关模式先写中断快照（回来不掉进度）；挑战模式按交卷结算
--- （挑战卷快照若写进主线 current，恢复时会串关，故绝不快照挑战会话）
function Play.goHome()
    if Game.mode() == "challenge" then
        Game.finishChallenge()
    else
        Game.abandon()
    end
    local ok, Nav = pcall(require, "ui.nav")
    if ok and Nav and Nav.reset then
        Nav.reset("home")
    end
end

--- 结果类提示统一弹窗（S8）；高频棋局反馈仍走 banner 吐司
local function alertModal(title, message)
    local ok, Modal = pcall(require, "ui.modal")
    if ok and Modal and Modal.alert then
        Modal.alert({ title = title, message = message })
    else
        print("[play] " .. tostring(title) .. ": " .. tostring(message))
    end
end

--- 打开府邸页（S2 系统总入口：官职/门客/签到/图鉴/挑战）
function Play.openCourt()
    Game.abandon()   -- 离开棋盘先写中断快照，返回时 Play.mount 才能无损恢复
    local ok, Nav = pcall(require, "ui.nav")
    if ok and Nav and Nav.go then
        Nav.go("court")
        return
    end
    local okC, Court = pcall(require, "ui.pages.court")
    if okC and type(Court) == "table" and Court.mount then
        Court.mount()
    else
        alertModal("加载失败", "府邸页加载失败，请稍后再试")
    end
end

------------------------------------------------------------------------------
-- 横幅（吐司）
------------------------------------------------------------------------------

local function buildBanner()
    local label = UI.Label {
        text = "",
        fontSize = Theme.font("caption", 24),
        fontColor = c("text_light"),
        textAlign = "center",
        fontWeight = "bold",
        lineHeight = 1.0,
        flexShrink = 1,
    }
    refs.banner = label
    refs.bannerBox = UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("banner", 0.06)),
        flexShrink = 1,
        justifyContent = "center",
        alignItems = "center",
        children = { UI.Panel {
            paddingHorizontal = 24,
            paddingVertical = 4,
            flexShrink = 1,
            borderRadius = 24,
            backgroundColor = withAlpha(c("chip_bg"), 235),
            borderWidth = 2,
            borderColor = c("chip_edge"),
            boxShadow = shadow(14, 4, 90),
            justifyContent = "center",
            alignItems = "center",
            children = { label },
        } },
    }
    return refs.bannerBox
end

local function showBanner(text, colorKey)
    if not refs.banner then return end
    refs.banner:SetStyle({ text = text, fontColor = colorKey and c(colorKey) or c("text_light") })
    anim(refs.bannerBox, {
        keyframes = {
            [0]   = { opacity = 0, translateY = 14, scale = 0.9 },
            [0.4] = { opacity = 1, translateY = -4, scale = 1.04 },
            [1]   = { opacity = 1, translateY = 0, scale = 1 },
        },
        duration = 0.32,
        easing = "easeOut",
    })
end

------------------------------------------------------------------------------
-- 通关特效弹层（印章 logo + 爆星星 + 金币雨）
------------------------------------------------------------------------------

local function buildClearOverlay()
    local emblemSize = 240
    local sealSize = 176
    local emblem = UI.Panel {
        width = emblemSize, height = emblemSize,
        borderRadius = emblemSize * 0.5,
        backgroundGradient = { direction = "to-bottom", from = c("gold"), to = c("gold_deep") },
        borderWidth = 4,
        borderColor = c("gold_dark"),
        boxShadow = shadow(30, 10, 160, "gold"),
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = sealSize, height = sealSize,
                borderRadius = 26,
                backgroundGradient = { direction = "to-bottom", from = c("seal"), to = c("seal_deep") },
                borderWidth = 3,
                borderColor = withAlpha(c("cream"), 200),
                justifyContent = "center",
                alignItems = "center",
                children = { UI.Label {
                    text = "过关",
                    fontSize = Theme.font("emblem", 64),
                    fontColor = c("cream"),
                    fontWeight = "bold",
                    textAlign = "center",
                    verticalAlign = "middle",
                } },
            },
        },
    }

    refs.clearReward = UI.Label {
        text = "",
        fontSize = Theme.font("caption", 24),
        fontColor = c("ink_dim"),
        textAlign = "center",
    }

    -- 释义卡（T18）：结算页直接看本关成语的释义与出处
    local cardH = Config.num("ui.clear_card_area_height", 300)
    refs.clearCards = UI.ScrollView {
        width = "100%",
        height = cardH,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = true,
        marginTop = 20,
        children = {},
    }

    refs.clearCard = UI.Panel {
        width = "84%",
        borderRadius = 36,
        backgroundGradient = { direction = "to-bottom", from = c("panel"), to = c("bank_block") },
        borderWidth = 4,
        borderColor = c("panel_edge"),
        boxShadow = shadow(34, 14, 180),
        flexDirection = "column",
        alignItems = "center",
        paddingVertical = 46,
        paddingHorizontal = 34,
        children = {
            emblem,
            UI.Label {
                text = "恭喜过关",
                fontSize = Theme.font("title", 56),
                fontColor = c("ink"),
                fontWeight = "bold",
                textAlign = "center",
                marginTop = 26,
            },
            refs.clearReward,
            refs.clearCards,
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                marginTop = 34,
                children = {
                    pillButton("下一关", function()
                        Play.hideClear()
                        Play.onNextLevel()
                    end, {
                        gradient = { direction = "to-bottom", from = c("gold"), to = c("gold_deep") },
                        glow = "gold_dark",
                    }),
                    pillButton("看看棋盘", function() Play.hideClear() end, {
                        gradient = { direction = "to-bottom", from = c("panel_edge"), to = c("ink_dim") },
                        fg = c("cream"),
                        glow = nil,
                    }),
                },
            },
        },
    }

    refs.clear = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = c("overlay"),
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        children = { refs.clearCard },
    }
    return refs.clear
end

function Play.hideClear()
    if refs.clear then refs.clear:SetVisible(false) end
end

--- 把本关成语填进结算页的释义卡区（T18）
local function fillClearCards(cards)
    local box = refs.clearCards
    if not box or not box.ClearChildren then return end
    box:ClearChildren()
    if not cards or #cards == 0 then return end
    for _, card in ipairs(cards) do
        local lines = { card.word }
        if card.pinyin and card.pinyin ~= "" then
            lines[#lines + 1] = card.pinyin
        end
        lines[#lines + 1] = W.wrapLines("释义：" .. (card.meaning ~= "" and card.meaning or "暂无"), 20)
        if card.source and card.source ~= "" then
            lines[#lines + 1] = W.wrapLines("出处：" .. card.source, 20)
        end
        local kids = {}
        for i, line in ipairs(lines) do
            kids[#kids + 1] = UI.Label {
                text = line,
                fontSize = (i == 1) and Theme.font("toolbar", 28) or Theme.font("caption", 24),
                fontColor = (i == 1) and c("ink") or c("ink_dim"),
                fontWeight = (i == 1) and "bold" or nil,
                width = "100%",
            }
        end
        box:AddChild(UI.Panel {
            width = "100%",
            borderRadius = 18,
            backgroundColor = withAlpha(c("bank_block"), 235),
            borderWidth = 2,
            borderColor = c("panel_edge"),
            paddingHorizontal = 18,
            paddingVertical = 12,
            marginBottom = 10,
            children = kids,
        })
    end
end

local function showClearOverlay(text)
    if not refs.clear then return end
    if refs.clearReward then refs.clearReward:SetStyle({ text = text }) end
    fillClearCards(Game.sessionCards())
    refs.clear:SetVisible(true)
    anim(refs.clearCard, {
        keyframes = {
            [0]    = { opacity = 0, scale = 0.55, translateY = 60 },
            [0.55] = { opacity = 1, scale = 1.08, translateY = -10 },
            [0.8]  = { opacity = 1, scale = 0.97, translateY = 4 },
            [1]    = { opacity = 1, scale = 1, translateY = 0 },
        },
        duration = Config.num("ui.fx.clear_pop_duration", 0.5),
        easing = "easeOut",
    })
    -- 印章弹一下 + 星星 + 金币雨
    FX.levelClear(refs.fxLayer)
end

------------------------------------------------------------------------------
-- 体力门
------------------------------------------------------------------------------

local function buildGate()
    local fontSize = Theme.font("toolbar", 28)
    local capSize = Theme.font("caption", 24)

    local function gateButton(text, onTap, primary)
        return UI.Button {
            text = text,
            fontSize = fontSize,
            width = "78%",
            marginVertical = 10,
            paddingVertical = 16,
            borderRadius = 30,
            backgroundGradient = primary
                and { direction = "to-bottom", from = c("jade"), to = c("jade_deep") }
                or { direction = "to-bottom", from = c("panel"), to = c("panel_edge") },
            textColor = primary and c("cream") or c("ink"),
            fontWeight = "bold",
            boxShadow = shadow(14, 5, 110, "jade_deep"),
            onClick = onTap,
        }
    end

    refs.gateInfo = UI.Label {
        text = "", fontSize = capSize,
        fontColor = c("cream_dim"),
        textAlign = "center",
    }

    return UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = c("overlay"),
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        children = {
            UI.Label {
                text = "体力不足",
                fontSize = Theme.font("title", 56),
                fontColor = c("cream"),
                fontWeight = "bold",
                textAlign = "center",
            },
            refs.gateInfo,
            gateButton("看广告恢复 +" .. tostring(Config.num("stamina.ad_reward", 10)) .. " 体力",
                function() Play.onGateAd() end, true),
            gateButton("稍后再来", function() Play.onGateWait() end, false),
        },
    }
end

------------------------------------------------------------------------------
-- 刷新
------------------------------------------------------------------------------

function Play.refresh()
    local s = refs.session
    if s then
        local grid = s.grid
        local rows, cols = grid:size()
        local selected = s.selectedCell

        for r = 0, rows - 1 do
            for cc = 0, cols - 1 do
                local ref = refs.cells[r] and refs.cells[r][cc]
                if ref then
                    local isReal = grid:getCell(r, cc) ~= nil
                    local isSel = selected ~= nil and selected.r == r and selected.c == cc
                    local bg, border, fg = cellStyle(grid, r, cc, isSel, false)
                    local style = {
                        backgroundColor = bg,
                        borderColor = border,
                    }
                    -- 非格子位置永不加投影（建造时就没有，这里也不补）
                    if isReal then
                        style.boxShadow = isSel and shadow(18, 4, 150, "gold") or pieceShadow()
                    end
                    ref.label:SetStyle({ text = cellText(grid, r, cc), fontColor = fg })
                    ref.panel:SetStyle(style)
                end
            end
        end

        for i, item in ipairs(s.bank) do
            local ref = refs.bank[i]
            if ref then
                local isSel = (s.selectedBankIdx == i)
                ref.panel:SetStyle({
                    backgroundColor = isSel and c("bank_block_selected")
                        or (item.used and c("bank_block_used") or c("bank_block")),
                    borderColor = isSel and c("gold_dark") or c("panel_edge"),
                    opacity = item.used and 0.4 or 1.0,
                    boxShadow = isSel and shadow(18, 5, 150, "gold") or pieceShadow(),
                })
            end
        end

        if refs.progressFill and grid.totalBlanks > 0 then
            refs.progressFill:SetStyle({
                width = pct(math.min(1, grid.filledCount / grid.totalBlanks)),
            })
        end
        if refs.hintBtn then
            local left = Config.num("hints.max_per_level", 3) - s.hintsUsed
            refs.hintBtn:SetStyle({ text = string.format("提示 %d", math.max(0, left)) })
        end
    end

    -- 顶栏经济数值（实时读 Game）
    if refs.topStamina and refs.topStamina.GetChildren then
        local kids = refs.topStamina:GetChildren()
        local lab = kids and kids[#kids]
        if lab and lab.SetStyle then
            lab:SetStyle({ text = string.format("体力 %d/%d", Game.stamina(), Config.num("stamina.max", 50)) })
        end
    end
    if refs.topGold and refs.topGold.GetChildren then
        local kids = refs.topGold:GetChildren()
        local lab = kids and kids[#kids]
        if lab and lab.SetStyle then
            lab:SetStyle({ text = "金币 " .. tostring(Game.gold()) })
        end
    end
end

--- 体力门文案与显隐
function Play.refreshGate()
    if not refs.gate then return end
    local intervalMin = math.max(1, math.floor(Config.num("stamina.recover_interval_sec", 360) / 60))
    local cost = Game.staminaCost()
    if refs.gateInfo then
        refs.gateInfo:SetStyle({
            text = string.format("当前体力 %d/%d，进关需要 %d 点\n每 %d 分钟自动恢复 1 点",
                Game.stamina(), Config.num("stamina.max", 50), cost, intervalMin),
        })
    end
    refs.gate:SetVisible(true)
    Play.refresh()
end

------------------------------------------------------------------------------
-- 交互（只调 Game/Session，不改状态）
------------------------------------------------------------------------------

function Play.onCellTapped(r, cc)
    local s = refs.session
    if not s then return end
    s:selectCell(r, cc)
    Play.refresh()
end

function Play.onBankTapped(idx)
    local s = refs.session
    if not s then return end
    s:selectBankIndex(idx)
    Play.refresh()
end

function Play.onHint()
    local s = refs.session
    if not s then return end
    local hint, err = s:useHint()
    if hint then
        showBanner("已提示一个字", "gold_dark")
    elseif err == "hint_limit" then
        alertModal("提示已用完", "本关的提示次数已用完，可以试用洗牌或撤销")
    end
    Play.refresh()
end

function Play.onUndo()
    local s = refs.session
    if not s then return end
    if s.state == "LevelCleared" then return end
    s:undo()
    Play.refresh()
end

function Play.onShuffle()
    local s = refs.session
    if not s then return end
    s:useShuffle()
    Play.mount(nil, { session = s, remountOnly = true })
    showBanner("已重新洗牌", "gold_dark")
end

--- 通关后进入下一关（优先恢复中断快照）
function Play.onNextLevel()
    local s, err = Game.nextLevel()
    if s then
        Play.mount(nil, { session = s })
    elseif err == "stamina_gate" then
        Play.refreshGate()
    end
end

--- 体力门：看广告（T21 走广告点位；中途关闭不发奖 = 免费出口）
function Play.onGateAd()
    local ok, AD = pcall(require, "ui.admodal")
    if not (ok and AD and AD.show) then
        -- 降级：广告模块不可用直接按原 mock 发放
        Game.claimAdStamina()
        Play.refreshGate()
        return
    end
    AD.show("stamina", {
        onGranted = function()
            alertModal("奖励已到账", "广告奖励已发放到你的账户")
            if Game.stamina() >= Game.staminaCost() then
                if refs.gate then refs.gate:SetVisible(false) end
                Play.onNextLevel()
            else
                Play.refreshGate()
            end
        end,
        onDenied = function(reason)
            alertModal("广告暂不可用", reason == "cooldown" and "广告冷却中，稍后再试" or "暂时无法观看广告，请稍后再试")
        end,
    })
end

--- 体力门：等待
function Play.onGateWait()
    if refs.gate then refs.gate:SetVisible(false) end
    Play.refresh()
end

------------------------------------------------------------------------------
-- 每日挑战：倒计时与交卷（T20）
------------------------------------------------------------------------------

local lastShownLeft_ = -1

--- 逐帧回调（由 ui/ticker 统一调度）：①防沉迷计时与强下线判定（T23）；②挑战倒计时
function Play.tick(dt)
    if dt and dt > 0 then Game.tickPlayTime(dt) end
    if Game.mode() ~= "challenge" then
        Play.checkCompliance()
        return
    end
    local left = Game.challengeLeft()
    local sec = math.max(0, math.ceil(left))
    if sec ~= lastShownLeft_ then
        lastShownLeft_ = sec
        W.chipText(refs.challengeChip, string.format("剩余 %ds", sec))
    end
    if left <= 0 then
        Play.onFinishChallenge()
    end
end

--- 订阅逐帧回调（全项目只允许 ui/ticker 订阅一次 Update，见 ticker 顶部说明）
local function hookTick()
    Ticker.add(Play.tick)
end

local complianceShown_ = false

--- 防沉迷：不可继续游玩时弹出阻断层（T23）
function Play.checkCompliance()
    local ok, reason = Game.canPlay()
    if ok then
        if complianceShown_ and refs.compliance then
            refs.compliance:SetVisible(false)
            complianceShown_ = false
        end
        return
    end
    if reason == "realname_required" then return end   -- 由登录页处理
    if not refs.compliance then return end
    if refs.complianceNotice then
        refs.complianceNotice:SetStyle({ text = Game.compliance().reasonText })
    end
    if not complianceShown_ then
        refs.compliance:SetVisible(true)
        complianceShown_ = true
    end
end

--- 阻断层（全屏吸点击，无法绕过）
local function buildComplianceGate()
    refs.complianceNotice = UI.Label {
        text = "",
        fontSize = Theme.font("toolbar", 28),
        fontColor = c("text_light"),
        textAlign = "center",
        width = "86%",
        marginTop = 18,
    }
    refs.compliance = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = c("overlay"),
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        -- 空 onClick 用于吃掉点击，避免穿透到下面棋盘
        onClick = function() end,
        children = { UI.Panel {
            width = "86%",
            borderRadius = 32,
            backgroundColor = c("chip_bg"),
            borderWidth = 3,
            borderColor = c("chip_edge"),
            boxShadow = shadow(30, 12, 170),
            paddingHorizontal = 30,
            paddingVertical = 36,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "健康游戏提示",
                    fontSize = Theme.font("title", 56),
                    fontColor = c("ink"),
                    fontWeight = "bold",
                    textAlign = "center",
                },
                refs.complianceNotice,
                UI.Label {
                    text = Config.get("compliance.health_notice", ""),
                    fontSize = Theme.font("caption", 24),
                    fontColor = c("text_light_dim"),
                    textAlign = "center",
                    width = "100%",
                    marginTop = 24,
                },
            },
        } },
    }
    return refs.compliance
end

--- 展示挑战结果（res 来自 Challenge.finish，已在结算时发放奖励）
local function showChallengeResult(res)
    if not res then return end
    local text = string.format("挑战结束：%d/%d 词，金币 +%d", res.idioms or 0, res.target or 0, res.gold or 0)
    if res.allDone then text = text .. "（全部达成）" end
    if refs.nextBtn then refs.nextBtn:SetVisible(false) end
    if refs.challengeChip then refs.challengeChip:SetVisible(false) end
    showClearOverlay(text)
end

--- 主动交卷 / 超时自动交卷
function Play.onFinishChallenge()
    if Game.mode() ~= "challenge" then return end
    local res = Game.finishChallenge()
    if res then
        lastShownLeft_ = -1
        showChallengeResult(res)
    end
end

------------------------------------------------------------------------------
-- 事件 → 反馈通道（DEV §10.3 / PRD §3.3.3）
------------------------------------------------------------------------------

local function hookSessionEvents(s)
    s:on("on_cell_filled", function(p)
        SFX.play("fill_ok")
        if p and p.r then popCell(p.r, p.c) end
        Play.refresh()
    end)
    s:on("on_idiom_completed", function(p)
        SFX.play("idiom_done")
        Play.refresh()
        local h = UI.GetHeight() or Config.num("ui.design_height", 1920)
        FX.starBurst(refs.fxLayer, {
            count = Config.num("ui.fx.spark_count", 10),
            radius = Config.num("ui.fx.spark_radius", 130),
            duration = Config.num("ui.fx.spark_duration", 0.6),
            y = h * 0.34,
            color = c("jade"),
        })
        FX.floatText(refs.fxLayer, {
            text = "成语达成 " .. tostring(p.answer),
            y = h * 0.30,
            color = c("jade"),
        })
        showBanner("成语达成：" .. tostring(p.answer), "jade_deep")
    end)
    s:on("on_cross_validated", function() SFX.play("cross_ok") end)
    s:on("on_undo", function() SFX.play("fill_ok", 0.35); Play.refresh() end)
    s:on("on_shuffle", function() Play.refresh() end)
    s:on("on_invalid", function(p)
        SFX.play("fill_err")
        if p and p.r then shakeCell(p.r, p.c) end
        showBanner("这个字不对，再想想", "seal")
        Play.refresh()
    end)
    s:on("on_level_cleared", function(p)
        SFX.play("level_win")
        Play.refresh()
        -- 挑战模式：Session 的 settle 已走完 Challenge.finish，这里只展示结果，
        -- 绝不重复结算（会二次发奖）
        if Game.mode() == "challenge" then
            showChallengeResult(p.reward)
            return
        end
        local gold = (p.reward and p.reward.gold) or 0
        local streak = (p.reward and p.reward.streak) or 0
        local mult = (p.reward and p.reward.streakMultiplier) or 1
        local text = "金币 +" .. tostring(gold)
        if mult > 1 then
            text = text .. string.format("  连对 %d 关 ×%d", streak, mult)
        end
        if refs.nextBtn then refs.nextBtn:SetVisible(true) end
        showClearOverlay(text)
    end)
end

------------------------------------------------------------------------------
-- 挂载
------------------------------------------------------------------------------

--- 挂载 play 页。opts: { session = 复用会话（洗牌重挂/进下一关）, remountOnly }
--- 不传 session 时：恢复中断快照或进入当前进度关；体力不足弹体力门。
function Play.mount(_, opts)
    opts = opts or {}
    local s = opts.session
    local gated = false
    if not s then
        local sNew, err = Game.nextLevel()
        s = sNew
        if not s then
            gated = (err == "stamina_gate")
            print("[play] 进关失败: " .. tostring(err))
        end
    end

    refs.session = s
    refs.cells = {}
    refs.bank = {}

    if s and Config.get("glyph.warmup_on_level_start", true) then
        -- P2：进关预热本关字形，避免首次出现时的抖动
        local ok, reason, n = Warm.warmupLevel(s.grid, s.bank, Theme.fontRaw("hanzi", 40))
        print(string.format("[play] 字形预热 %s（%d 字）%s",
            ok and "成功" or "跳过", n or 0, ok and "" or ("原因: " .. tostring(reason))))
    end

    refs.fxLayer = FX.newLayer()
    local clearPanel = buildClearOverlay()
    local gatePanel = buildGate()
    refs.gate = gatePanel

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = c("bg_top"),
        backgroundImage = "Textures/bg_main.png",
        backgroundFit = "cover",
        -- S27：顶部安全区（系统状态栏 + TapTap 宿主胶囊）用 root 的 paddingTop 实现。
        -- 不额外插入占位 child：那会让 children 总高超过 100%，Yoga 压缩分区后
        -- 在矮视口产生 Layout Warning（实测 4 条）。padding 不新增兄弟节点，背景仍铺满全屏。
        paddingTop = Theme.safeTop(),
        children = {
            buildTopBar(s),
            buildProgressBar(),
            buildBoard(s),
            buildBank(s),
            buildToolBar(s),
            buildBanner(),
            -- 底部广告预留区（S8）：占位留空，后续接 Banner 广告直接挂这里
            UI.Panel {
                width = "100%",
                height = pct(Theme.ratio("ad_reserve", 0.09)),
                flexShrink = 1,
            },
            clearPanel,
            gatePanel,
            buildComplianceGate(),
            refs.fxLayer,   -- 特效层置顶，保证星星/金币在最上层
        },
    }
    refs.root = root
    UI.SetRoot(root, true)

    if s then hookSessionEvents(s) end
    hookTick()
    Play.tick()
    Play.refresh()

    if gated then
        Play.refreshGate()
    end
    return s
end

function Play.session()
    return refs.session
end

return Play
