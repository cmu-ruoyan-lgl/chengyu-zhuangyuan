-- 激励视频播放弹窗（T21）。
-- 纪律：①「免费出口」——任何时刻都可点「关闭」退出，且**不发放奖励、不扣分、不惩罚**；
--       ②奖励只在播放完成后发放（Game.grantAd）；
--       ③未成年人不做个性化投放（config.ad.personalized_for_minor=false）。
-- ⚠️ 边界：真实广告 SDK 未接入，这里用倒计时模拟播放过程（mock_duration_sec），
--   接入时只需把 AD.finish() 的触发点换成 SDK 的 onAdComplete 回调。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local W = require("ui.widgets")
local Ticker = require("ui.ticker")

local AD = {}

local st = {
    active = false,
    id = nil,
    endsAt = 0,
    overlay = nil,
    label = nil,
    onGranted = nil,
    onClose = nil,
    hookTried = false,
}

------------------------------------------------------------------------------
-- 逐帧倒计时
------------------------------------------------------------------------------

--- 倒计时由 os.clock 驱动（不依赖引擎 dt，避免切后台后跳变）
function AD.tick()
    if not st.active then return end
    local left = math.max(0, st.endsAt - os.clock())
    if st.label then
        st.label:SetStyle({ text = string.format("广告播放中… %d", math.ceil(left)) })
    end
    if left <= 0 then
        AD.finish()
    end
end

local function hookTick()
    Ticker.add(AD.tick)
end

------------------------------------------------------------------------------
-- 生命周期
------------------------------------------------------------------------------

function AD.close()
    if st.overlay then
        local root = UI.GetRoot()
        if root and root.RemoveChild then
            pcall(function() root:RemoveChild(st.overlay) end)
        end
    end
    st.active = false
    st.overlay = nil
    st.label = nil
    st.id = nil
end

--- 播放完成 → 发奖 → 关闭
function AD.finish()
    if not st.active then return end
    local id = st.id
    local cb = st.onGranted
    AD.close()
    local reward = Game.grantAd(id)
    if type(cb) == "function" then cb(reward) end
end

------------------------------------------------------------------------------
-- 展示
------------------------------------------------------------------------------

--- opts: { onGranted(reward), onClose(), onDenied(reason) }
function AD.show(placementId, opts)
    opts = opts or {}
    local ok, reason = Game.canShowAd(placementId)
    if not ok then
        if type(opts.onDenied) == "function" then opts.onDenied(reason) end
        return false, reason
    end

    AD.close()
    hookTick()

    local dur = Config.num("ad.mock_duration_sec", 5)
    local placement = nil
    for _, p in ipairs(Game.adPlacements()) do
        if p.id == placementId then placement = p end
    end

    st.id = placementId
    st.endsAt = os.clock() + dur
    st.onGranted = opts.onGranted
    st.onClose = opts.onClose
    st.active = true

    st.label = UI.Label {
        text = string.format("广告播放中… %d", dur),
        fontSize = Theme.font("toolbar", 28),
        fontColor = W.c("text_light"),
        textAlign = "center",
        fontWeight = "bold",
        width = "100%",
    }

    local card = UI.Panel {
        width = "84%",
        borderRadius = 32,
        backgroundColor = W.c("chip_bg"),
        borderWidth = 3,
        borderColor = W.c("chip_edge"),
        boxShadow = W.shadow(30, 12, 170),
        paddingHorizontal = 30,
        paddingVertical = 34,
        alignItems = "center",
        children = {
            UI.Label {
                text = (placement and placement.name) or "广告",
                fontSize = Theme.font("title", 56) * 0.7,
                fontColor = W.c("gold"),
                fontWeight = "bold",
                textAlign = "center",
            },
            UI.Label {
                text = "看完可得：" .. Game.adRewardText(placementId),
                fontSize = Theme.font("toolbar", 28),
                fontColor = W.c("text_light"),
                textAlign = "center",
                marginTop = 12,
            },
            st.label,
            UI.Label {
                text = "（当前为模拟播放，正式版接入广告 SDK）",
                fontSize = Theme.font("caption", 24),
                fontColor = W.c("text_light_dim"),
                textAlign = "center",
                marginTop = 8,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                marginTop = 26,
                children = {
                    -- 免费出口：随时可关，不发奖也不惩罚
                    W.pillButton("关闭（不领奖）", function()
                        local cb = st.onClose
                        AD.close()
                        if type(cb) == "function" then cb() end
                    end, {
                        gradient = {
                            direction = "to-bottom",
                            from = W.c("panel_edge"),
                            to = W.c("ink_dim"),
                        },
                        fg = W.c("cream"),
                    }),
                },
            },
        },
    }

    st.overlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = W.c("overlay"),
        justifyContent = "center",
        alignItems = "center",
        children = { card },
    }

    local root = UI.GetRoot()
    if not root then return false, "no_root" end
    root:AddChild(st.overlay)
    return true
end

return AD
