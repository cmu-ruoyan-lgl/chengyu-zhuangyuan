-- 商店页（T22 内购 + T21 广告点位）。
-- 只读 Game.iapProducts() / Game.adPlacements()，购买与领奖都走逻辑层。
-- 未成年人的单笔/月度限额由 econ/iap 判定，本页只负责把拒绝原因说清楚。
-- ⚠️ 真实支付渠道与 SKU 后台配置属平台侧工作（待接入项）。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local W = require("ui.widgets")

local Shop = {}

local msg_ = ""

local function c(key, default)
    return W.c(key, default)
end

--- 金额文案（成年人限额为 math.huge，不能直接 %d）
local function moneyText(n)
    local v = tonumber(n) or 0
    if v >= 1e9 then return "不限" end
    return string.format("%d", math.floor(v))
end

local function fs(key, default)
    return Theme.font(key, default)
end

local function row(title, sub, btnText, onTap, opts)
    opts = opts or {}
    local btn = nil
    if btnText then
        btn = W.pillButton(btnText, onTap, {
            fontSize = fs("caption", 24),
            grow = 0,
            paddingVertical = 10,
            paddingHorizontal = 26,
            marginHorizontal = 0,
            gradient = opts.gradient,
            fg = opts.fg,
            glow = opts.glow,
            disabled = opts.disabled,
        })
    end
    local kids = {
        UI.Panel {
            flexGrow = 1,
            flexShrink = 1,
            flexDirection = "column",
            children = {
                UI.Label {
                    text = title,
                    fontSize = fs("toolbar", 28),
                    fontColor = c("ink"),
                    fontWeight = "bold",
                    width = "100%",
                },
            },
        },
    }
    if sub then
        kids[1]:AddChild(UI.Label {
            text = sub,
            fontSize = fs("caption", 24),
            fontColor = opts.subColor or c("ink_dim"),
            width = "100%",
            marginTop = 4,
        })
    end
    if btn then kids[#kids + 1] = btn end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        marginTop = 12,
        children = kids,
    }
end

local function act(msg)
    msg_ = msg
    Shop.mount()
end

local function iapSection()
    local kids = {}
    local limit = Game.iapLimit()
    local spent = Game.iapMonthSpent()
    local limitText = (limit.monthly_cny or 0) > 0
        and string.format("本月已消费 %s/%s 元，单笔上限 %s 元",
            moneyText(spent), moneyText(limit.monthly_cny), moneyText(limit.per_payment_cny))
        or "当前年龄段不可内购"
    for _, p in ipairs(Game.iapProducts()) do
        local sub = string.format("￥%d", p.price_cny or 0)
        if (tonumber(p.gold) or 0) > 0 then
            sub = sub .. string.format("  金币 %d", p.gold)
        end
        if p.id == "no_ad" then
            sub = sub .. "  永久去广告"
        end
        if not p.canBuy and p.reasonText ~= "" then
            sub = sub .. "  （" .. p.reasonText .. "）"
        end
        kids[#kids + 1] = row(p.name, sub,
            (p.id == "no_ad" and Game.isNoAd()) and "已拥有" or string.format("￥%d 购买", p.price_cny or 0),
            function()
                local res, reason, text = Game.buy(p.id)
                act(res and string.format("购买成功：%s（金币 +%d）", p.name, res.gold or 0)
                    or ("无法购买：" .. tostring(text or reason)))
            end,
            { disabled = not p.canBuy or (p.id == "no_ad" and Game.isNoAd()),
              subColor = p.canBuy and c("ink_dim") or c("seal_deep") })
    end
    kids[#kids + 1] = UI.Label {
        text = limitText,
        fontSize = fs("caption", 24),
        fontColor = c("ink_dim"),
        width = "100%",
        marginTop = 10,
    }
    return W.sectionCard("金币充值", kids, { subtitle = "未成年人按国家规定限额" })
end

local function adSection()
    local kids = {}
    for _, p in ipairs(Game.adPlacements()) do
        local ok, reason = Game.canShowAd(p.id)
        local sub = "看完可得：" .. Game.adRewardText(p.id)
        if not ok then
            sub = sub .. "  （" .. (reason == "cooldown" and "冷却中" or
                (reason == "no_ad_purchased" and "已购去广告" or "暂不可用")) .. "）"
        end
        kids[#kids + 1] = row(p.name, sub, ok and "观看" or "不可观看", function()
            local ok2, AD = pcall(require, "ui.admodal")
            if not (ok2 and AD and AD.show) then
                act("广告模块不可用")
                return
            end
            AD.show(p.id, {
                onGranted = function(reward)
                    act(reward and ("奖励已发放：" .. Game.adRewardText(p.id)) or "发放失败")
                end,
                onDenied = function(reason2)
                    act("暂时无法观看：" .. tostring(reason2))
                end,
            })
        end, { disabled = not ok, gradient = {
            direction = "to-bottom", from = c("jade"), to = c("jade_deep") },
            fg = c("cream"), glow = "jade_deep" })
    end
    return W.sectionCard("看广告领奖励", kids, { subtitle = "随时可关闭，不领奖也不损失" })
end

function Shop.mount()
    local status = UI.Label {
        text = msg_ or "",
        fontSize = fs("caption", 24),
        fontColor = c("gold"),
        textAlign = "center",
        width = "100%",
        flexShrink = 1,
    }
    local body = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = true,
        paddingHorizontal = 24,
        paddingVertical = 10,
        children = {
            status,
            iapSection(),
            adSection(),
            W.sectionCard("说明", {
                UI.Label {
                    text = "本版支付为本地模拟，正式上线需接入 TapTap/第三方支付并配置 SKU；"
                        .. "广告需接入聚合 SDK 后方可真实播放。",
                    fontSize = fs("caption", 24),
                    fontColor = c("ink_dim"),
                    width = "100%",
                },
            }),
        },
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = c("bg_top"),
        backgroundImage = "Textures/bg_main.png",
        backgroundFit = "cover",
        children = {
            W.pageHeader("商店", {
                W.chip("金币 " .. tostring(Game.gold()), {
                    dotColor = c("coin"), fg = c("gold"),
                }),
            }, function()
                local ok, Court = pcall(require, "ui.pages.court")
                if ok and Court and Court.mount then Court.mount() end
            end),
            body,
        },
    }
    UI.SetRoot(root, true)
    return root
end

return Shop
