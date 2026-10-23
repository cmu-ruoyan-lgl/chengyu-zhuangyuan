-- 通用工具：UTF-8 汉字处理、可复现随机、表操作。
-- 纯逻辑、无引擎依赖，可在 lua54 下离线单测。

local M = {}

------------------------------------------------------------------------------
-- UTF-8
------------------------------------------------------------------------------

--- 把字符串切成字符数组（按 UTF-8 码点，不是字节）
function M.chars(s)
    local out = {}
    if type(s) ~= "string" then return out end
    for ch in s:gmatch(utf8.charpattern) do
        out[#out + 1] = ch
    end
    return out
end

--- 字符数（非字节数）
function M.len(s)
    return #M.chars(s)
end

--- 取第 i 个字符（1-based）
function M.charAt(s, i)
    local chars = M.chars(s)
    return chars[i]
end

------------------------------------------------------------------------------
-- 可复现随机（LCG，避免污染全局 math.random，保证 --seed 可复现）
------------------------------------------------------------------------------

--- seed 混洗（FNV-1a 变体，32 位内运算，不会丢精度）。
-- 为什么必须混洗（RISK S4-2）：MINSTD 的**首个输出**≈ frac(seed*16807/2^31)，
-- 相邻 seed 只差 1 时首个输出只差 0.0008% —— 关卡生成器用
-- `seed*7919 + levelId*1000 + attempt` 派生 seed，attempt 递增 1 的 120 次重试
-- 实际上"首抽"几乎完全一致（成语数恒为 4、失败关卡 120 次重试全部失败）。
local function mixSeed(seed)
    seed = math.floor(tonumber(seed) or 1)
    local h = 2166136261
    local guard = 0
    while seed > 0 and guard < 8 do
        h = (h * 65599 + (seed % 65536)) % 4294967296
        seed = math.floor(seed / 65536)
        guard = guard + 1
    end
    return h % 2147483647
end

--- 返回一个 rand 函数：rand() -> [0,1)；rand(n) -> [1,n] 整数
function M.rng(seed)
    local state = mixSeed(seed)
    if state <= 0 then state = state + 2147483646 end
    return function(n)
        state = (state * 16807) % 2147483647
        local v = (state - 1) / 2147483646
        if n then
            return math.floor(v * n) + 1
        end
        return v
    end
end

--- 原地洗牌（Fisher-Yates）
function M.shuffle(arr, rand)
    rand = rand or math.random
    for i = #arr, 2, -1 do
        local j = rand(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

--- 从数组里随机取一个
function M.pick(arr, rand)
    if #arr == 0 then return nil end
    return arr[(rand or math.random)(#arr)]
end

------------------------------------------------------------------------------
-- 表操作
------------------------------------------------------------------------------

function M.contains(t, v)
    for i = 1, #t do
        if t[i] == v then return true, i end
    end
    return false, nil
end

function M.setContains(set, v)
    return set[v] == true
end

--- 去重，保持首次出现顺序
function M.unique(arr)
    local seen, out = {}, {}
    for _, v in ipairs(arr) do
        if not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    return out
end

function M.countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- 浅拷贝
function M.copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

--- 深拷贝（仅处理 table/基础类型，不含环）
function M.deepcopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = M.deepcopy(v)
    end
    return out
end

--- 数值裁剪
function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

return M
