-- 府邸升级（T16，PRD §3.4）：6 级（茅草屋→宫殿）。
-- 成本、名称、金币加成全部读 config.manor；本模块只做纯计算 + 扣费，不持有状态。
-- 府邸提供「结算金币加成」（manor.gold_bonus_ratio），加成在 Currency 结算后由
-- Game 统一施加（见 system/game.lua settleHook），保证单一加成入口。

local Config = require("core.config")
local Currency = require("econ.currency")

local M = {}

local function names()
    return Config.get("manor.names", {})
end

local function costs()
    return Config.get("manor.costs", {})
end

local function ratios()
    return Config.get("manor.gold_bonus_ratio", {})
end

--- 最高等级（= 名称数）
function M.maxLevel()
    return math.max(1, #names())
end

--- 当前等级（越界收敛到 [1, maxLevel]）
function M.level(save)
    local lv = tonumber(save and save.manor_level) or 1
    if lv < 1 then lv = 1 end
    if lv > M.maxLevel() then lv = M.maxLevel() end
    return lv
end

--- 当前府邸名称
function M.name(save)
    return names()[M.level(save)] or "府邸"
end

--- 当前金币加成比例（0.05 = +5%）
function M.ratio(save)
    return tonumber(ratios()[M.level(save)]) or 0
end

--- 下一级所需金币；已满级返回 nil
function M.nextCost(save)
    return tonumber(costs()[M.level(save)]) or nil
end

--- 是否已满级
function M.isMax(save)
    return M.level(save) >= M.maxLevel()
end

--- 金币是否够升下一级
function M.canUpgrade(save)
    local c = M.nextCost(save)
    return c ~= nil and Currency.balance(save) >= c
end

--- 升级：扣金币并 +1 级。返回 新等级 或 nil,err
function M.upgrade(save)
    if M.isMax(save) then return nil, "max_level" end
    local c = M.nextCost(save)
    if not c then return nil, "no_cost_defined" end
    local ok, err = Currency.spend(save, c, "manor_upgrade")
    if not ok then return nil, err or "insufficient" end
    save.manor_level = M.level(save) + 1
    return save.manor_level
end

--- 金币加成后的金额（向下取整，避免小数金币）
function M.applyBonus(save, gold)
    return math.floor((tonumber(gold) or 0) * (1 + M.ratio(save)))
end

--- 全部升满所需金币总额（经济护栏与模拟用）
function M.totalCost()
    local sum = 0
    for _, c in ipairs(costs()) do
        sum = sum + (tonumber(c) or 0)
    end
    return sum
end

--- 展示用：{ level, name, ratio, nextCost, isMax }
function M.info(save)
    return {
        level = M.level(save),
        name = M.name(save),
        ratio = M.ratio(save),
        nextCost = M.nextCost(save),
        isMax = M.isMax(save),
        canUpgrade = M.canUpgrade(save),
    }
end

return M
