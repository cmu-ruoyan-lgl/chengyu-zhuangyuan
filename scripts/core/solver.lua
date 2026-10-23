-- 可解性校验（锚点推理）。
-- 用途：① 关卡生成时剔除「必须靠猜」的关；② 运行时兜底判断是否死局。
-- 规则：反复填补「恰好只剩 1 个空位」的成语，直到无进展；全部填满即视为可推导。

local util = require("core.util")
local Grid = require("core.grid")
local Idioms = require("core.idioms")

local Solver = {}

--- 取题库（失败则退化为纯逻辑推导，不影响判定可用性）
local function idiomPool()
    local ok = pcall(Idioms.init, "data/idioms.json")
    if not ok then return nil end
    return Idioms.all()
end

--- 从备选字里消耗一个字（模拟玩家用掉字块）
local function takeFromBank(bankAvail, ch)
    local n = bankAvail[ch] or 0
    if n <= 0 then return false end
    bankAvail[ch] = n - 1
    return true
end

--- 缺失字符是否都能从剩余备选字里取到
local function missingAvailable(bankAvail, missing)
    local need = {}
    for _, ch in ipairs(missing) do
        need[ch] = (need[ch] or 0) + 1
    end
    for ch, n in pairs(need) do
        if (bankAvail[ch] or 0) < n then return false end
    end
    return true
end

--- 词与模式是否吻合（nil 位置为未知）
-- 注意：pattern 里可能有 nil 空洞，长度必须外部传入（#pattern 对空洞不可靠）
local function matches(wordChars, pattern, plen)
    for i = 1, plen do
        if pattern[i] ~= nil and pattern[i] ~= wordChars[i] then return false end
    end
    return true
end

--- 在关卡数据上做模拟推理（不改传入数据）
-- 规则 A：某条成语只剩 1 个空位 → 直接补上（经典锚点推理）
-- 规则 B：按「已知字模式 + 剩余备选字」筛题库，若候选唯一 → 补上
--   规则 B 是真实玩家的主要手段：备选区只有那么几个字，能拼出的成语往往唯一。
function Solver.isDerivable(levelData)
    local ok, gridOrErr = pcall(Grid.new, levelData)
    if not ok then return false, { error = tostring(gridOrErr) } end
    local grid = gridOrErr

    local bankAvail = {}
    for _, ch in ipairs(levelData.bank or {}) do
        bankAvail[ch] = (bankAvail[ch] or 0) + 1
    end
    local pool = idiomPool()

    local function fillCell(r, c, char)
        local cell = grid.cells[r][c]
        if cell.value ~= nil then return end
        cell.value = char
        cell.isBlank = false
        grid.filledCount = grid.filledCount + 1
        if not cell.isPreset then takeFromBank(bankAvail, char) end
    end

    local function fillIdiom(def, wordChars)
        for i, pos in ipairs(def.cells) do
            fillCell(pos.r, pos.c, wordChars[i])
        end
        grid:refreshDoneFlags()
    end

    local progress = true
    local guard = 0
    while progress do
        progress = false
        guard = guard + 1
        if guard > 200 then break end

        -- 规则 A
        for _, id in ipairs(grid.idiomOrder) do
            local def = grid.idioms[id]
            if not def.done then
                local emptyPos, emptyCount = nil, 0
                for _, pos in ipairs(def.cells) do
                    if grid.cells[pos.r][pos.c].value == nil then
                        emptyCount = emptyCount + 1
                        emptyPos = pos
                    end
                end
                if emptyCount == 1 then
                    fillIdiom(def, util.chars(def.answer))
                    progress = true
                end
            end
        end

        -- 规则 B
        if pool and not progress then
            for _, id in ipairs(grid.idiomOrder) do
                local def = grid.idioms[id]
                if def.done then goto continue_b end
                local pattern = {}
                local plen = #def.cells
                for idx, pos in ipairs(def.cells) do
                    pattern[idx] = grid.cells[pos.r][pos.c].value -- 可能是 nil（空洞）
                end
                local candidates = {}
                for _, entry in ipairs(pool) do
                    local wc = util.chars(entry.word)
                    if #wc == plen and matches(wc, pattern, plen) then
                        local need = {}
                        for i = 1, plen do
                            if pattern[i] == nil then need[#need + 1] = wc[i] end
                        end
                        if missingAvailable(bankAvail, need) then
                            candidates[#candidates + 1] = wc
                            if #candidates > 1 then break end
                        end
                    end
                end
                if os.getenv("DEBUG_SOLVER") then
                    local shown = {}
                    for i = 1, plen do shown[i] = pattern[i] or "_" end
                    print(string.format("[solver] %s pattern=%s 候选=%d 首个=%s",
                        def.id, table.concat(shown, ""), #candidates,
                        candidates[1] and table.concat(candidates[1], "") or "nil"))
                end
                if #candidates == 1 then
                    fillIdiom(def, candidates[1])
                    progress = true
                end
                ::continue_b::
            end
        end
    end

    local stalled = {}
    for _, id in ipairs(grid.idiomOrder) do
        if not grid.idioms[id].done then
            stalled[#stalled + 1] = id
        end
    end
    return #stalled == 0, { stalledIdioms = stalled }
end

--- 当前局面是否还能继续推导（运行时兜底）
function Solver.canProgress(grid)
    for _, id in ipairs(grid.idiomOrder) do
        local def = grid.idioms[id]
        if not def.done then
            local emptyCount = 0
            for _, pos in ipairs(def.cells) do
                if grid.cells[pos.r][pos.c].value == nil then
                    emptyCount = emptyCount + 1
                end
            end
            if emptyCount <= 1 then return true end
        end
    end
    return false
end

--- 给一个可填的提示位置：优先「只剩 1 空」的成语，其次任意空位
function Solver.hintCell(grid)
    local fallback = nil
    for _, id in ipairs(grid.idiomOrder) do
        local def = grid.idioms[id]
        if not def.done then
            for _, pos in ipairs(def.cells) do
                local cell = grid.cells[pos.r][pos.c]
                if cell.value == nil then
                    if fallback == nil then
                        fallback = { r = pos.r, c = pos.c, char = cell.answer, idiomId = id }
                    end
                    local emptyCount = 0
                    for _, p2 in ipairs(def.cells) do
                        if grid.cells[p2.r][p2.c].value == nil then emptyCount = emptyCount + 1 end
                    end
                    if emptyCount == 1 then
                        return { r = pos.r, c = pos.c, char = cell.answer, idiomId = id }
                    end
                end
            end
        end
    end
    return fallback
end

--- 统计关卡不重复汉字数（P2 字形预算约束）
function Solver.distinctCharCount(levelData)
    local chars = {}
    for _, def in ipairs(levelData.idioms or {}) do
        for _, ch in ipairs(util.chars(def.answer)) do
            chars[#chars + 1] = ch
        end
    end
    for _, ch in ipairs(levelData.bank or {}) do
        chars[#chars + 1] = ch
    end
    return #util.unique(chars)
end

return Solver
