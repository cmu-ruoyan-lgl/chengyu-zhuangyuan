-- 经济护栏与长线模拟（T17 验收：「30 天模拟不通胀」）。
-- 护栏定义（economy_guard）：
--   ①挂机产出封顶 8 小时（followers.idle_cap_hours）；
--   ②日挂机产出 / 日主动产出 ≤ idle_output_ratio_cap（默认 0.3）；
--   ③「全建满」（府邸满级 + 全门客满级）所需金币，必须显著高于 30 天累计产出，
--      否则金币在月内贬值、成长线失去意义（RISK Failure State ⑤）。
-- 本模块纯计算，不 require UI，可离线单测。

local Config = require("core.config")
local Manor = require("progress.manor")
local Followers = require("econ.followers")
local Rank = require("progress.rank")

local M = {}

function M.idleCapRatio()
    return Config.num("economy_guard.idle_output_ratio_cap", 0.3)
end

------------------------------------------------------------------------------
-- 护栏②：日挂机产出上限
------------------------------------------------------------------------------

--- 参考日均主动产出（PRD §3.5 供需校验口径：30 关 × 15 金币 = 450）
function M.referenceActiveDaily(save)
    local levels = Config.num("economy_guard.reference_levels_per_day", 30)
    local perLevel = Config.num("economy_guard.reference_gold_per_level", 15)
    return Manor.applyBonus(save, levels * perLevel) + Rank.salary(save)
end

--- 日挂机金币上限 = 护栏比例 × 参考日均主动产出（PRD §3.5：≤135）
function M.idleDailyCap(save)
    return math.floor(M.idleCapRatio() * M.referenceActiveDaily(save))
end

--- 实际日挂机产出 = 时间封顶与金币封顶取小者
function M.effectiveDailyIdle(save)
    return math.min(Followers.dailyIdleCap(save), M.idleDailyCap(save))
end

--- 收取挂机金币（带双重护栏）。返回 实收金币
function M.collectIdle(save, nowTs)
    return Followers.collect(save, nowTs, M.idleDailyCap(save))
end

--- 挂机占比（相对给定的日主动产出）。activeGold<=0 时返回 0
function M.idleRatio(save, activeDailyGold)
    local idle = M.effectiveDailyIdle(save)
    local active = tonumber(activeDailyGold) or 0
    if active <= 0 then return 0 end
    return idle / active
end

--- 是否击穿护栏②
function M.capExceeded(save, activeDailyGold)
    return M.idleRatio(save, activeDailyGold) > M.idleCapRatio()
end

--- 护栏报告
function M.guardReport(save, activeDailyGold)
    local ratio = M.idleRatio(save, activeDailyGold)
    local cap = M.idleCapRatio()
    return {
        ratio = ratio,
        cap = cap,
        ok = ratio <= cap,
        dailyIdle = M.effectiveDailyIdle(save),
        theoreticalIdle = Followers.dailyIdleCap(save),
        idleDailyCap = M.idleDailyCap(save),
        activeDaily = tonumber(activeDailyGold) or 0,
        idleCapHours = Config.num("followers.idle_cap_hours", 8),
    }
end

--- 全建满所需金币
function M.fullBuildCost()
    return Manor.totalCost() + Followers.totalCost()
end

------------------------------------------------------------------------------
-- 30 天模拟
------------------------------------------------------------------------------

--- 单关产出（不含连对倍率，保守估计）：base + bonus × 剩余提示上限
function M.perLevelGold()
    local base = Config.num("gold.base_per_level", 10)
    local bonus = Config.num("gold.bonus_per_unused_hint", 5)
    local maxHints = Config.num("hints.max_per_level", 3)
    return base + bonus * maxHints
end

--- 日主动产出（含府邸加成 + 当日俸禄）
function M.activeDailyGold(save, levelsPerDay)
    local n = tonumber(levelsPerDay) or 0
    local raw = M.perLevelGold() * n
    local withManor = Manor.applyBonus(save, raw)
    return withManor + Rank.salary(save)
end

--- 模拟 days 天。
--- opts: { levelsPerDay, startSave, buyFollowers = false }
--- 返回 { days = { {day, active, idle, gold} }, totalGold, totalIdle, totalActive,
---        idleRatio, fullBuildCost, daysToFullBuild }
function M.simulate(days, levelsPerDay, opts)
    opts = opts or {}
    days = tonumber(days) or 0
    levelsPerDay = tonumber(levelsPerDay) or 0
    local save = opts.startSave or {
        manor_level = 1,
        followers = {},
        gold = 0,
        max_level_passed = 0,
    }
    local perDay = {}
    local totalGold, totalIdle, totalActive = 0, 0, 0
    for d = 1, days do
        local active = M.activeDailyGold(save, levelsPerDay)
        -- 挂机按「每日收一次」计，且受双重护栏封顶（与运行时口径一致）
        local idle = math.min(Followers.dailyIdleCap(save), M.idleDailyCap(save))
        totalActive = totalActive + active
        totalIdle = totalIdle + idle
        totalGold = totalGold + active + idle
        save.gold = (tonumber(save.gold) or 0) + active + idle
        perDay[#perDay + 1] = { day = d, active = active, idle = idle, gold = active + idle }
    end
    local full = M.fullBuildCost()
    local avgDaily = days > 0 and (totalGold / days) or 0
    return {
        days = perDay,
        totalGold = totalGold,
        totalIdle = totalIdle,
        totalActive = totalActive,
        idleRatio = totalActive > 0 and (totalIdle / totalActive) or 0,
        fullBuildCost = full,
        avgDailyGold = avgDaily,
        daysToFullBuild = avgDaily > 0 and (full / avgDaily) or math.huge,
    }
end

return M
