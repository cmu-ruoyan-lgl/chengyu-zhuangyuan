-- 网格模型：由关卡数据构建运行时棋盘。
-- 纯逻辑，不依赖引擎与 UI；坐标与关卡数据一致，统一使用 **0-based**（r/c）。
-- 交叉关系（owners）由成语覆盖范围推导，是「交叉点亮」动画的唯一数据源。

local util = require("core.util")

local Grid = {}
Grid.__index = Grid

local DIRS = { h = { dr = 0, dc = 1 }, v = { dr = 1, dc = 0 } }

--- 由关卡数据构建。levelData 需含 size 与 idioms；presets 为预填格（可空）。
function Grid.new(levelData)
    assert(type(levelData) == "table", "Grid.new 需要 levelData")
    local size = levelData.size or { 4, 4 }
    local self = setmetatable({}, Grid)

    self.rows = size[1] or 4
    self.cols = size[2] or size[1] or 4
    self.idioms = {}
    self.idiomOrder = {}
    self.cells = {}

    for r = 0, self.rows - 1 do
        self.cells[r] = {}
        for c = 0, self.cols - 1 do
            self.cells[r][c] = { owners = {}, answer = nil, value = nil, isBlank = false }
        end
    end

    -- 1) 铺成语：覆盖格子、写 answer、登记 owners
    for _, def in ipairs(levelData.idioms or {}) do
        local step = DIRS[def.dir]
        assert(step, "非法成语方向: " .. tostring(def.dir))
        local chars = util.chars(def.answer)
        local cells = {}
        for i = 1, #chars do
            local r = def.row + step.dr * (i - 1)
            local c = def.col + step.dc * (i - 1)
            assert(r >= 0 and r < self.rows and c >= 0 and c < self.cols,
                string.format("成语 %s 越界 (%d,%d)", tostring(def.id), r, c))
            local cell = self.cells[r][c]
            -- 交叉处字符必须一致，否则关卡数据有问题
            if cell.answer ~= nil then
                assert(cell.answer == chars[i],
                    string.format("交叉字符冲突 (%d,%d): %s vs %s", r, c, cell.answer, chars[i]))
            end
            cell.answer = chars[i]
            cell.owners[#cell.owners + 1] = def.id
            cells[#cells + 1] = { r = r, c = c }
        end
        self.idioms[def.id] = {
            id = def.id,
            dir = def.dir,
            row = def.row,
            col = def.col,
            answer = def.answer,
            idiom_ref = def.idiom_ref,
            cells = cells,
            done = false,
        }
        self.idiomOrder[#self.idiomOrder + 1] = def.id
    end

    -- 2) 预填格：直接落到 value 上，且不算待填空位
    for _, p in ipairs(levelData.presets or {}) do
        local cell = self.cells[p.r] and self.cells[p.r][p.c]
        if cell then
            assert(cell.answer == p.char,
                string.format("预填字符与答案不符 (%d,%d)", p.r, p.c))
            cell.value = p.char
            cell.isPreset = true
        end
    end

    -- 3) 统计空位：给定字（preset）不计入待填总数
    self.totalBlanks = 0
    self.filledCount = 0
    for r = 0, self.rows - 1 do
        for c = 0, self.cols - 1 do
            local cell = self.cells[r][c]
            if cell.answer ~= nil then
                cell.isBlank = (cell.value == nil) and not cell.isPreset
                if not cell.isPreset then
                    self.totalBlanks = self.totalBlanks + 1
                    if cell.value ~= nil then
                        self.filledCount = self.filledCount + 1
                    end
                end
            end
        end
    end

    self.levelData = levelData
    return self
end

--- 由快照恢复（中断续玩）
function Grid.restore(snapshot)
    assert(type(snapshot) == "table", "Grid.restore 需要 snapshot")
    local g = Grid.new(snapshot.levelData)
    for _, item in ipairs(snapshot.values or {}) do
        local cell = g.cells[item.r] and g.cells[item.r][item.c]
        if cell and cell.isBlank then
            cell.value = item.char
        end
    end
    g:recomputeCounters()
    g:refreshDoneFlags()
    return g
end

function Grid:size()
    return self.rows, self.cols
end

function Grid:getCell(r, c)
    local row = self.cells[r]
    return row and row[c] or nil
end

function Grid:idiomsOfCell(r, c)
    local cell = self:getCell(r, c)
    return cell and cell.owners or {}
end

function Grid:isCrossPoint(r, c)
    local cell = self:getCell(r, c)
    return cell ~= nil and #cell.owners > 1
end

--- 写入：只有空位可写；正确返回 true，错误返回 false（不落盘）
function Grid:setValue(r, c, char)
    local cell = self:getCell(r, c)
    if not cell or not cell.isBlank or cell.value ~= nil then
        return false, "not_blank"
    end
    local ok = (cell.answer == char)
    if ok then
        cell.value = char
        cell.isBlank = false
        self.filledCount = self.filledCount + 1
    end
    return ok, ok and nil or "wrong_char"
end

--- 清空已填格（撤销）
function Grid:clearCell(r, c)
    local cell = self:getCell(r, c)
    if not cell or cell.answer == nil or cell.value == nil then
        return false
    end
    if cell.isPreset then
        return false -- 给定字不可撤销
    end
    cell.value = nil
    cell.isBlank = true
    self.filledCount = self.filledCount - 1
    self:refreshDoneFlags()
    return true
end

function Grid:blanksLeft()
    return self.totalBlanks - self.filledCount
end

function Grid:recomputeCounters()
    self.totalBlanks, self.filledCount = 0, 0
    for r = 0, self.rows - 1 do
        for c = 0, self.cols - 1 do
            local cell = self.cells[r][c]
            if cell.answer ~= nil then
                cell.isBlank = (cell.value == nil) and not cell.isPreset
                if not cell.isPreset then
                    -- totalBlanks = 所有待填格（含已填），filledCount = 已填数
                    self.totalBlanks = self.totalBlanks + 1
                    if cell.value ~= nil then
                        self.filledCount = self.filledCount + 1
                    end
                end
            end
        end
    end
end

--- 重算每条成语的完成标记（撤销后需要）
function Grid:refreshDoneFlags()
    for _, id in ipairs(self.idiomOrder) do
        local def = self.idioms[id]
        local complete = true
        for _, pos in ipairs(def.cells) do
            local cell = self.cells[pos.r][pos.c]
            if cell.value == nil then complete = false; break end
        end
        def.done = complete
    end
end

--- 序列化（供存档/中断续玩）
function Grid:snapshot()
    local values = {}
    for r = 0, self.rows - 1 do
        for c = 0, self.cols - 1 do
            local cell = self.cells[r][c]
            if cell.value ~= nil and not cell.isPreset then
                values[#values + 1] = { r = r, c = c, char = cell.value }
            end
        end
    end
    return { levelData = self.levelData, values = values }
end

--- 当前棋盘上所有已填/预填字符（供字形预热使用，去重）
function Grid:distinctChars()
    local out = {}
    for r = 0, self.rows - 1 do
        for c = 0, self.cols - 1 do
            local cell = self.cells[r][c]
            if cell.answer ~= nil then out[#out + 1] = cell.answer end
        end
    end
    for _, ch in ipairs(self.levelData.bank or {}) do
        out[#out + 1] = ch
    end
    return util.unique(out)
end

return Grid
