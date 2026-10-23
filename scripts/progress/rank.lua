-- 官职晋升（T15，PRD §3.4）：童生→秀才→举人→贡士→进士→探花→榜眼→状元（8 阶）。
-- 晋升由「累计通关关卡数」驱动；阈值全部读 config.rank.tiers。
-- 纯逻辑：不 require UI。

local Config = require("core.config")

local M = {}

--- 全部阶位（数组，按 need 升序）
function M.tiers()
    local t = Config.get("rank.tiers", {})
    if type(t) ~= "table" or #t == 0 then
        t = { { id = "tongsheng", name = "童生", need = 0 } }
    end
    return t
end

--- 按累计通关数算当前阶位索引（1 基）
function M.indexFor(levelsPassed)
    local n = tonumber(levelsPassed) or 0
    local tiers = M.tiers()
    local idx = 1
    for i, tier in ipairs(tiers) do
        if n >= (tonumber(tier.need) or 0) then idx = i end
    end
    return idx
end

--- 当前阶位定义
function M.current(save)
    local tiers = M.tiers()
    return tiers[M.indexFor(save and save.max_level_passed or 0)]
end

--- 晋升检查：返回晋升后的阶位（含 name），无晋升返回 nil
function M.refresh(save)
    local tiers = M.tiers()
    local idx = M.indexFor(save.max_level_passed)
    local tier = tiers[idx]
    if not tier then return nil end
    if save.rank_id == tier.id then return nil end
    save.rank_id = tier.id
    return tier
end

--- 下一阶位与进度（用于进度条）
function M.next(save)
    local tiers = M.tiers()
    local idx = M.indexFor(save and save.max_level_passed or 0)
    local cur = tiers[idx]
    local nxt = tiers[idx + 1]
    if not nxt then
        return nil, 1, 0, 0
    end
    local passed = tonumber(save.max_level_passed) or 0
    local from = tonumber(cur.need) or 0
    local to = tonumber(nxt.need) or 1
    local ratio = math.max(0, math.min(1, (passed - from) / math.max(1, to - from)))
    return nxt, ratio, passed - from, to - from
end

--- 阶位称号（显示用）
function M.name(save)
    local t = M.current(save)
    return t and t.name or "童生"
end

--- 俸禄：每阶每日一次（T19 每日任务里发放），金额 = tier 序号 × salary_gold_per_tier
function M.salary(save)
    local idx = M.indexFor(save and save.max_level_passed or 0)
    return idx * Config.num("rank.salary_gold_per_tier", 20)
end

--- 解锁的关卡段（晋升贡士 = 第 3 阶索引起可进进阶段）
function M.unlockedSegment(save)
    local idx = M.indexFor(save and save.max_level_passed or 0)
    return math.max(1, idx)
end

return M
