-- 府邸页（S2 系统总入口）：官职 / 府邸 / 门客 / 签到 / 每日任务 / 成就 / 挑战 / 图鉴。
-- 严格分层：只读 Game 暴露的状态并发指令，不持有任何游戏状态。
-- 交互反馈策略：操作后重挂本页（数据即视图），并在状态条回显结果，
-- 避免在滚动页里维护几十个局部引用。

local UI = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Config = require("core.config")
local Game = require("system.game")
local W = require("ui.widgets")

local Court = {}

--- 结果类提示统一弹窗（S8）
local function alert(title, message, onClose)
    local ok, Modal = pcall(require, "ui.modal")
    if ok and Modal and Modal.alert then
        Modal.alert({ title = title, message = message, onClose = onClose })
    else
        print("[court] " .. tostring(title) .. ": " .. tostring(message))
        if onClose then onClose() end
    end
end

local function c(key, default)
    return W.c(key, default)
end

--- 金额文案（成年人的限额是 math.huge，不能直接 %d）
local function moneyText(n)
    local v = tonumber(n) or 0
    if v >= 1e9 then return "不限" end
    return string.format("%d", math.floor(v))
end

local function fs(key, default)
    return Theme.font(key, default)
end

------------------------------------------------------------------------------
-- 通用行：左信息 + 右按钮
------------------------------------------------------------------------------

local function actionRow(leftKids, buttonText, onTap, opts)
    opts = opts or {}
    local btn = nil
    if buttonText then
        btn = W.pillButton(buttonText, onTap, {
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
    local left = UI.Panel {
        flexGrow = 1,
        flexShrink = 1,
        flexDirection = "column",
        children = leftKids,
    }
    local kids = { left }
    if btn then kids[#kids + 1] = btn end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        marginTop = 12,
        paddingTop = 12,
        borderWidth = 0,
        children = kids,
    }
end

local function line1(text, bold, colorKey)
    return UI.Label {
        text = text,
        fontSize = fs("toolbar", 28),
        fontColor = c(colorKey or "ink"),
        fontWeight = bold and "bold" or nil,
        width = "100%",
        flexShrink = 1,
    }
end

local function line2(text)
    return UI.Label {
        text = text,
        fontSize = fs("caption", 24),
        fontColor = c("ink_dim"),
        width = "100%",
        marginTop = 4,
        flexShrink = 1,
    }
end

--- 操作后弹窗回显，关闭弹窗时重挂刷新数据（数据即视图）
local function act(msg, fn)
    local ok, result = pcall(fn)
    local title = ok and "操作成功" or "操作失败"
    local text = ok and tostring(msg or "") or tostring(result)
    alert(title, text, function() Court.mount() end)
end

------------------------------------------------------------------------------
-- 分区
------------------------------------------------------------------------------

local function rankSection()
    local r = Game.rank()
    local kids = {
        actionRow({ line1("当前官职：" .. tostring(r.name), true),
                    line2(string.format("累计通关 %d 关", r.levelsPassed or 0)) },
            "领俸禄 " .. tostring(r.salary or 0),
            function()
                local gold, err = Game.claimSalary()
                act(gold and ("俸禄到账 +" .. tostring(gold) .. " 金币")
                    or (err == "already_claimed" and "今日俸禄已领" or "领取失败"),
                    function() return gold end)
            end),
    }
    if r.next then
        kids[#kids + 1] = W.progressBar(r.ratio)
        kids[#kids + 1] = line2(string.format("距「%s」还需 %d 关（%d/%d）",
            tostring(r.next.name), math.max(0, (r.need or 0) - (r.have or 0)),
            r.have or 0, r.need or 0))
    else
        kids[#kids + 1] = line2("已至最高阶：状元")
    end
    return W.sectionCard("官职", kids, { subtitle = "通关越多，官越大" })
end

local function manorSection()
    local m = Game.manor()
    local kids = {
        actionRow({ line1("府邸：" .. tostring(m.name), true),
                    line2(string.format("结算金币加成 +%d%%", math.floor((m.ratio or 0) * 100 + 0.5))) },
            m.isMax and "已满级" or ("升级 " .. tostring(m.nextCost or 0)),
            function()
                local lv, err = Game.upgradeManor()
                act(lv and ("府邸升至 " .. tostring(Game.manor().name))
                    or (err == "insufficient" and "金币不足" or "无法升级"),
                    function() return lv end)
            end,
            { disabled = m.isMax or not m.canUpgrade }),
    }
    if not m.isMax then
        kids[#kids + 1] = line2(string.format("当前金币 %d / 需要 %d",
            Game.gold(), m.nextCost or 0))
    end
    return W.sectionCard("府邸", kids, { subtitle = "加成作用于每关结算" })
end

local function followerSection()
    local pending = Game.idlePending()
    local kids = {
        actionRow({ line1("挂机收益", true),
                    line2(string.format("可收取 %d 金币（%s）",
                        pending.gold or 0, pending.capped and "已达上限" or "累积中")) },
            (pending.gold or 0) > 0 and ("收取 " .. tostring(pending.gold)) or "暂无",
            function()
                local gold = Game.collectIdle()
                act(gold > 0 and ("收取 +" .. tostring(gold) .. " 金币") or "暂无可收",
                    function() return gold end)
            end,
            { disabled = (pending.gold or 0) <= 0, gradient = {
                direction = "to-bottom", from = c("jade"), to = c("jade_deep") },
              fg = c("cream"), glow = "jade_deep" }),
    }
    for _, f in ipairs(Game.followers()) do
        local title = string.format("%s（%s） Lv.%d", f.name, f.kind or "", f.level or 0)
        local sub = string.format("产出 %d 金币/小时%s",
            math.floor(f.output or 0), f.isMax and "（已满级）" or "")
        local btnText, disabled
        if not f.owned then
            btnText = "招募 " .. tostring(f.nextCost or 0)
            disabled = Game.gold() < (f.nextCost or 0)
        elseif f.isMax then
            btnText = "满级"
            disabled = true
        else
            btnText = "升级 " .. tostring(f.nextCost or 0)
            disabled = Game.gold() < (f.nextCost or 0)
        end
        kids[#kids + 1] = actionRow({ line1(title), line2(sub) }, btnText, function()
            if f.owned then
                local lv, err = Game.upgradeFollower(f.id)
                act(lv and (f.name .. " 升至 Lv." .. tostring(lv))
                    or (err == "insufficient" and "金币不足" or "无法升级"),
                    function() return lv end)
            else
                local entry, err = Game.recruitFollower(f.id)
                act(entry and ("招募成功：" .. f.name)
                    or (err == "insufficient" and "金币不足" or "无法招募"),
                    function() return entry end)
            end
        end, { disabled = disabled })
    end
    return W.sectionCard("门客", kids, { subtitle = "离线也在挣钱（8 小时封顶）" })
end

local function signinSection()
    local s = Game.signinInfo()
    local reward = s.reward or {}
    local kids = {
        actionRow({ line1(string.format("连续签到 %d 天（第 %d/%d 天奖励）",
                s.streak or 0, s.dayIndex or 1, Config.num("signin.cycle_days", 7)), true),
                    line2(string.format("今日奖励：%d 金币%s",
                        tonumber(reward.gold) or 0,
                        reward.item and (" + " .. tostring(reward.item)) or "")) },
            s.canClaim and "签到" or "今日已签",
            function()
                local r = Game.claimSignin()
                act(r and (string.format("签到成功 +%d 金币", r.gold or 0)) or "今日已签到",
                    function() return r end)
            end,
            { disabled = not s.canClaim }),
    }
    kids[#kids + 1] = W.progressBar(((s.dayIndex or 1) - 1) / math.max(1, Config.num("signin.cycle_days", 7)))
    return W.sectionCard("每日签到", kids)
end

local function taskSection()
    local kids = {}
    for _, t in ipairs(Game.taskList()) do
        local btnText = t.claimed and "已领" or (t.done and ("领 " .. tostring(t.reward_gold)) or "未完成")
        kids[#kids + 1] = actionRow({
            line1(t.desc),
            line2(string.format("%d/%d", t.progress or 0, t.target or 0)),
            W.progressBar(t.ratio, { height = 10, marginTop = 6 }),
        }, btnText, function()
            local r = Game.claimTask(t.id)
            act(r and (string.format("任务奖励 +%d 金币", r.gold or 0)) or "无法领取",
                function() return r end)
        end, { disabled = t.claimed or not t.done })
    end
    if #kids == 0 then
        kids[#kids + 1] = line2("今日无任务")
    end
    return W.sectionCard("每日任务", kids, { subtitle = "每日 0 点重置" })
end

local function achievementSection()
    local kids = {}
    for _, a in ipairs(Game.achievements()) do
        kids[#kids + 1] = actionRow({
            line1(a.name, true, a.claimed and "jade_deep" or "ink"),
            line2(string.format("%d/%d%s", a.progress or 0, a.target or 0,
                a.claimed and "  已达成" or "")),
        }, a.claimed and "已达成" or "未达成", nil, { disabled = true })
    end
    return W.sectionCard("成就", kids, { subtitle = "达成自动发放金币" })
end

local function challengeSection()
    local info = Game.challengeInfo()
    local kids = {
        actionRow({
            line1(string.format("限时挑战：%d 词 / %d 秒", info.target or 0, info.timeLimit or 0), true),
            line2(string.format("今日剩余 %d/%d 次，最佳 %d 词",
                info.remaining or 0, info.limit or 0, info.best or 0)),
        }, (info.remaining or 0) > 0 and "开始挑战" or "今日已用完",
            function()
                local s, err = Game.startChallenge()
                if s then
                    local ok, Nav = pcall(require, "ui.nav")
                    if ok and Nav then Nav.reset("play", { session = s }) end
                else
                    alert("挑战不可用", tostring(err))
                end
            end,
            { disabled = (info.remaining or 0) <= 0, gradient = {
                direction = "to-bottom", from = c("seal"), to = c("seal_deep") },
              fg = c("cream"), glow = "seal_deep" }),
    }
    return W.sectionCard("每日挑战", kids, { subtitle = "限时内多答多得" })
end

local function shopSection()
    local limit = Game.iapLimit()
    local kids = {
        actionRow({
            line1("金币充值 / 看广告领奖励", true),
            line2(string.format("本月已消费 %s 元%s", moneyText(Game.iapMonthSpent()),
                (tonumber(limit.monthly_cny) or 0) > 0
                    and string.format("（限额 %s 元）", moneyText(limit.monthly_cny)) or "（当前年龄段不可内购）")),
        }, "前往商店", function()
            local ok, Nav = pcall(require, "ui.nav")
            if ok and Nav and Nav.go then Nav.go("shop") end
        end),
    }
    return W.sectionCard("商店", kids, { subtitle = "支付与广告均为待接入项" })
end

local function bookSection()
    local wrong = Game.wrongList()
    local kids = {
        actionRow({
            line1(string.format("成语图鉴：已收录 %d 条", Game.bookCount()), true),
            line2(string.format("错题本：%d 条", #wrong)),
        }, "查看图鉴", function()
            local ok, Nav = pcall(require, "ui.nav")
            if ok and Nav and Nav.go then Nav.go("book") end
        end),
    }
    return W.sectionCard("图鉴与错题本", kids, { subtitle = "填错的成语自动进错题本" })
end

------------------------------------------------------------------------------
-- 挂载
------------------------------------------------------------------------------

function Court.mount()
    local back = function()
        local ok, Nav = pcall(require, "ui.nav")
        if ok and Nav and Nav.back then Nav.back() end
    end

    local body = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = true,
        paddingHorizontal = 24,
        paddingVertical = 10,
        children = {
            rankSection(),
            manorSection(),
            followerSection(),
            signinSection(),
            taskSection(),
            challengeSection(),
            shopSection(),
            bookSection(),
            achievementSection(),
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
            W.pageHeader("府邸", {
                W.chip("金币 " .. tostring(Game.gold()), {
                    dotColor = c("coin"), fg = c("gold_dark"),
                }),
            }, back),
            body,
        },
    }
    UI.SetRoot(root, true)
    return root
end

return Court
