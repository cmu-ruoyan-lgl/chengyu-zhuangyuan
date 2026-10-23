-- 合规：实名 + 防沉迷（T23，PRD 第 5 章）。
-- 口径：
--   ①未实名禁入（compliance.realname_required）；
--   ②未成年人仅可在周五/六/日及法定节假日 20:00–21:00 进入，每日 60 分钟；
--   ③超时/非允许时段强制下线提示（健康忠告）。
-- ⚠️ 边界：真实实名认证与公安核验 SDK 不在代码能力范围内，本模块只做
--   「状态存储 + 规则判定」，认证入口由 ui/pages/login.lua 占位，
--   交付文档中列为待用户接入项。
-- 时间基准一律走 system/time（服务端校准），禁止 os.time() 直接判定。

local Config = require("core.config")
local Time = require("system.time")

local M = {}

local SEC_PER_DAY = function() return Config.num("time.sec_per_day", 86400) end

------------------------------------------------------------------------------
-- 状态
------------------------------------------------------------------------------

function M.required()
    return Config.get("compliance.realname_required", true) ~= false
end

function M.isVerified(save)
    return (save and save.realname_status) == "verified"
end

--- 是否已成年（未实名/未知按未成年处理，最保守）
function M.isMinor(save)
    if not save then return true end
    return (tonumber(save.age) or 0) < 18
end

function M.ageBracket(save)
    if not save then return "unknown" end
    return save.age_bracket or "unknown"
end

--- 记录实名结果。age<=0 表示只标记已认证但年龄未知（按未成年处理）
function M.setVerified(save, age)
    save.realname_status = "verified"
    save.age = tonumber(age) or 0
    local a = tonumber(age) or 0
    if a <= 0 then
        save.age_bracket = "unknown"
    elseif a < 8 then
        save.age_bracket = "child"
    elseif a < 16 then
        save.age_bracket = "minor_8_15"
    elseif a < 18 then
        save.age_bracket = "minor_16_17"
    else
        save.age_bracket = "adult"
    end
    return save.age_bracket
end

------------------------------------------------------------------------------
-- 时段
------------------------------------------------------------------------------

--- 是否法定节假日（数据来自 config.compliance.holiday_dates，需运营维护）
function M.isHoliday(nowTs)
    local list = Config.get("compliance.holiday_dates", {})
    if #list == 0 then return false end
    local day = os.date("%Y-%m-%d", tonumber(nowTs) or Time.now())
    for _, d in ipairs(list) do
        if d == day then return true end
    end
    return false
end

--- 当前是否在未成年人允许时段内
function M.inAllowedWindow(save, nowTs)
    if not M.isMinor(save) then return true end
    local t = os.date("*t", tonumber(nowTs) or Time.now())
    -- os.date 的 wday：1=周日 … 7=周六
    local allowedDays = Config.get("compliance.minor_allowed_weekdays", {})
    local dayOk = false
    for _, d in ipairs(allowedDays) do
        if tonumber(d) == t.wday then dayOk = true; break end
    end
    if not dayOk and Config.get("compliance.minor_holiday_allowed", false) and M.isHoliday(nowTs) then
        dayOk = true
    end
    if not dayOk then return false end
    local hours = Config.get("compliance.minor_allowed_hours", {})
    for _, h in ipairs(hours) do
        if tonumber(h) == t.hour then return true end
    end
    return false
end

------------------------------------------------------------------------------
-- 时长累计
------------------------------------------------------------------------------

local function ensurePlay(save, nowTs)
    if type(save.play_time) ~= "table" then save.play_time = {} end
    local day = math.floor((tonumber(nowTs) or Time.now()) / SEC_PER_DAY())
    if save.play_time.day ~= day then
        save.play_time = { day = day, seconds = 0 }
    end
    return save.play_time
end

function M.playedSeconds(save, nowTs)
    if not save then return 0 end
    return tonumber(ensurePlay(save, nowTs).seconds) or 0
end

--- 累计在线时长（由 UI 逐帧调用）
function M.tick(save, dt, nowTs)
    if not save then return 0 end
    local p = ensurePlay(save, nowTs)
    p.seconds = (tonumber(p.seconds) or 0) + (tonumber(dt) or 0)
    return p.seconds
end

function M.dailyLimitSec()
    return Config.num("compliance.minor_daily_minutes", 60) * 60
end

--- 未成年剩余可玩分钟数（成年返回极大值）
function M.remainingMinutes(save, nowTs)
    if not M.isMinor(save) then return math.huge end
    local left = M.dailyLimitSec() - M.playedSeconds(save, nowTs)
    return math.max(0, math.floor(left / 60))
end

------------------------------------------------------------------------------
-- 准入判定
------------------------------------------------------------------------------

--- 是否允许进入游戏。返回 ok, reason
--- reason: nil | "realname_required" | "minor_out_of_window" | "minor_overtime"
function M.canPlay(save, nowTs)
    if M.required() and not M.isVerified(save) then
        return false, "realname_required"
    end
    if M.isMinor(save) then
        if not M.inAllowedWindow(save, nowTs) then
            return false, "minor_out_of_window"
        end
        if M.playedSeconds(save, nowTs) >= M.dailyLimitSec() then
            return false, "minor_overtime"
        end
    end
    return true
end

--- 拒绝原因 → 玩家可读文案
function M.reasonText(reason)
    if reason == "realname_required" then
        return "按国家规定，需完成实名认证后方可进入游戏"
    elseif reason == "minor_out_of_window" then
        local days, hours = Config.get("compliance.minor_allowed_weekdays", {}),
                            Config.get("compliance.minor_allowed_hours", {})
        return string.format("未成年人仅可在周五、周六、周日及法定节假日 %d:00–%d:00 进入游戏",
            tonumber(hours[1]) or 20, (tonumber(hours[#hours]) or 21) + 1)
    elseif reason == "minor_overtime" then
        return string.format("今日游戏时长已达 %d 分钟上限，请明日再来",
            Config.num("compliance.minor_daily_minutes", 60))
    end
    return "暂时无法进入游戏"
end

function M.healthNotice()
    return Config.get("compliance.health_notice", "适度游戏益脑，沉迷游戏伤身。")
end

function M.agePrompt()
    return Config.get("compliance.age_prompt", "本游戏适合全年龄段玩家。")
end

------------------------------------------------------------------------------
-- 付费上限（供 econ/iap 复用）
------------------------------------------------------------------------------

--- 按年龄取付费上限：{ per_payment_cny, monthly_cny }
function M.paymentLimit(save)
    local age = tonumber(save and save.age) or 0
    local limits = Config.get("iap.limits", {})
    if not M.isVerified(save) or age <= 0 then
        -- 未实名/年龄未知：按最严格处理
        return { per_payment_cny = 0, monthly_cny = 0 }
    end
    for _, l in ipairs(limits) do
        if age <= (tonumber(l.age_max) or 0) then
            return {
                per_payment_cny = tonumber(l.per_payment_cny) or 0,
                monthly_cny = tonumber(l.monthly_cny) or 0,
            }
        end
    end
    return { per_payment_cny = math.huge, monthly_cny = math.huge }
end

return M
