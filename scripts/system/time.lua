-- 权威时间源（裁决 #13）。
-- 引擎内用 common.get_server_time()：服务端校准 + 单调推算，改本地系统时间无效；
-- 引擎外（离线工具/单测）降级 os.time()；单测可用 setTestNow 注入固定时钟。
-- 注意：体力恢复、每日重置等一切防作弊时间判断必须走本模块，禁止直接 os.time()。

local M = {}

local testNow_ = nil

--- 当前 Unix 秒
function M.now()
    if testNow_ then return testNow_ end
    if _G.common ~= nil then
        local ok, v = pcall(function() return _G.common.get_server_time() end)
        if ok and type(v) == "number" and v > 0 then
            return v
        end
    end
    return os.time()
end

--- 单测注入固定时钟；nil 恢复真实时间
function M.setTestNow(ts)
    testNow_ = ts
end

return M
