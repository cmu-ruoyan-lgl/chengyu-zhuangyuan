-- 成就系统（T19，PRD §3.7）：达成即发放金币，条目与阈值全部读 config.achievements。
-- 度量口径：levels = 累计通关关数；book = 图鉴解锁数；streak = 历史最长连对。

local Config = require("core.config")
local Currency = require("econ.currency")
local Book = require("progress.book")

local M = {}

function M.defs()
    return Config.get("achievements.list", {})
end

--- 度量取值
function M.metric(save, name)
    if name == "levels" then
        return tonumber(save.stats and save.stats.total_levels) or 0
    elseif name == "book" then
        return Book.count(save)
    elseif name == "streak" then
        return tonumber(save.best_streak) or 0
    end
    return 0
end

--- 成就列表（含进度）
function M.list(save)
    local out = {}
    for _, def in ipairs(M.defs()) do
        local target = tonumber(def.target) or 0
        local progress = M.metric(save, def.metric)
        out[#out + 1] = {
            id = def.id,
            name = def.name,
            metric = def.metric,
            target = target,
            progress = progress,
            done = progress >= target,
            claimed = save.achievements and save.achievements[def.id] == true,
            reward_gold = tonumber(def.reward_gold) or 0,
            ratio = target > 0 and math.min(1, progress / target) or 0,
        }
    end
    return out
end

--- 检查并结算新达成成就。返回本次新达成的数组（每项含 gold）
function M.refresh(save)
    if type(save.achievements) ~= "table" then save.achievements = {} end
    local gained = {}
    for _, def in ipairs(M.defs()) do
        local target = tonumber(def.target) or 0
        if save.achievements[def.id] ~= true and M.metric(save, def.metric) >= target then
            save.achievements[def.id] = true
            local gold = tonumber(def.reward_gold) or 0
            if gold > 0 then Currency.add(save, gold, "achievement") end
            gained[#gained + 1] = { id = def.id, name = def.name, gold = gold }
        end
    end
    return gained
end

--- 已达成数量 / 总数
function M.progress(save)
    local done, total = 0, 0
    for _, a in ipairs(M.list(save)) do
        total = total + 1
        if a.done then done = done + 1 end
    end
    return done, total
end

return M
