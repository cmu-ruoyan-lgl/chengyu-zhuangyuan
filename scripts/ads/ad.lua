-- 激励视频广告点位（T21，PRD §3.5/§5）。
-- 纪律：①每个点位必须有「免费出口」（玩家可随时关闭且不损失任何东西）；
--       ②未成年人不投放个性化广告（ad.personalized_for_minor = false）；
--       ③冷却时间防刷；④奖励发放走 econ 模块，不在这里改金币公式。
-- ⚠️ 边界：真实广告 SDK（穿山甲/优量汇等）接入属平台侧工作，本模块提供
--   「点位配置 + 冷却 + 发奖」的完整逻辑，播放环节由 ui/admodal 占位模拟，
--   交付文档中列为待接入项。

local Config = require("core.config")
local Time = require("system.time")
local Items = require("econ.items")
local Stamina = require("econ.stamina")
local Compliance = require("system.compliance")

local M = {}

------------------------------------------------------------------------------
-- 点位
------------------------------------------------------------------------------

function M.placements()
    return Config.get("ad.placements", {})
end

function M.placement(id)
    for _, p in ipairs(M.placements()) do
        if p.id == id then return p end
    end
    return nil
end

--- 免费出口：任何点位都必须允许随时关闭（缺失即视为缺陷，默认 true 也要求显式配置）
function M.hasFreeExit(id)
    local p = M.placement(id)
    if not p then return false end
    return p.free_exit ~= false
end

--- 所有点位是否都合规（有免费出口）
function M.allHaveFreeExit()
    for _, p in ipairs(M.placements()) do
        if p.free_exit == false then return false end
    end
    return true
end

function M.personalizedForMinor()
    return Config.get("ad.personalized_for_minor", false) == true
end

------------------------------------------------------------------------------
-- 冷却
------------------------------------------------------------------------------

local function ensureState(save)
    if type(save.ad_state) ~= "table" then save.ad_state = { last_ts = {}, levels_since = 0 } end
    if type(save.ad_state.last_ts) ~= "table" then save.ad_state.last_ts = {} end
    if type(save.ad_state.levels_since) ~= "number" then save.ad_state.levels_since = 0 end
    return save.ad_state
end

function M.cooldownSec()
    return Config.num("ad.cooldown_sec", 30)
end

--- 是否可展示（冷却 + 去广告特权 + 未成年人个性化限制不影响激励视频本身）
function M.canShow(save, id, nowTs)
    if not M.placement(id) then return false, "unknown_placement" end
    if save and save.no_ad then return false, "no_ad_purchased" end
    local st = ensureState(save)
    local last = tonumber(st.last_ts[id]) or 0
    local now = tonumber(nowTs) or Time.now()
    if now - last < M.cooldownSec() then return false, "cooldown" end
    return true
end

function M.noteShown(save, id, nowTs)
    local st = ensureState(save)
    st.last_ts[id] = tonumber(nowTs) or Time.now()
    return st.last_ts[id]
end

------------------------------------------------------------------------------
-- 奖励
------------------------------------------------------------------------------

--- 发放广告奖励。返回 { kind, amount, item } 或 nil,err
function M.grant(save, id, nowTs)
    local p = M.placement(id)
    if not p then return nil, "unknown_placement" end
    M.noteShown(save, id, nowTs)
    if p.reward_kind == "stamina" then
        Stamina.addByAd(save)
        return { kind = "stamina", amount = tonumber(p.reward_amount) or 0 }
    elseif p.reward_kind == "item" then
        local n = tonumber(p.reward_amount) or 1
        Items.grant(save, p.reward_item, n)
        return { kind = "item", item = p.reward_item, amount = n }
    end
    return nil, "unknown_reward_kind"
end

--- 奖励文案（UI 直接展示）
function M.rewardText(id)
    local p = M.placement(id)
    if not p then return "" end
    if p.reward_kind == "stamina" then
        return string.format("体力 +%d", tonumber(p.reward_amount) or 0)
    elseif p.reward_kind == "item" then
        local name = Config.get("items.name." .. tostring(p.reward_item), p.reward_item)
        return string.format("%s ×%d", tostring(name), tonumber(p.reward_amount) or 1)
    end
    return ""
end

------------------------------------------------------------------------------
-- 插屏（关间）
------------------------------------------------------------------------------

function M.interstitialEveryLevels()
    return Config.num("ad.interstitial_every_levels", 5)
end

--- 通关计数 + 是否该弹插屏
function M.noteLevelCleared(save)
    local st = ensureState(save)
    st.levels_since = (tonumber(st.levels_since) or 0) + 1
    return st.levels_since >= M.interstitialEveryLevels()
end

function M.resetInterstitial(save)
    local st = ensureState(save)
    st.levels_since = 0
end

--- 未成年人不得个性化推荐（埋点/文案用）
function M.shouldPersonalize(save)
    return M.personalizedForMinor() and not Compliance.isMinor(save)
end

return M
