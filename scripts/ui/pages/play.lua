-- play 页：状态条 + 进度条 + 矩阵 + 备选区 + 道具栏 + 通关特效 + 体力门（DEV §10.2）。
-- 严格分层：本页只订阅 Session 事件渲染 + 调用 Game 逻辑层，不持有游戏状态。
-- T11 反馈通道：音效（system/audio）+ 关键帧动效（ui/fx）；触觉按裁决 #20 视为不可用。
-- 视觉：中国风「漆底 + 宣纸 + 描金」，所有配色/字号/动效参数读 config，禁止硬编码。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local SFX = require("system.audio")
local Warm = require("system.glyphwarm")
local FX = require("ui.fx")

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
}

------------------------------------------------------------------------------
-- 工具
------------------------------------------------------------------------------

local function pct(x)
    return string.format("%.4f%%", x * 100)
end

--- 数值/颜色/比例统一走 config
local function c(key, default)
    return Config.color("ui.color." .. key, default or { 0, 0, 0, 255 })
end

local function withAlpha(color, alpha)
    return { color[1], color[2], color[3], alpha }
end

--- 投影（卡片/棋子统一风格）
local function shadow(blur, y, alpha, colorKey)
    local col = colorKey and c(colorKey) or { 0, 0, 0, 255 }
    return { { x = 0, y = y or 6, blur = blur or 18, spread = 0,
               color = withAlpha(col, alpha or 90) } }
end

--- 棋子/字块基础质感：落影 + 顶部内高光
local function pieceShadow()
    return {
        { x = 0, y = 3, blur = 8, spread = 0, color = { 60, 40, 20, 60 } },
        { x = 0, y = 2, blur = 0, spread = 0, color = { 255, 255, 255, 60 }, inset = true },
    }
end

--- 跑一个关键帧动画（失败静默降级为静态呈现）
local function anim(widget, config)
    if not widget or not widget.Animate then return false end
    local ok = pcall(function() widget:Animate(config) end)
    return ok
end

------------------------------------------------------------------------------
-- 单元格样式
------------------------------------------------------------------------------

local function cellStyle(grid, r, cc, selected, flashWrong)
    local cell = grid:getCell(r, cc)
    if not cell then
        return c("cream"), c("panel_edge"), c("ink")
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

--- 正确填字：弹性放大 + 描金闪一下
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
-- 组件：胶囊 / 按钮
------------------------------------------------------------------------------

--- 顶栏信息胶囊（漆底 + 描金边）
local function chip(label, opts)
    opts = opts or {}
    local fontSize = opts.fontSize or Theme.font("topbar", 26) * 0.85
    local dot = nil
    if opts.dotColor then
        dot = UI.Panel {
            width = 18, height = 18,
            borderRadius = 9,
            backgroundColor = opts.dotColor,
            marginRight = 10,
        }
    end
    local text = UI.Label {
        text = label,
        fontSize = fontSize,
        fontColor = opts.fg or c("text_light"),
        fontWeight = opts.bold and "bold" or nil,
        flexShrink = 1,
    }
    local kids = {}
    if dot then kids[#kids + 1] = dot end
    kids[#kids + 1] = text
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 16,
        paddingVertical = 4,
        flexShrink = 1,
        borderRadius = 28,
        backgroundColor = opts.bg or c("chip_bg"),
        borderWidth = 2,
        borderColor = opts.border or c("chip_edge"),
        boxShadow = shadow(10, 3, 70, opts.glow),
        children = kids,
    }
end

--- 道具胶囊按钮（描金渐变 + 投影）
local function pillButton(text, onTap, opts)
    opts = opts or {}
    return UI.Button {
        text = text,
        fontSize = Theme.font("toolbar", 28),
        flexGrow = opts.grow or 1,
        marginHorizontal = 7,
        paddingVertical = 14,
        borderRadius = 30,
        backgroundColor = opts.bg or c("gold_deep"),
        backgroundGradient = opts.gradient or {
            direction = "to-bottom",
            from = c("gold"),
            to = c("gold_deep"),
        },
        textColor = opts.fg or c("ink"),
        fontWeight = "bold",
        boxShadow = {
            { x = 0, y = 6, blur = 16, spread = 0, color = withAlpha(c(opts.glow or "gold_dark"), 130) },
            { x = 0, y = 2, blur = 0, spread = 0, color = { 255, 248, 230, 90 }, inset = true },
        },
        borderWidth = 2,
        borderColor = c("gold_dark"),
        onClick = onTap,
    }
end

------------------------------------------------------------------------------
-- 构建：顶栏 / 进度条 / 棋盘 / 备选区 / 道具栏 / 横幅
------------------------------------------------------------------------------

local function buildTopBar(session)
    refs.levelChip = chip(session and ("第 " .. tostring(session.levelId) .. " 关") or "成语小秀才", {
        bg = c("gold_deep"), border = c("gold_dark"), fg = c("ink"), bold = true,
        glow = "gold",
    })
    refs.topStamina = chip("体力 --", { dotColor = c("jade") })
    refs.topGold = chip("金币 --", { dotColor = c("coin"), fg = c("gold") })

    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("topbar", 0.08)),
        flexShrink = 1,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = 24,
        children = {
            chip("成语小秀才", {
                bg = withAlpha(c("chip_bg"), 235),
                border = c("gold_dark"), fg = c("gold"), bold = true, glow = "gold_dark",
            }),
            refs.levelChip, refs.topStamina, refs.topGold,
        },
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
            marginHorizontal = 24,
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
    local fontSize = math.min(Theme.font("hanzi", 40), cellSize * 0.52)

    local rowPanels = {}
    for r = 0, rows - 1 do
        refs.cells[r] = {}
        local cellPanels = {}
        for cIdx = 0, cols - 1 do
            local bg, border, fg = cellStyle(grid, r, cIdx, false, false)
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
                boxShadow = pieceShadow(),
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

    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("board", 0.446)),
        flexShrink = 1,
        marginHorizontal = 24,
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        paddingHorizontal = 16,
        paddingVertical = 14,
        backgroundColor = c("panel"),
        borderRadius = 26,
        borderWidth = 3,
        borderColor = c("panel_edge"),
        boxShadow = shadow(26, 10, 120),
        children = rowPanels,
    }
end

local function buildBank(session)
    local gap = Theme.num("cell_gap", 8)
    local block = Theme.num("bank_block_min", 88)
    local fontSize = Theme.font("hanzi", 40)
    local vw = select(1, UI.GetViewportSize()) or 1080
    local usable = vw - 60
    local perRow = math.max(1, math.floor(usable / (block + gap)))

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
    refs.hintBtn = pillButton("提示", function() Play.onHint() end)
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
        paddingHorizontal = 24,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                children = {
                    refs.hintBtn,
                    pillButton("撤销", function() Play.onUndo() end),
                    pillButton("洗牌", function() Play.onShuffle() end),
                    refs.nextBtn,
                },
            },
        },
    }
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

local function showClearOverlay(text)
    if not refs.clear then return end
    if refs.clearReward then refs.clearReward:SetStyle({ text = text }) end
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
                and { direction = "to-bottom", from = c("gold"), to = c("gold_deep") }
                or { direction = "to-bottom", from = c("chip_bg"), to = c("ink") },
            textColor = primary and c("ink") or c("text_light"),
            fontWeight = "bold",
            boxShadow = shadow(14, 5, 110, "gold_dark"),
            onClick = onTap,
        }
    end

    refs.gateInfo = UI.Label {
        text = "", fontSize = capSize,
        fontColor = c("text_light_dim"),
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
                fontColor = c("text_light"),
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
                    local isSel = selected ~= nil and selected.r == r and selected.c == cc
                    local bg, border, fg = cellStyle(grid, r, cc, isSel, false)
                    ref.label:SetStyle({ text = cellText(grid, r, cc), fontColor = fg })
                    ref.panel:SetStyle({
                        backgroundColor = bg,
                        borderColor = border,
                        boxShadow = isSel and shadow(18, 4, 150, "gold") or pieceShadow(),
                    })
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
        showBanner("已提示一个字", "gold")
    elseif err == "hint_limit" then
        showBanner("本关提示已用完", "seal")
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
    showBanner("已重新洗牌", "gold")
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

--- 体力门：看广告（S1 mock，S3 接真实广告位）
function Play.onGateAd()
    local before = Game.stamina()
    Game.claimAdStamina()
    local after = Game.stamina()
    showBanner(string.format("广告奖励：体力 +%d", after - before), "jade")
    if after >= Game.staminaCost() then
        if refs.gate then refs.gate:SetVisible(false) end
        Play.onNextLevel()
    else
        Play.refreshGate()
    end
end

--- 体力门：等待
function Play.onGateWait()
    if refs.gate then refs.gate:SetVisible(false) end
    Play.refresh()
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
        showBanner("成语达成：" .. tostring(p.answer), "jade")
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
        local ok, reason, n = Warm.warmupLevel(s.grid, s.bank, Theme.font("hanzi", 40))
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
        children = {
            buildTopBar(s),
            buildProgressBar(),
            buildBoard(s),
            buildBank(s),
            buildToolBar(s),
            buildBanner(),
            clearPanel,
            gatePanel,
            refs.fxLayer,   -- 特效层置顶，保证星星/金币在最上层
        },
    }
    refs.root = root
    UI.SetRoot(root, true)

    if s then hookSessionEvents(s) end
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
