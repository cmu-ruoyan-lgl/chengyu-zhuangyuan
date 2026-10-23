-- 每日系统（T19，PRD §3.7）：每日重置 + 7 日签到 + 每日任务。
-- 时间基准一律走 system/time（服务端校准），禁止 os.time()（DEV §0.2）。
-- 每日重置：以「天序号 = floor(ts / sec_per_day)」为键，跨天清零
--   当日已用提示数、每日任务进度与领取状态。

local Config = require("core.config")
local Time = require("system.time")
local Currency = require("econ.currency")
local Items = require("econ.items")

local M = {}

------------------------------------------------------------------------------
-- 天数与重置
------------------------------------------------------------------------------

function M.secPerDay()
    return Config.num("time.sec_per_day", 86400)
end

--- 天序号（权威：服务端秒 / 每日秒数）
function M.dayKey(nowTs)
    local now = tonumber(nowTs) or Time.now()
    return math.floor(now / M.secPerDay())
end

local function ensureDaily(save)
    if type(save.daily) ~= "table" then save.daily = {} end
    local d = save.daily
    if type(d.tasks) ~= "table" then d.tasks = {} end
    if type(d.claimed) ~= "table" then d.claimed = {} end
    if type(d.day) ~= "number" then d.day = 0 end
    return d
end

--- 跨天则重置。返回 true 表示本次发生了重置
function M.resetIfNeeded(save, nowTs)
    local day = M.dayKey(nowTs)
    if ensureDaily(save).day == day then return false end
    save.daily = { day = day, tasks = {}, claimed = {} }
    save.daily_reset_ts = day
    save.hints_used_today = 0
    return true
end

------------------------------------------------------------------------------
-- 签到
------------------------------------------------------------------------------

local function ensureSignin(save)
    if type(save.signin) ~= "table" then save.signin = {} end
    save.signin.streak = tonumber(save.signin.streak) or 0
    save.signin.last_claim_day = tonumber(save.signin.last_claim_day) or 0
    return save.signin
end

function M.cycleDays()
    return math.max(1, Config.num("signin.cycle_days", 7))
end

function M.rewards()
    return Config.get("signin.rewards", {})
end

--- 签到状态：{ streak, nextStreak, dayIndex, canClaim, reward, claimed }
--- 断签（间隔 >1 天）则连签归 1，重新从周期第 1 天拿奖励
function M.signinInfo(save, nowTs)
    local s = ensureSignin(save)
    local today = M.dayKey(nowTs)
    local claimed = (s.last_claim_day == today)
    local gap = today - s.last_claim_day
    local nextStreak
    if claimed then
        nextStreak = s.streak
    elseif gap <= 1 then
        nextStreak = s.streak + 1
    else
        nextStreak = 1
    end
    local idx = ((math.max(1, nextStreak) - 1) % M.cycleDays()) + 1
    return {
        streak = s.streak,
        nextStreak = nextStreak,
        dayIndex = idx,
        canClaim = not claimed,
        claimed = claimed,
        reward = M.rewards()[idx],
        today = today,
    }
end

--- 领取签到奖励。返回 { gold, item, dayIndex, streak } 或 nil,err
function M.claimSignin(save, nowTs)
    local info = M.signinInfo(save, nowTs)
    if not info.canClaim then return nil, "already_claimed" end
    local s = ensureSignin(save)
    s.streak = info.nextStreak
    s.last_claim_day = info.today
    local r = info.reward or {}
    local gold = tonumber(r.gold) or 0
    if gold > 0 then Currency.add(save, gold, "signin") end
    if r.item then Items.grant(save, r.item, 1) end
    return { gold = gold, item = r.item, dayIndex = info.dayIndex, streak = s.streak }
end

------------------------------------------------------------------------------
-- 每日任务
------------------------------------------------------------------------------

function M.taskDefs()
    return Config.get("daily_task.tasks", {})
end

local function defOf(id)
    for _, t in ipairs(M.taskDefs()) do
        if t.id == id then return t end
    end
    return nil
end

function M.taskProgress(save, id)
    return tonumber(ensureDaily(save).tasks[id]) or 0
end

--- 推进任务进度（不超过 target）。返回推进后的进度
function M.bump(save, id, amount, nowTs)
    M.resetIfNeeded(save, nowTs)
    local def = defOf(id)
    if not def then return 0 end
    local d = ensureDaily(save)
    local cur = tonumber(d.tasks[id]) or 0
    local target = tonumber(def.target) or 0
    local next = cur + (tonumber(amount) or 1)
    if next > target then next = target end
    if next < 0 then next = 0 end
    d.tasks[id] = next
    return next
end

function M.isDone(save, id)
    local def = defOf(id)
    if not def then return false end
    return M.taskProgress(save, id) >= (tonumber(def.target) or 0)
end

function M.isClaimed(save, id)
    return ensureDaily(save).claimed[id] == true
end

--- 任务列表（含进度与领取态）
function M.taskList(save, nowTs)
    M.resetIfNeeded(save, nowTs)
    local out = {}
    for _, def in ipairs(M.taskDefs()) do
        local progress = M.taskProgress(save, def.id)
        local target = tonumber(def.target) or 0
        out[#out + 1] = {
            id = def.id,
            desc = def.desc,
            target = target,
            progress = progress,
            done = progress >= target,
            claimed = M.isClaimed(save, def.id),
            reward_gold = tonumber(def.reward_gold) or 0,
            reward_item = def.reward_item,
            ratio = target > 0 and (progress / target) or 0,
        }
    end
    return out
end

--- 领取任务奖励。返回 { gold, item } 或 nil,err
function M.claimTask(save, id, nowTs)
    M.resetIfNeeded(save, nowTs)
    local def = defOf(id)
    if not def then return nil, "unknown_task" end
    if not M.isDone(save, id) then return nil, "not_done" end
    if M.isClaimed(save, id) then return nil, "already_claimed" end
    local d = ensureDaily(save)
    d.claimed[id] = true
    local gold = tonumber(def.reward_gold) or 0
    if gold > 0 then Currency.add(save, gold, "daily_task") end
    if def.reward_item then Items.grant(save, def.reward_item, 1) end
    return { gold = gold, item = def.reward_item }
end

--- 是否有可领的任务/签到（红点用）
function M.hasPending(save, nowTs)
    if M.signinInfo(save, nowTs).canClaim then return true end
    for _, t in ipairs(M.taskList(save, nowTs)) do
        if t.done and not t.claimed then return true end
    end
    return false
end

return M
