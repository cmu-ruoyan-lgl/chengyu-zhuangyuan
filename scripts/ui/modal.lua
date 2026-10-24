-- 统一弹窗组件（S8）：所有「操作结果类提示」的单一出口。
-- 设计纪律（避免重蹈文字/布局问题）：
--   ① 正文一律 W.wrapLines 手动断行（Label 不自动换行，S6-3 教训）；
--   ② 按钮用 Panel+onClick（Button 单行 auto-fit 会弄乱复合内容，S6-1 教训）；
--   ③ 卡片宽度定 78%，文字全部 flexShrink=1 + 居中，任何视口不溢出；
--   ④ 同一时刻只允许一个弹窗（新的顶掉旧的）。
-- 高频即时反馈（填字对错、成语达成）不走这里——那是 play 页 banner 的职责，
-- 弹窗会打断连击节奏。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local W = require("ui.widgets")

local Modal = {}

local active_ = nil

local c = W.c

--- 关闭当前弹窗（若有）
function Modal.close()
    if active_ then
        local root = UI.GetRoot()
        if root and root.RemoveChild then
            pcall(function() root:RemoveChild(active_) end)
        end
        active_ = nil
    end
end

--- 信息弹窗：标题 + 正文 + 主按钮
--- opts: { title, message, buttonText, onClose }
function Modal.alert(opts)
    opts = opts or {}
    Modal.close()

    local title = tostring(opts.title or "提示")
    local message = W.wrapLines(tostring(opts.message or ""), 14)
    local buttonText = tostring(opts.buttonText or "知道了")

    local btn = UI.Panel {
        width = "72%",
        marginTop = 28,
        paddingVertical = 15,
        borderRadius = 30,
        backgroundGradient = { direction = "to-bottom", from = c("jade"), to = c("jade_deep") },
        borderWidth = 2,
        borderColor = c("jade_deep"),
        boxShadow = W.shadow(14, 5, 120, "jade_deep"),
        justifyContent = "center",
        alignItems = "center",
        onClick = function()
            Modal.close()
            if type(opts.onClose) == "function" then opts.onClose() end
        end,
        children = { UI.Label {
            text = buttonText,
            fontSize = Theme.font("toolbar", 28),
            fontColor = c("cream"),
            fontWeight = "bold",
            textAlign = "center",
            width = "100%",
            flexShrink = 1,
        } },
    }

    local card = UI.Panel {
        width = "78%",
        borderRadius = 32,
        backgroundColor = c("panel"),
        borderWidth = 3,
        borderColor = c("panel_edge"),
        boxShadow = W.shadow(34, 14, 180),
        flexDirection = "column",
        alignItems = "center",
        paddingHorizontal = 30,
        paddingVertical = 34,
        children = {
            -- 顶部装饰圆点
            UI.Panel {
                width = 54, height = 54,
                borderRadius = 27,
                backgroundGradient = { direction = "to-bottom", from = c("jade"), to = c("jade_deep") },
                boxShadow = W.shadow(10, 4, 90, "jade_deep"),
                justifyContent = "center",
                alignItems = "center",
                children = { UI.Label {
                    text = "i",
                    fontSize = Theme.font("toolbar", 28),
                    fontColor = c("cream"),
                    fontWeight = "bold",
                    textAlign = "center",
                    width = "100%",
                } },
            },
            UI.Label {
                text = title,
                fontSize = Theme.font("toolbar", 28) * 1.15,
                fontColor = c("ink"),
                fontWeight = "bold",
                textAlign = "center",
                width = "100%",
                marginTop = 16,
                flexShrink = 1,
            },
            UI.Panel {
                width = "40%",
                height = 2,
                backgroundColor = c("panel_edge"),
                marginTop = 14,
            },
            UI.Label {
                text = message,
                fontSize = Theme.font("caption", 24),
                fontColor = c("ink_dim"),
                textAlign = "center",
                width = "100%",
                marginTop = 16,
                flexShrink = 1,
            },
            btn,
        },
    }

    local overlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = c("overlay"),
        justifyContent = "center",
        alignItems = "center",
        -- 吃掉点击，不穿透到底层页面；点遮罩不关闭（结果类提示要求玩家明确确认）
        onClick = function() end,
        children = { card },
    }

    local root = UI.GetRoot()
    if not root then
        print("[modal] 无根节点，弹窗降级为日志: " .. title .. " / " .. message)
        return false
    end
    root:AddChild(overlay)
    active_ = overlay

    W.anim(card, {
        keyframes = {
            [0]   = { opacity = 0, scale = 0.82, translateY = 26 },
            [0.6] = { opacity = 1, scale = 1.04, translateY = -4 },
            [1]   = { opacity = 1, scale = 1, translateY = 0 },
        },
        duration = 0.28,
        easing = "easeOut",
    })
    return true
end

--- 是否有弹窗在显示
function Modal.isActive()
    return active_ ~= nil
end

return Modal
