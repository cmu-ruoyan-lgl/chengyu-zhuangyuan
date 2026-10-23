-- play 页：状态条 + 矩阵 + 备选区 + 道具栏 + 体力门（DEV §10.2）。
-- 严格分层：本页只订阅 Session 事件渲染 + 调用 Game 逻辑层，不持有游戏状态。
-- T11 反馈通道：音效（system/audio）+ 视觉关键帧动画；触觉按裁决 #20 视为不可用。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local SFX = require("system.audio")
local Warm = require("system.glyphwarm")

local Play = {}

local refs = {
    root = nil,
    session = nil,
    cells = {},      -- [r][c] = { panel, label }
    bank = {},       -- [i] = { panel, label }
    topLevel = nil,
    topProgress = nil,
    topStamina = nil,
    topGold = nil,
    banner = nil,
    nextBtn = nil,
    gate = nil,
    gateInfo = nil,
    hintLabel = nil,
}

------------------------------------------------------------------------------
-- 工具
------------------------------------------------------------------------------

local function pct(x)
    return string.format("%.4f%%", x * 100)
end

local function cellFillStyle(grid, r, c, selected)
    local cell = grid:getCell(r, c)
    if not cell then return Theme.color("board_bg") end
    if selected then return Theme.color("cell_selected") end
    if cell.isPreset then return Theme.color("cell_fixed") end
    if cell.value ~= nil then
        local allDone = true
        for _, id in ipairs(cell.owners) do
            if not grid.idioms[id].done then allDone = false; break end
        end
        return allDone and Theme.color("cell_done") or Theme.color("cell_filled")
    end
    return Theme.color("cell_empty")
end

local function cellText(grid, r, c)
    local cell = grid:getCell(r, c)
    if not cell or cell.answer == nil then return "" end
    return cell.value or ""
end

--- 错填抖动（裁决 #20：触觉不可用 → 视觉抖动增强）
local function shakeCell(r, c)
    local ref = refs.cells[r] and refs.cells[r][c]
    if not ref or not ref.panel.Animate then return end
    local ok = pcall(function()
        ref.panel:Animate({
            keyframes = {
                [0]   = { translateX = 0 },
                [0.2] = { translateX = -7 },
                [0.4] = { translateX = 7 },
                [0.6] = { translateX = -4 },
                [0.8] = { translateX = 4 },
                [1]   = { translateX = 0 },
            },
            duration = 0.15,
            easing = "linear",
        })
    end)
    if not ok then print("[play] 抖动动画不可用（已降级为仅颜色反馈）") end
end

--- 正确填字的呼吸强调
local function popCell(r, c)
    local ref = refs.cells[r] and refs.cells[r][c]
    if not ref or not ref.panel.Animate then return end
    pcall(function()
        ref.panel:Animate({
            keyframes = {
                [0] = { opacity = 0.35 },
                [1] = { opacity = 1 },
            },
            duration = 0.12,
            easing = "easeOut",
        })
    end)
end

------------------------------------------------------------------------------
-- 构建
------------------------------------------------------------------------------

local function buildTopBar(session)
    local fontSize = Theme.font("topbar", 26)
    local textColor = Theme.color("text_main")
    refs.topLevel = UI.Label {
        text = session and ("第 " .. tostring(session.levelId) .. " 关") or "成语小秀才",
        fontSize = fontSize, fontColor = textColor,
    }
    refs.topProgress = UI.Label {
        text = "", fontSize = fontSize, fontColor = Theme.color("text_dim"),
    }
    refs.topStamina = UI.Label {
        text = "体力 --", fontSize = fontSize, fontColor = textColor,
    }
    refs.topGold = UI.Label {
        text = "金币 --", fontSize = fontSize, fontColor = Theme.color("accent"),
    }
    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("topbar", 0.08)),
        flexShrink = 1,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = 24,
        children = { refs.topLevel, refs.topProgress, refs.topStamina, refs.topGold },
    }
end

local function buildBoard(session)
    local radius = Theme.num("cell_radius", 12)
    if not session then
        -- 无会话（体力不足进不了关）：占位提示
        return UI.Panel {
            width = "100%",
            height = pct(Theme.ratio("board", 0.46)),
            flexShrink = 1,
            backgroundColor = Theme.color("board_bg"),
            borderRadius = radius,
            justifyContent = "center",
            alignItems = "center",
            children = { UI.Label {
                text = "体力恢复后即可闯关",
                fontSize = Theme.font("caption", 24),
                fontColor = Theme.color("text_dim"),
            } },
        }
    end

    local grid = session.grid
    local rows, cols = grid:size()
    local gap = Theme.num("cell_gap", 8)
    local fontSize = Theme.font("hanzi", 40)

    local rowPanels = {}
    for r = 0, rows - 1 do
        refs.cells[r] = {}
        local cellPanels = {}
        for c = 0, cols - 1 do
            -- 注意：Label 不要写 width/height="100%"。
            -- 百分比高度会相对「父容器的可用高度」解析，导致格子被撑满整行高度，
            -- 棋盘必然溢出（实测 4 行 → 每行 316px）。居中交给父 Panel 的
            -- justifyContent/alignItems，格子本身用 aspectRatio 保证正方形。
            local label = UI.Label {
                text = cellText(grid, r, c),
                fontSize = fontSize,
                fontColor = Theme.color("text_main"),
                textAlign = "center",
                verticalAlign = "middle",
            }
            local panel = UI.Panel {
                height = "100%",
                aspectRatio = 1,
                flexShrink = 1,
                margin = gap / 2,
                backgroundColor = cellFillStyle(grid, r, c, false),
                borderWidth = 2,
                borderColor = Theme.color("cell_empty_border"),
                borderRadius = radius,
                justifyContent = "center",
                alignItems = "center",
                onClick = function()
                    Play.onCellTapped(r, c)
                end,
                children = { label },
            }
            refs.cells[r][c] = { panel = panel, label = label }
            cellPanels[#cellPanels + 1] = panel
        end
        rowPanels[#rowPanels + 1] = UI.Panel {
            width = "100%",
            flexGrow = 1,
            flexShrink = 1,
            flexDirection = "row",
            justifyContent = "center",
            alignItems = "center",
            children = cellPanels,
        }
    end

    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("board", 0.46)),
        flexShrink = 1,
        flexDirection = "column",
        paddingHorizontal = 20,
        paddingVertical = 10,
        backgroundColor = Theme.color("board_bg"),
        borderRadius = radius,
        children = rowPanels,
    }
end

local function buildBank(session)
    local gap = Theme.num("cell_gap", 8)
    local block = Theme.num("bank_block_min", 88)
    local fontSize = Theme.font("hanzi", 40)
    local vw = select(1, UI.GetViewportSize()) or 1080
    local usable = vw - 40
    local perRow = math.max(1, math.floor(usable / (block + gap)))

    local rows, rowChildren, current = {}, {}, nil
    refs.bank = {}
    if not session then
        return UI.Panel {
            width = "100%", height = pct(Theme.ratio("bank", 0.26)),
            flexShrink = 1,
        }
    end
    for i, item in ipairs(session.bank) do
        if not current or #current >= perRow then
            current = {}
            rowChildren[#rowChildren + 1] = current
        end
        local label = UI.Label {
            text = item.char,
            fontSize = fontSize,
            fontColor = Theme.color("text_main"),
            textAlign = "center",
            verticalAlign = "middle",
            width = "100%",
            height = "100%",
        }
        local idx = i
        local panel = UI.Panel {
            width = block,
            height = block,
            margin = gap / 2,
            backgroundColor = item.used and Theme.color("bank_block_used") or Theme.color("bank_block"),
            borderWidth = 2,
            borderColor = Theme.color("cell_empty_border"),
            borderRadius = Theme.num("cell_radius", 12),
            justifyContent = "center",
            alignItems = "center",
            onClick = function()
                Play.onBankTapped(idx)
            end,
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
        height = pct(Theme.ratio("bank", 0.26)),
        flexShrink = 1,
        flexDirection = "column",
        justifyContent = "center",
        children = rows,
    }
end

local function buildToolBar(session)
    local fontSize = Theme.font("toolbar", 28)
    local function toolButton(text, onTap)
        return UI.Button {
            text = text,
            fontSize = fontSize,
            flexGrow = 1,
            marginHorizontal = 8,
            backgroundColor = Theme.color("tool_button"),
            textColor = Theme.color("text_main"),
            onClick = onTap,
        }
    end
    refs.hintLabel = UI.Label {
        text = "提示 --",
        fontSize = fontSize,
        fontColor = Theme.color("text_dim"),
    }
    refs.nextBtn = UI.Button {
        text = "下一关 ▶",
        fontSize = fontSize,
        visible = false,
        marginHorizontal = 8,
        backgroundColor = Theme.color("accent"),
        textColor = Theme.color("cell_empty"),
        onClick = function() Play.onNextLevel() end,
    }
    if not session then
        return UI.Panel {
            width = "100%",
            height = pct(Theme.ratio("toolbar", 0.14)),
            flexShrink = 1,
            justifyContent = "center",
            children = { refs.hintLabel, refs.nextBtn },
        }
    end
    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("toolbar", 0.14)),
        flexShrink = 1,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 20,
        children = {
            toolButton("提示", function() Play.onHint() end),
            toolButton("撤销", function() Play.onUndo() end),
            toolButton("洗牌", function() Play.onShuffle() end),
            refs.hintLabel,
            refs.nextBtn,
        },
    }
end

------------------------------------------------------------------------------
-- 体力门（DEV §10.1 stamina_gate；S1 广告为 mock，S3 接真实广告）
------------------------------------------------------------------------------

local function buildGate()
    local fontSize = Theme.font("toolbar", 28)
    local capSize = Theme.font("caption", 24)

    local function gateButton(text, onTap)
        return UI.Button {
            text = text,
            fontSize = fontSize,
            width = "80%",
            marginVertical = 10,
            backgroundColor = Theme.color("tool_button"),
            textColor = Theme.color("text_main"),
            onClick = onTap,
        }
    end

    refs.gateInfo = UI.Label {
        text = "", fontSize = capSize,
        fontColor = Theme.color("text_dim"),
        textAlign = "center",
    }

    local panel = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = Theme.color("board_bg"),
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        children = {
            UI.Label {
                text = "体力不足",
                fontSize = Theme.font("hanzi", 40),
                fontColor = Theme.color("text_main"),
                textAlign = "center",
            },
            refs.gateInfo,
            gateButton("看广告恢复 +" .. tostring(Config.num("stamina.ad_reward", 10)) .. " 体力",
                function() Play.onGateAd() end),
            gateButton("稍后再来", function() Play.onGateWait() end),
        },
    }
    return panel
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
            for c = 0, cols - 1 do
                local ref = refs.cells[r] and refs.cells[r][c]
                if ref then
                    local isSel = selected ~= nil and selected.r == r and selected.c == c
                    ref.label:SetStyle({ text = cellText(grid, r, c) })
                    ref.panel:SetStyle({ backgroundColor = cellFillStyle(grid, r, c, isSel) })
                end
            end
        end

        for i, item in ipairs(s.bank) do
            local ref = refs.bank[i]
            if ref then
                local isSel = (s.selectedBankIdx == i)
                ref.panel:SetStyle({
                    backgroundColor = isSel and Theme.color("bank_block_selected")
                        or (item.used and Theme.color("bank_block_used") or Theme.color("bank_block")),
                    opacity = item.used and 0.45 or 1.0,
                })
            end
        end

        if refs.topProgress then
            refs.topProgress:SetStyle({
                text = string.format("%d/%d", grid.filledCount, grid.totalBlanks),
            })
        end
        if refs.hintLabel then
            local left = Config.num("hints.max_per_level", 3) - s.hintsUsed
            refs.hintLabel:SetStyle({ text = "提示 " .. tostring(math.max(0, left)) })
        end
    end

    -- 顶栏经济数值（实时读 Game）
    if refs.topStamina then
        refs.topStamina:SetStyle({
            text = string.format("体力 %d/%d", Game.stamina(), Config.num("stamina.max", 50)),
        })
    end
    if refs.topGold then
        refs.topGold:SetStyle({ text = "金币 " .. tostring(Game.gold()) })
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

function Play.onCellTapped(r, c)
    local s = refs.session
    if not s then return end
    s:selectCell(r, c)
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
    if not hint and err == "hint_limit" and refs.banner then
        refs.banner:SetStyle({ text = "本关提示已用完" })
    end
    Play.refresh()
end

function Play.onUndo()
    local s = refs.session
    if not s then return end
    if s.state == "LevelCleared" then return end -- 已结算，不允许撤销回退
    s:undo()
    Play.refresh()
end

function Play.onShuffle()
    local s = refs.session
    if not s then return end
    s:useShuffle()
    -- 洗牌换了顺序，备选区需要重建
    Play.mount(nil, { session = s, remountOnly = true })
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
    if refs.banner then
        refs.banner:SetStyle({ text = string.format("广告奖励：体力 +%d", after - before) })
    end
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
        if refs.banner then
            refs.banner:SetStyle({ text = "成语达成：" .. tostring(p.answer) })
        end
    end)
    s:on("on_cross_validated", function()
        SFX.play("cross_ok")
    end)
    s:on("on_undo", function() SFX.play("fill_ok", 0.35); Play.refresh() end)
    s:on("on_shuffle", function() Play.refresh() end)
    s:on("on_invalid", function(p)
        SFX.play("fill_err")
        if p and p.r then shakeCell(p.r, p.c) end
        if refs.banner then refs.banner:SetStyle({ text = "这个字不对，再想想" }) end
        Play.refresh()
    end)
    s:on("on_level_cleared", function(p)
        SFX.play("level_win")
        Play.refresh()
        local gold = (p.reward and p.reward.gold) or 0
        local streak = (p.reward and p.reward.streak) or 0
        local mult = (p.reward and p.reward.streakMultiplier) or 1
        if refs.banner then
            local text = "通关！金币 +" .. tostring(gold)
            if mult > 1 then
                text = text .. string.format("（连对 %d 关 ×%d）", streak, mult)
            end
            refs.banner:SetStyle({ text = text })
        end
        if refs.nextBtn then refs.nextBtn:SetVisible(true) end
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

    refs.banner = UI.Label {
        text = "", fontSize = Theme.font("caption", 24),
        fontColor = Theme.color("accent"), textAlign = "center",
        height = pct(Theme.ratio("banner", 0.06)),
        width = "100%",
        flexShrink = 1,
    }
    -- 「下一关」按钮在 buildToolBar 中创建并挂载（与提示/撤销/洗牌同排，
    -- 14% 的行高放得下按钮的固有高度；banner 行只有 6%，塞按钮会溢出）

    local gatePanel = buildGate()
    refs.gate = gatePanel

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = Theme.color("bg"),
        children = {
            buildTopBar(s),
            buildBoard(s),
            buildBank(s),
            buildToolBar(s),
            refs.banner,
            gatePanel,
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
