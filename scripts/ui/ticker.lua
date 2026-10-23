-- 统一的逐帧调度器。
-- 踩坑记录（RISK S3-1）：引擎侧对同一脚本对象的 SubscribeToEvent("Update", fn)
-- 是**单槽**的——后一次订阅会覆盖前一次。play 页与广告弹窗各订阅一次时，
-- 先订阅者的回调会被静默丢弃（实测第 13 帧后失效）。
-- 因此全项目只允许本模块订阅一次 Update，其余模块通过 Ticker.add 注册回调。

local M = {}

local handlers_ = {}
local hooked_ = false

--- 注册逐帧回调 fn(dt)
function M.add(fn)
    if type(fn) ~= "function" then return false end
    handlers_[#handlers_ + 1] = fn
    M.hook()
    return true
end

--- 订阅引擎 Update（只允许一次）
function M.hook()
    if hooked_ then return hooked_ end
    if _G.SubscribeToEvent == nil then
        hooked_ = false
        print("[ticker] 引擎 Update 事件不可用，逐帧回调降级")
        return false
    end
    local ok = pcall(function()
        _G.SubscribeToEvent("Update", function(self, eventType, eventData)
            M.tick(M.dtOf(eventData))
        end)
    end)
    hooked_ = (ok == true)
    print("[ticker] Update 订阅 " .. (hooked_ and "成功" or "失败（降级）"))
    return hooked_
end

--- 从 Update 事件取帧间隔。
--- 注意：不能用 os.clock() 推导 dt —— 实测该平台上 os.clock() 几乎不推进，
--- dt 恒为 0，防沉迷计时会完全失效（RISK S3-4）。
--- 取不到时回退到单一帧的保守估计（1/60 秒）。
function M.dtOf(eventData)
    if eventData ~= nil then
        local ok, v = pcall(function() return eventData["TimeStep"]:GetFloat() end)
        if ok and type(v) == "number" and v > 0 then
            return math.min(1, v)
        end
    end
    return 1 / 60
end

--- 由引擎 Update 驱动；dt 来自事件（单帧上限 1s，防切后台跳变）
function M.tick(dt)
    dt = tonumber(dt) or 0
    for i = 1, #handlers_ do
        local ok, err = pcall(handlers_[i], dt)
        if not ok then
            print("[ticker] 回调出错: " .. tostring(err))
        end
    end
end

--- 回调数量（诊断用）
function M.count()
    return #handlers_
end

return M
