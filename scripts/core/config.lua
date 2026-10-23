-- 配置读取：唯一数值来源（data/config.json）。
-- 支持点号路径取值：Config.get("gold.base_per_level")
-- 禁止在业务代码里写死数值 —— 一律走这里。

local json = require("core.json")
local fs = require("core.fs")

local M = {}

local DATA_PATH = "data/config.json"
local cache_ = nil

--- 加载（幂等）。失败时返回 nil + 原因，由调用方决定是否降级。
function M.load(force)
    if cache_ and not force then return cache_, nil end
    local text, err = fs.readText(DATA_PATH)
    if not text then
        return nil, "读取 " .. DATA_PATH .. " 失败: " .. tostring(err)
    end
    local ok, data = pcall(json.decode, text)
    if not ok or type(data) ~= "table" then
        return nil, "解析 " .. DATA_PATH .. " 失败: " .. tostring(data)
    end
    cache_ = data
    return cache_
end

--- 点号路径取值；找不到返回 default
function M.get(path, default)
    local data = M.load()
    if not data then return default end
    local node = data
    for seg in tostring(path):gmatch("[^%.]+") do
        if type(node) ~= "table" then return default end
        node = node[seg]
        if node == nil then return default end
    end
    return node
end

--- 数字取值（带类型保证）
function M.num(path, default)
    local v = M.get(path, default)
    if type(v) == "number" then return v end
    return default
end

--- 取难度段配置（按关卡号）
function M.segment(levelId)
    local segs = M.get("difficulty.segments", {})
    for _, seg in ipairs(segs) do
        if levelId >= (seg.from or 0) and levelId <= (seg.to or 0) then
            return seg
        end
    end
    return segs[#segs]
end

--- 区间随机：读 config 里的 [min,max] 数组
function M.range(path, default)
    local r = M.get(path, default)
    if type(r) == "table" and #r >= 2 then return r[1], r[2] end
    return default, default
end

--- 颜色：config 里存 [r,g,b,a]
function M.color(path, default)
    local c = M.get(path, default)
    if type(c) == "table" and #c >= 3 then
        return { c[1], c[2], c[3], c[4] or 255 }
    end
    return default
end

--- 清空缓存（测试用）
function M.reset()
    cache_ = nil
end

return M
