-- 内购与付费上限（T22，PRD §5）。
-- 纪律：①未实名不得付费；②按年龄分段限制单笔与月度额度；
--       ③所有金额来自 config.iap；④发货走 econ/currency，不在这里改公式。
-- ⚠️ 边界：真实支付渠道（TapTap 支付 / 微信 / 支付宝）与 SKU 后台配置属平台侧工作，
--   本模块完成「商品表 + 限额判定 + 发货 + 流水记录」，交付文档列为待接入项。

local Config = require("core.config")
local Time = require("system.time")
local Currency = require("econ.currency")
local Compliance = require("system.compliance")

local M = {}

------------------------------------------------------------------------------
-- 商品
------------------------------------------------------------------------------

function M.products()
    return Config.get("iap.products", {})
end

function M.product(id)
    for _, p in ipairs(M.products()) do
        if p.id == id then return p end
    end
    return nil
end

------------------------------------------------------------------------------
-- 流水与限额
------------------------------------------------------------------------------

local function ensureSpend(save, nowTs)
    if type(save.iap_spend) ~= "table" then save.iap_spend = {} end
    local month = os.date("%Y%m", tonumber(nowTs) or Time.now())
    if save.iap_spend.month ~= month then
        save.iap_spend = { month = month, amount = 0 }
    end
    return save.iap_spend
end

--- 本月已消费（元）
function M.monthSpent(save, nowTs)
    if not save then return 0 end
    return tonumber(ensureSpend(save, nowTs).amount) or 0
end

function M.limit(save)
    return Compliance.paymentLimit(save)
end

--- 是否可以购买。返回 ok, reason
--- reason: "realname_required" | "unknown_product" | "blocked_by_age"
---       | "over_per_payment" | "over_monthly"
function M.canBuy(save, productId, nowTs)
    if not Compliance.isVerified(save) then return false, "realname_required" end
    local p = M.product(productId)
    if not p then return false, "unknown_product" end
    local price = tonumber(p.price_cny) or 0
    local lim = M.limit(save)
    if lim.per_payment_cny <= 0 then return false, "blocked_by_age" end
    if price > lim.per_payment_cny then return false, "over_per_payment" end
    if M.monthSpent(save, nowTs) + price > lim.monthly_cny then return false, "over_monthly" end
    return true
end

--- 拒绝原因 → 玩家可读文案
function M.reasonText(save, reason)
    local lim = M.limit(save)
    if reason == "realname_required" then
        return "完成实名认证后才能购买"
    elseif reason == "blocked_by_age" then
        return "当前年龄段不可进行内购"
    elseif reason == "over_per_payment" then
        return string.format("单笔限额 %d 元，该商品超出限制", lim.per_payment_cny or 0)
    elseif reason == "over_monthly" then
        return string.format("本月累计限额 %d 元，已无法购买", lim.monthly_cny or 0)
    elseif reason == "unknown_product" then
        return "商品不存在"
    end
    return "暂时无法购买"
end

------------------------------------------------------------------------------
-- 购买
------------------------------------------------------------------------------

--- 下单并发货（真实渠道回调应调用本函数完成发货）。
--- 返回 { product, gold, no_ad } 或 nil,reason
function M.purchase(save, productId, nowTs)
    local ok, reason = M.canBuy(save, productId, nowTs)
    if not ok then return nil, reason end
    local p = M.product(productId)
    local price = tonumber(p.price_cny) or 0

    -- 记录流水（先记后发，避免发放成功但流水丢失导致限额失效）
    local spend = ensureSpend(save, nowTs)
    spend.amount = (tonumber(spend.amount) or 0) + price

    local gold = tonumber(p.gold) or 0
    if gold > 0 then Currency.add(save, gold, "iap_" .. tostring(p.id)) end
    if p.id == "no_ad" then save.no_ad = true end

    return { product = p, gold = gold, no_ad = (p.id == "no_ad") }
end

--- 是否已购去广告
function M.isNoAd(save)
    return save and save.no_ad == true
end

return M
