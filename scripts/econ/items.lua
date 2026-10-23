-- 道具系统（T14，PRD §3.6）。
-- 五种：提示卡 / 撤销（无限）/ 洗牌 / 跳过卡 / 双倍卡。
-- 全部价格与限制读 config（items.* / hints.*），本模块不持有状态，
-- 只对传入的 save 做纯计算与变更，便于离线单测。

local Config = require("core.config")
local Currency = require("econ.currency")

local M = {}

local KEYS = { "hint", "shuffle", "skip", "double" }

local function itemTable(save)
    if type(save.items) ~= "table" then save.items = {} end
    for _, k in ipairs(KEYS) do
        if type(save.items[k]) ~= "number" then save.items[k] = 0 end
    end
    return save.items
end

--- 道具数量
function M.count(save, key)
    return itemTable(save)[key] or 0
end

--- 加道具（广告/签到/内购发放）
function M.grant(save, key, amount)
    if not key then return 0 end
    local t = itemTable(save)
    t[key] = (tonumber(t[key]) or 0) + (tonumber(amount) or 0)
    return t[key]
end

--- 扣道具
function M.consumeItem(save, key, amount)
    local t = itemTable(save)
    local have = tonumber(t[key]) or 0
    local need = tonumber(amount) or 1
    if have < need then return false, "not_enough_item" end
    t[key] = have - need
    return true
end

------------------------------------------------------------------------------
-- 提示
------------------------------------------------------------------------------

--- 今日剩余免费提示（每日重置由 system/daily 负责清零 hints_used_today）
function M.freeHintsLeft(save)
    local free = Config.num("hints.free_per_day", 3)
    local used = tonumber(save.hints_used_today) or 0
    return math.max(0, free - used)
end

--- 用一次提示：优先免费额度 → 提示卡 → 金币购买
--- 返回 ok, source(免费/道具/金币), err
function M.useHint(save)
    local maxPerLevel = Config.num("hints.max_per_level", 3)
    -- 单关上限由 session 侧判定，这里只看全局资源
    if M.freeHintsLeft(save) > 0 then
        save.hints_used_today = (tonumber(save.hints_used_today) or 0) + 1
        return true, "free"
    end
    if M.count(save, "hint") > 0 then
        M.consumeItem(save, "hint", 1)
        return true, "item"
    end
    local price = Config.num("items.hint_price_gold", Config.num("hints.price_gold", 20))
    local ok, err = Currency.spend(save, price, "hint")
    if ok then return true, "gold" end
    return false, nil, err or "no_resource"
end

--- 提示是否还有可用途径（用于 UI 是否展示「看广告补提示」）
function M.hintAvailable(save)
    return M.freeHintsLeft(save) > 0 or M.count(save, "hint") > 0
        or Currency.balance(save) >= Config.num("items.hint_price_gold", 20)
end

------------------------------------------------------------------------------
-- 洗牌 / 跳过 / 双倍
------------------------------------------------------------------------------

--- 洗牌：道具优先，否则金币
function M.useShuffle(save)
    if M.count(save, "shuffle") > 0 then
        M.consumeItem(save, "shuffle", 1)
        return true, "item"
    end
    local price = Config.num("items.shuffle_price", 15)
    local ok, err = Currency.spend(save, price, "shuffle")
    if ok then return true, "gold" end
    return false, nil, err or "no_resource"
end

--- 跳过卡：道具优先，否则金币；不产金币（防刷，PRD §3.6）
function M.useSkip(save)
    if M.count(save, "skip") > 0 then
        M.consumeItem(save, "skip", 1)
        return true, "item"
    end
    local price = Config.num("items.skip_price", 30)
    local ok, err = Currency.spend(save, price, "skip")
    if ok then return true, "gold" end
    return false, nil, err or "no_resource"
end

--- 跳过结算：金币产出按 skip_gold_ratio（默认 0）
function M.skipRewardRatio()
    return Config.num("items.skip_gold_ratio", 0)
end

--- 双倍卡：生效至 nowTs + duration
function M.activateDouble(save, nowTs)
    if M.count(save, "double") > 0 then
        M.consumeItem(save, "double", 1)
    end
    local dur = Config.num("items.double_duration_sec", 1800)
    local base = math.max(tonumber(save.double_until_ts) or 0, tonumber(nowTs) or 0)
    save.double_until_ts = base + dur
    return save.double_until_ts
end

--- 双倍卡是否生效
function M.doubleActive(save, nowTs)
    local until_ts = tonumber(save.double_until_ts) or 0
    return until_ts > (tonumber(nowTs) or 0)
end

--- 双倍剩余秒数
function M.doubleLeft(save, nowTs)
    local until_ts = tonumber(save.double_until_ts) or 0
    return math.max(0, until_ts - (tonumber(nowTs) or 0))
end

------------------------------------------------------------------------------
-- 撤销（无限，PRD §3.6）
------------------------------------------------------------------------------

function M.undoUnlimited()
    return Config.get("items.undo_unlimited", true) ~= false
end

--- 广告发放数量（每个点位一次给几张）
function M.adGrant(key)
    return Config.num("items.ad_grant." .. tostring(key), 1)
end

return M
