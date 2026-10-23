-- 门客（T17，PRD §3.4 / §3.5）：招募历史人物，离线产出金币。
-- 护栏（economy_guard.idle_output_ratio_cap）：挂机产出上限 = 8 小时
-- （followers.idle_cap_hours），且日挂机产出不得高于主动游玩产出的 30%，
-- 否则金币贬值、府邸成本失去意义（RISK Failure State ⑤）。
-- 产出/成本/成长全部读 config.followers。

local Config = require("core.config")
local Currency = require("econ.currency")

local M = {}

------------------------------------------------------------------------------
-- 配置读取
------------------------------------------------------------------------------

function M.defs()
    return Config.get("followers.list", {})
end

function M.def(id)
    for _, d in ipairs(M.defs()) do
        if d.id == id then return d end
    end
    return nil
end

function M.maxLevel()
    return Config.num("followers.max_level", 10)
end

--- 挂机封顶秒数（8 小时）
function M.idleCapSec()
    return Config.num("followers.idle_cap_hours", 8) * Config.num("time.sec_per_hour", 3600)
end

function M.outputGrowth()
    return Config.num("followers.output_growth_per_level", 0.25)
end

function M.costGrowth()
    return Config.num("followers.cost_growth_per_level", 1.6)
end

------------------------------------------------------------------------------
-- 存档结构：save.followers = { { id, level, ts } }
------------------------------------------------------------------------------

local function ensure(save)
    if type(save.followers) ~= "table" then save.followers = {} end
    return save.followers
end

function M.owned(save, id)
    for _, f in ipairs(ensure(save)) do
        if f.id == id then return f end
    end
    return nil
end

--- 门客在指定等级的时产出（金币/小时）
function M.outputFor(def, level)
    local base = tonumber(def and def.output) or 0
    local lv = math.max(1, tonumber(level) or 1)
    return base * (1 + M.outputGrowth() * (lv - 1))
end

--- 升到目标等级所需金币（1 级 = 招募价，之后按 cost_growth 指数增长）
function M.costFor(def, targetLevel)
    local base = tonumber(def and def.cost) or 0
    local lv = math.max(1, tonumber(targetLevel) or 1)
    return math.floor(base * (M.costGrowth() ^ (lv - 1)) + 0.5)
end

------------------------------------------------------------------------------
-- 产出
------------------------------------------------------------------------------

--- 全门客合计时产出（金币/小时）
function M.hourlyOutput(save)
    local sum = 0
    for _, f in ipairs(ensure(save)) do
        local def = M.def(f.id)
        if def then
            sum = sum + M.outputFor(def, tonumber(f.level) or 1)
        end
    end
    return sum
end

--- 日挂机产出上限（金币/天）= 时产出 × 封顶小时数
function M.dailyIdleCap(save)
    return M.hourlyOutput(save) * Config.num("followers.idle_cap_hours", 8)
end

--- 待收金币：{ gold, capped, elapsedSec }
--- 护栏①：超过 idle_cap_hours 的部分直接丢弃（时间封顶）
--- 护栏②：若传入 dailyCap（金币封顶，由 econ/economy 导出），累计不超过该值
function M.pending(save, nowTs, dailyCap)
    local now = tonumber(nowTs) or 0
    local rate = M.hourlyOutput(save)
    if rate <= 0 then return { gold = 0, capped = false, elapsedSec = 0 } end
    local cap = M.idleCapSec()
    local secPerHour = Config.num("time.sec_per_hour", 3600)
    local latest = 0
    local total = 0
    local capped = false
    for _, f in ipairs(ensure(save)) do
        local def = M.def(f.id)
        if def then
            local last = tonumber(f.ts) or now
            if last > latest then latest = last end
            local elapsed = now - last
            if elapsed < 0 then elapsed = 0 end
            if elapsed > cap then
                elapsed = cap
                capped = true
            end
            total = total + M.outputFor(def, tonumber(f.level) or 1) * elapsed / secPerHour
        end
    end
    local gold = math.floor(total)
    if dailyCap and gold > dailyCap then
        gold = dailyCap
        capped = true
    end
    return { gold = gold, capped = capped, elapsedSec = now - latest }
end

--- 收取挂机金币（带护栏）。返回 实收金币（0 表示无可收）
function M.collect(save, nowTs, dailyCap)
    local p = M.pending(save, nowTs, dailyCap)
    if p.gold <= 0 then
        -- 无可收也要推进时间戳，避免下次一次性爆量
        for _, f in ipairs(ensure(save)) do f.ts = tonumber(nowTs) or 0 end
        return 0
    end
    local ok = Currency.add(save, p.gold, "follower_idle")
    for _, f in ipairs(ensure(save)) do f.ts = tonumber(nowTs) or 0 end
    if not ok then return 0 end
    return p.gold
end

------------------------------------------------------------------------------
-- 招募 / 升级
------------------------------------------------------------------------------

--- 招募（首次）。返回 entry 或 nil,err
function M.recruit(save, id, nowTs)
    local def = M.def(id)
    if not def then return nil, "unknown_follower" end
    if M.owned(save, id) then return nil, "already_owned" end
    local cost = M.costFor(def, 1)
    local ok, err = Currency.spend(save, cost, "follower_recruit")
    if not ok then return nil, err or "insufficient" end
    local entry = { id = id, level = 1, ts = tonumber(nowTs) or 0 }
    local list = ensure(save)
    list[#list + 1] = entry
    return entry
end

--- 升级（已满级返回 nil,"max_level"）。返回 新等级 或 nil,err
function M.upgrade(save, id)
    local def = M.def(id)
    if not def then return nil, "unknown_follower" end
    local f = M.owned(save, id)
    if not f then return nil, "not_owned" end
    local lv = tonumber(f.level) or 1
    if lv >= M.maxLevel() then return nil, "max_level" end
    local cost = M.costFor(def, lv + 1)
    local ok, err = Currency.spend(save, cost, "follower_upgrade")
    if not ok then return nil, err or "insufficient" end
    f.level = lv + 1
    return f.level
end

------------------------------------------------------------------------------
-- 展示
------------------------------------------------------------------------------

--- 门客列表（含未招募的），供 UI 直出
function M.list(save)
    local out = {}
    local ownedMap = {}
    for _, f in ipairs(ensure(save)) do ownedMap[f.id] = f end
    for _, def in ipairs(M.defs()) do
        local f = ownedMap[def.id]
        local lv = f and (tonumber(f.level) or 1) or 0
        out[#out + 1] = {
            id = def.id,
            name = def.name,
            kind = def.kind,
            level = lv,
            owned = f ~= nil,
            output = f and M.outputFor(def, lv) or M.outputFor(def, 1),
            nextCost = f and (lv >= M.maxLevel() and nil or M.costFor(def, lv + 1)) or M.costFor(def, 1),
            isMax = f ~= nil and lv >= M.maxLevel(),
        }
    end
    return out
end

--- 全部门客满级所需金币总额（经济护栏用）
function M.totalCost()
    local sum = 0
    for _, def in ipairs(M.defs()) do
        for lv = 1, M.maxLevel() do
            sum = sum + M.costFor(def, lv)
        end
    end
    return sum
end

return M
