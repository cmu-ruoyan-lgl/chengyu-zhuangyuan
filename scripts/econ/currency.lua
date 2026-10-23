-- 金币（DEV §6.2）。结算公式与数值全部读 config：
--   gold = base_per_level + bonus_per_unused_hint * unusedHints
--   连对 ≥ streak_threshold 时 ×streak_multiplier（PRD §3.5）
-- 连对定义（裁决 #14）：本次通关无错填且未使用提示才续连；错填或提示即中断清零。

local Config = require("core.config")

local M = {}

function M.add(save, amount, reason)
    if type(save) ~= "table" or (tonumber(amount) or 0) <= 0 then return false end
    save.gold = (tonumber(save.gold) or 0) + math.floor(amount)
    return true, save.gold
end

--- 消费：余额不足返回 false，不产生负数。reason 预留埋点。
function M.spend(save, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end
    local gold = tonumber(save.gold) or 0
    if gold < amount then return false, "insufficient" end
    save.gold = gold - amount
    return true
end

function M.balance(save)
    return tonumber(save.gold) or 0
end

--- 结算通关奖励并更新连对。stats 来自 Session:statsSnapshot()。
--- 返回 { gold, unusedHints, streak, streakMultiplier }
function M.settleLevel(save, stats)
    stats = stats or {}
    local base = Config.num("gold.base_per_level", 10)
    local bonus = Config.num("gold.bonus_per_unused_hint", 5)
    local maxHints = Config.num("hints.max_per_level", 3)
    local threshold = Config.num("gold.streak_threshold", 3)
    local mult = Config.num("gold.streak_multiplier", 2)

    local unused = math.max(0, maxHints - (tonumber(stats.hintsUsed) or 0))
    local gold = base + bonus * unused

    local clean = (tonumber(stats.wrongCount) or 0) == 0
        and (tonumber(stats.hintsUsed) or 0) == 0
    if clean then
        save.streak = (tonumber(save.streak) or 0) + 1
    else
        save.streak = 0
    end
    if (tonumber(save.streak) or 0) > (tonumber(save.best_streak) or 0) then
        save.best_streak = save.streak
    end

    local streakMul = 1
    if clean and save.streak >= threshold then
        streakMul = mult
        gold = gold * mult
    end

    M.add(save, gold, "level_settle")
    return {
        gold = gold,
        unusedHints = unused,
        streak = save.streak,
        streakMultiplier = streakMul,
    }
end

return M
