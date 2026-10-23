-- 体力（DEV §6.1）。恢复惰性结算：任何读取消耗动作前先 sync。
-- 纪律（裁决 #13）：时间一律走 system/time（引擎内为服务器时间），
-- 禁止 os.time()；时钟回退（now < stamina_ts）不产生恢复也不推进基准。

local Config = require("core.config")
local Time = require("system.time")

local M = {}

local function maxStamina()
    return Config.num("stamina.max", 50)
end

local function interval()
    local v = Config.num("stamina.recover_interval_sec", 360)
    if v <= 0 then v = 360 end
    return v
end

--- 结算离线恢复（写回 save.stamina / save.stamina_ts），返回当前体力。
function M.sync(save, nowTs)
    if type(save) ~= "table" then return 0 end
    nowTs = nowTs or Time.now()
    local max = maxStamina()
    local st = tonumber(save.stamina) or max
    local last = tonumber(save.stamina_ts) or 0
    if last <= 0 then
        -- 无基准（新档）：只刷新基准，不恢复
        save.stamina_ts = nowTs
        save.stamina = st
        return st
    end
    if last > nowTs then
        -- 时钟回退：单调时钟纪律（裁决 #13 不允许回退），不动基准、不恢复
        return st
    end
    if st >= max then
        save.stamina = max
        save.stamina_ts = nowTs
        return max
    end
    local iv = interval()
    local recovered = math.floor((nowTs - last) / iv)
    if recovered > 0 then
        st = math.min(max, st + recovered)
        save.stamina = st
        -- 保留不足一个 interval 的余量；满值时重置基准
        if st >= max then
            save.stamina_ts = nowTs
        else
            save.stamina_ts = last + recovered * iv
        end
    end
    return st
end

--- 扣体力。不足返回 false（调用方弹 StaminaGate），不产生负数。
function M.consume(save, amount, nowTs)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end
    local st = M.sync(save, nowTs)
    if st < amount then return false, "insufficient" end
    save.stamina = st - amount
    return true
end

--- 广告补体力（S1 为 mock，S3 接真实广告）：+ad_reward，封顶 max。
function M.addByAd(save, nowTs)
    local st = M.sync(save, nowTs)
    local reward = Config.num("stamina.ad_reward", 10)
    st = math.min(maxStamina(), st + reward)
    save.stamina = st
    return st
end

--- 距下次恢复剩余秒数（满时返回 0；供 UI 倒计时）
function M.secondsToNext(save, nowTs)
    nowTs = nowTs or Time.now()
    local max = maxStamina()
    if (save.stamina or 0) >= max then return 0 end
    local iv = interval()
    local last = tonumber(save.stamina_ts) or nowTs
    if last >= nowTs then return iv end
    local passed = (nowTs - last) % iv
    return iv - passed
end

return M
