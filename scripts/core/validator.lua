-- 判定逻辑：成语完成、交叉生效、通关。
-- 只做纯计算，不修改除 done 标记以外的状态，不碰 UI。

local Validator = {}

--- 单条成语是否完整且正确
function Validator.checkIdiom(grid, idiomId)
    local def = grid.idioms and grid.idioms[idiomId]
    if not def then return false, nil end
    local s = {}
    for _, pos in ipairs(def.cells) do
        local cell = grid.cells[pos.r][pos.c]
        if cell.value == nil then
            def.done = false
            return false, def.cells
        end
        s[#s + 1] = cell.value
    end
    local text = table.concat(s)
    def.done = (text == def.answer)
    return def.done, def.cells
end

--- 全关是否通过
function Validator.checkLevel(grid)
    for _, id in ipairs(grid.idiomOrder) do
        if not grid.idioms[id].done then
            -- 可能刚恢复存档，标记未刷新，先算一次
            local ok = Validator.checkIdiom(grid, id)
            if not ok then return false end
        end
    end
    return true
end

--- 交叉格是否「双向都成立」（其全部所属成语均已完成）
function Validator.isCrossValidated(grid, r, c)
    local owners = grid:idiomsOfCell(r, c)
    if #owners < 2 then return false end
    for _, id in ipairs(owners) do
        if not grid.idioms[id].done then return false end
    end
    return true
end

--- 单格写入后的增量校验：只检查该格 owners（O(1)，不做全量扫描）
function Validator.onCellFilled(grid, r, c)
    local result = { completedIdiomIds = {}, newlyValidCross = {} }
    local owners = grid:idiomsOfCell(r, c)
    if #owners == 0 then return result end

    for _, id in ipairs(owners) do
        if not grid.idioms[id].done then
            local ok = Validator.checkIdiom(grid, id)
            if ok then
                result.completedIdiomIds[#result.completedIdiomIds + 1] = id
            end
        end
    end

    -- 交叉格：所有所属成语都完成时才亮
    if #owners > 1 and Validator.isCrossValidated(grid, r, c) then
        result.newlyValidCross[#result.newlyValidCross + 1] = { r = r, c = c }
    end
    -- 同条成语上的其它交叉格也可能因此点亮（比如该成语另一端）
    for _, id in ipairs(owners) do
        for _, pos in ipairs(grid.idioms[id].cells) do
            if (pos.r ~= r or pos.c ~= c) and grid:isCrossPoint(pos.r, pos.c)
                and Validator.isCrossValidated(grid, pos.r, pos.c) then
                local dup = false
                for _, added in ipairs(result.newlyValidCross) do
                    if added.r == pos.r and added.c == pos.c then dup = true; break end
                end
                if not dup then
                    result.newlyValidCross[#result.newlyValidCross + 1] = { r = pos.r, c = pos.c }
                end
            end
        end
    end
    return result
end

return Validator
