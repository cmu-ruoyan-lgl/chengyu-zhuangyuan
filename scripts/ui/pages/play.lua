-- play 页：状态条 + 矩阵 + 备选区 + 道具栏（DEV §10.2）。
-- 严格分层：本页只订阅 Session 事件渲染，不持有游戏状态。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Session = require("core.session")
local Warm = require("system.glyphwarm")

local Play = {}

local refs = {
    root = nil,
    session = nil,
    cells = {},      -- [r][c] = { panel, label }
    bank = {},       -- [i] = { panel, label }
    topLevel = nil,
    topProgress = nil,
    banner = nil,
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

------------------------------------------------------------------------------
-- 构建
------------------------------------------------------------------------------

local function buildTopBar(session)
    local fontSize = Theme.font("topbar", 26)
    local textColor = Theme.color("text_main")
    refs.topLevel = UI.Label {
        text = "第 " .. tostring(session.levelId) .. " 关",
        fontSize = fontSize, fontColor = textColor,
    }
    refs.topProgress = UI.Label {
        text = "", fontSize = fontSize, fontColor = Theme.color("text_dim"),
    }
    local stamina = UI.Label {
        text = "体力 " .. tostring(Config.num("stamina.max", 50)),
        fontSize = fontSize, fontColor = textColor,
    }
    return UI.Panel {
        width = "100%",
        height = pct(Theme.ratio("topbar", 0.08)),
        flexShrink = 1,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = 24,
        children = { refs.topLevel, refs.topProgress, stamina },
    }
end

local function buildBoard(session)
    local grid = session.grid
    local rows, cols = grid:size()
    local gap = Theme.num("cell_gap", 8)
    local radius = Theme.num("cell_radius", 12)
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
        text = "提示 " .. tostring(Config.num("hints.max_per_level", 3)),
        fontSize = fontSize,
        fontColor = Theme.color("text_dim"),
    }
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
        },
    }
end

------------------------------------------------------------------------------
-- 刷新
------------------------------------------------------------------------------

function Play.refresh()
    local s = refs.session
    if not s then return end
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

------------------------------------------------------------------------------
-- 交互（只调 Session，不改状态）
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
    s:useHint()
    Play.refresh()
end

function Play.onUndo()
    local s = refs.session
    if not s then return end
    s:undo()
    Play.refresh()
end

function Play.onShuffle()
    local s = refs.session
    if not s then return end
    s:useShuffle()
    -- 洗牌换了顺序，备选区需要重建
    Play.mount(s.levelId, { session = s, reshuffleOnly = true })
end

------------------------------------------------------------------------------
-- 挂载
------------------------------------------------------------------------------

--- 挂载 play 页。opts: { levelId, session }
function Play.mount(levelId, opts)
    opts = opts or {}
    local s = opts.session
    if not s then
        local err
        s, err = Session.start(levelId)
        if not s then
            print("[play] 关卡加载失败: " .. tostring(err))
            return nil, err
        end
    end

    refs.session = s
    refs.cells = {}
    refs.bank = {}

    -- P2：进关预热本关字形，避免首次出现时的抖动
    if Config.get("glyph.warmup_on_level_start", true) then
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
        },
    }
    refs.root = root
    UI.SetRoot(root, true)

    s:on("on_cell_filled", function() Play.refresh() end)
    s:on("on_idiom_completed", function(p)
        Play.refresh()
        if refs.banner then
            refs.banner:SetStyle({ text = "成语达成：" .. tostring(p.answer) })
        end
    end)
    s:on("on_undo", function() Play.refresh() end)
    s:on("on_shuffle", function() Play.refresh() end)
    s:on("on_invalid", function()
        if refs.banner then refs.banner:SetStyle({ text = "这个字不对" }) end
        Play.refresh()
    end)
    s:on("on_level_cleared", function(p)
        Play.refresh()
        if refs.banner then
            local gold = (p.reward and p.reward.gold) or 0
            refs.banner:SetStyle({ text = "通关！金币 +" .. tostring(gold) })
        end
    end)

    Play.refresh()
    return s
end

function Play.session()
    return refs.session
end

return Play
