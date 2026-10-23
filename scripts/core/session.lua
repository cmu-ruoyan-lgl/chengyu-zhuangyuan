-- 关卡状态机：单关会话。
-- 逻辑层只发事件（on_cell_filled / on_idiom_completed / on_level_cleared ...），
-- 绝不直接调用 UI；UI 与音频、埋点通过 Session:on() 订阅。

local json = require("core.json")
local fs = require("core.fs")
local util = require("core.util")
local Config = require("core.config")
local Grid = require("core.grid")
local Validator = require("core.validator")
local Solver = require("core.solver")

local Session = {}
Session.__index = Session

--- 关卡文件路径：data/levels/0001.json
local function levelPath(levelId)
    return string.format("data/levels/%04d.json", tonumber(levelId) or 0)
end

--- 读取关卡（引擎内走资源目录，离线走 io）
function Session.loadLevel(levelId)
    local path = levelPath(levelId)
    local text, err = fs.readText(path)
    if not text then
        return nil, "读取关卡失败 " .. path .. ": " .. tostring(err)
    end
    local ok, data = pcall(json.decode, text)
    if not ok or type(data) ~= "table" then
        return nil, "解析关卡失败 " .. path .. ": " .. tostring(data)
    end
    return data
end

------------------------------------------------------------------------------
-- 生命周期
------------------------------------------------------------------------------

--- ctx: { levelData, stamina, items, analytics, settle(levelId, stats) }
function Session.start(levelId, ctx)
    ctx = ctx or {}
    local levelData = ctx.levelData
    if not levelData then
        local data, err = Session.loadLevel(levelId)
        if not data then return nil, err end
        levelData = data
    end

    local self = setmetatable({}, Session)
    self.levelId = levelId or levelData.level_id
    self.levelData = levelData
    self.ctx = ctx
    self.grid = Grid.new(levelData)

    -- 备选字块：{ char, used }
    self.bank = {}
    for _, ch in ipairs(levelData.bank or {}) do
        self.bank[#self.bank + 1] = { char = ch, used = false }
    end

    self.selectedCell = nil
    self.selectedBankIdx = nil
    self.history = {}          -- 撤销栈：{ r, c, char, bankIdx }
    self.wrongCount = 0
    self.hintsUsed = 0
    self.shuffleUsed = 0
    self.skipped = false
    self.state = "Idle"
    self.listeners = {}
    self.stats = { startedAt = os.clock(), durationMs = 0 }

    self.grid:refreshDoneFlags()
    return self
end

------------------------------------------------------------------------------
-- 事件
------------------------------------------------------------------------------

function Session:on(event, fn)
    self.listeners[event] = self.listeners[event] or {}
    self.listeners[event][#self.listeners[event] + 1] = fn
    return self
end

function Session:emit(event, payload)
    local fns = self.listeners[event]
    if not fns then return end
    for i = 1, #fns do
        local ok, err = pcall(fns[i], payload, self)
        if not ok then
            print(string.format("[session] 事件 %s 回调出错: %s", event, tostring(err)))
        end
    end
end

------------------------------------------------------------------------------
-- 交互
------------------------------------------------------------------------------

function Session:selectCell(r, c)
    local cell = self.grid:getCell(r, c)
    if not cell or cell.answer == nil then
        return false, "not_playable"
    end
    if cell.value ~= nil then
        -- 已填/预填格不可再选
        self.selectedCell = nil
        return false, "already_filled"
    end
    self.selectedCell = { r = r, c = c }
    self.state = "CellSelected"
    if self.selectedBankIdx then
        local idx = self.selectedBankIdx
        self.selectedBankIdx = nil
        return self:fillByBankIndex(idx)
    end
    return true
end

function Session:selectBankIndex(idx)
    local item = self.bank[idx]
    if not item or item.used then
        return false, "unavailable"
    end
    self.selectedBankIdx = idx
    if self.selectedCell then
        local cell = self.selectedCell
        self.selectedBankIdx = nil
        return self:fill(cell.r, cell.c, item.char, idx)
    end
    return true
end

function Session:clearSelection()
    self.selectedCell = nil
    self.selectedBankIdx = nil
    self.state = "Idle"
end

--- 核心：往选中格写字
function Session:fill(r, c, char, bankIdx)
    local cell = self.grid:getCell(r, c)
    if not cell or cell.answer == nil then
        return { ok = false, reason = "not_playable" }
    end
    local ok = self.grid:setValue(r, c, char)
    if not ok then
        self.wrongCount = self.wrongCount + 1
        self.state = "Idle"
        self:emit("on_invalid", { r = r, c = c, char = char })
        return { ok = false, reason = "wrong_char" }
    end

    -- 消费字块
    local usedIdx = bankIdx
    if not usedIdx then
        for i, item in ipairs(self.bank) do
            if not item.used and item.char == char then
                usedIdx = i
                break
            end
        end
    end
    if usedIdx then self.bank[usedIdx].used = true end

    self.history[#self.history + 1] = { r = r, c = c, char = char, bankIdx = usedIdx }
    self.selectedCell = nil
    self.selectedBankIdx = nil
    self.state = "Filled"
    self:emit("on_cell_filled", { correct = true, r = r, c = c, char = char, bankIdx = usedIdx })

    local res = Validator.onCellFilled(self.grid, r, c)
    for _, id in ipairs(res.completedIdiomIds) do
        self:emit("on_idiom_completed", { idiomId = id, answer = self.grid.idioms[id].answer })
    end
    for _, pos in ipairs(res.newlyValidCross) do
        self:emit("on_cross_validated", pos)
    end

    local cleared = Validator.checkLevel(self.grid)
    if cleared then
        self.state = "LevelCleared"
        self.stats.durationMs = (os.clock() - self.stats.startedAt) * 1000
        local reward = self:settle()
        self:emit("on_level_cleared", { reward = reward, stats = self:statsSnapshot() })
        return { ok = true, completedIdioms = res.completedIdioms, cleared = true, reward = reward }
    end
    return { ok = true, completedIdioms = res.completedIdioms, cleared = false }
end

function Session:fillByBankIndex(idx)
    local item = self.bank[idx]
    if not item then return { ok = false, reason = "no_bank_item" } end
    local cell = self.selectedCell
    if not cell then return { ok = false, reason = "no_cell" } end
    return self:fill(cell.r, cell.c, item.char, idx)
end

--- 撤销最近一次填写
function Session:undo()
    local last = self.history[#self.history]
    if not last then return false end
    table.remove(self.history, #self.history)
    self.grid:clearCell(last.r, last.c)
    if last.bankIdx then self.bank[last.bankIdx].used = false end
    self.state = "Idle"
    self:emit("on_undo", { r = last.r, c = last.c, char = last.char })
    return true
end

------------------------------------------------------------------------------
-- 道具
------------------------------------------------------------------------------

--- 提示：直接用 Solver 给出的最易推位置并填上
function Session:useHint()
    local maxPerLevel = Config.num("hints.max_per_level", 3)
    if self.hintsUsed >= maxPerLevel then
        return nil, "hint_limit"
    end
    local hint = Solver.hintCell(self.grid)
    if not hint then return nil, "nothing_to_hint" end
    self.hintsUsed = self.hintsUsed + 1
    local res = self:fill(hint.r, hint.c, hint.char)
    self:emit("on_hint_used", { r = hint.r, c = hint.c, char = hint.char, source = self.ctx.hintSource or "free" })
    return hint, nil, res
end

--- 洗牌：打乱备选区顺序（不改变可用性）
function Session:useShuffle()
    local order = {}
    for i = 1, #self.bank do order[i] = i end
    util.shuffle(order)
    local newBank = {}
    for _, oldIdx in ipairs(order) do
        newBank[#newBank + 1] = self.bank[oldIdx]
    end
    self.bank = newBank
    self.shuffleUsed = self.shuffleUsed + 1
    self.selectedBankIdx = nil
    self:emit("on_shuffle", { order = order })
    return self.bank
end

function Session:useSkip()
    self.skipped = true
    self.state = "Skipped"
    self:emit("on_skip", { levelId = self.levelId })
    return true
end

------------------------------------------------------------------------------
-- 结算与存档
------------------------------------------------------------------------------

function Session:statsSnapshot()
    return {
        levelId = self.levelId,
        durationMs = self.stats.durationMs,
        hintsUsed = self.hintsUsed,
        wrongCount = self.wrongCount,
        shuffleUsed = self.shuffleUsed,
        cleared = Validator.checkLevel(self.grid),
    }
end

--- 结算：公式全部读 config
function Session:settle()
    if type(self.ctx.settle) == "function" then
        return self.ctx.settle(self.levelId, self:statsSnapshot())
    end
    local base = Config.num("gold.base_per_level", 10)
    local bonus = Config.num("gold.bonus_per_unused_hint", 5)
    local maxHints = Config.num("hints.max_per_level", 3)
    local unused = math.max(0, maxHints - self.hintsUsed)
    local gold = base + bonus * unused
    return { gold = gold, unusedHints = unused, streak = 0 }
end

--- 中途退出：返回可存档快照
function Session:abandon()
    self.stats.durationMs = (os.clock() - self.stats.startedAt) * 1000
    return {
        levelId = self.levelId,
        grid = self.grid:snapshot(),
        bank = self.bank,
        hintsUsed = self.hintsUsed,
        wrongCount = self.wrongCount,
        stats = self:statsSnapshot(),
    }
end

--- 从快照恢复（中断续玩）
function Session.resume(snapshot, ctx)
    if type(snapshot) ~= "table" or not snapshot.grid then return nil, "快照无效" end
    local s = Session.start(snapshot.levelId, ctx)
    if not s then return nil, "关卡加载失败" end
    local ok, grid = pcall(Grid.restore, snapshot.grid)
    if ok then
        s.grid = grid
    end
    s.bank = snapshot.bank or s.bank
    s.hintsUsed = snapshot.hintsUsed or 0
    s.wrongCount = snapshot.wrongCount or 0
    s.grid:refreshDoneFlags()
    return s
end

return Session
