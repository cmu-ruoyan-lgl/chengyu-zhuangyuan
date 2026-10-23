-- JSON 编解码统一入口。
-- 引擎运行时：使用内置全局 cjson（引擎已注册，性能与正确性最好）。
-- 离线跑 lua54（关卡生成 / 单测）：无 cjson、且 io 可用 → 走纯 Lua 兜底实现。
-- 两者行为对齐：数组解码为 1-based 连续数组；null 解码为 nil（cjson 用 cjson.null，
-- 这里统一转成 nil，业务层只判 nil）。

local M = {}

------------------------------------------------------------------------------
-- 引擎路径：cjson
------------------------------------------------------------------------------
if type(cjson) == "table" and type(cjson.encode) == "function" then
    local NULL = cjson.null

    function M.encode(value)
        return cjson.encode(value)
    end

    function M.decode(str)
        local data = cjson.decode(str)
        M._stripNull(data)
        return data
    end

    -- cjson 把 null 解成 lightuserdata 哨兵，递归清成 nil，避免污染业务层
    function M._stripNull(v)
        if type(v) ~= "table" then return end
        for k, sub in pairs(v) do
            if sub == NULL then
                v[k] = nil
            elseif type(sub) == "table" then
                M._stripNull(sub)
            end
        end
    end

    return M
end

------------------------------------------------------------------------------
-- 离线兜底：纯 Lua 实现（仅覆盖本项目数据结构）
------------------------------------------------------------------------------

local function escapeStr(s)
    s = s:gsub('[%z\1-\31\\"]', function(c)
        if c == "\\" then return "\\\\" end
        if c == '"' then return '\\"' end
        if c == "\n" then return "\\n" end
        if c == "\r" then return "\\r" end
        if c == "\t" then return "\\t" end
        if c == "\b" then return "\\b" end
        if c == "\f" then return "\\f" end
        return string.format("\\u%04X", string.byte(c))
    end)
    return s
end

local function isArray(t)
    local n, max = 0, 0
    for k in pairs(t) do
        if type(k) ~= "number" or k % 1 ~= 0 then return false end
        max = k > max and k or max
        n = n + 1
    end
    return n == max
end

local encodeValue

local function encodeTable(t, out)
    if isArray(t) then
        table.insert(out, "[")
        for i, v in ipairs(t) do
            if i > 1 then table.insert(out, ",") end
            encodeValue(v, out)
        end
        table.insert(out, "]")
    else
        table.insert(out, "{")
        local first = true
        -- 排序输出，保证离线生成的文件 diff 稳定
        local keys = {}
        for k in pairs(t) do
            if type(k) == "string" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            if not first then table.insert(out, ",") end
            first = false
            table.insert(out, '"' .. escapeStr(k) .. '":')
            encodeValue(t[k], out)
        end
        table.insert(out, "}")
    end
end

encodeValue = function(v, out)
    local tv = type(v)
    if v == nil then
        table.insert(out, "null")
    elseif tv == "boolean" then
        table.insert(out, v and "true" or "false")
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            table.insert(out, "null")
        elseif v % 1 == 0 and math.abs(v) < 2 ^ 53 then
            table.insert(out, string.format("%d", v))
        else
            table.insert(out, string.format("%.14g", v))
        end
    elseif tv == "string" then
        table.insert(out, '"' .. escapeStr(v) .. '"')
    elseif tv == "table" then
        encodeTable(v, out)
    else
        error("json.encode: 不支持的类型 " .. tv)
    end
end

function M.encode(value)
    local out = {}
    encodeValue(value, out)
    return table.concat(out)
end

------------------------------------------------------------------------------
-- 解析
------------------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function newParser(s)
    return setmetatable({ s = s, i = 1, n = #s }, Parser)
end

function Parser:error(msg)
    error(string.format("json.decode: %s (位置 %d)", msg, self.i), 0)
end

function Parser:skipWs()
    local s, n = self.s, self.n
    while self.i <= n do
        local c = s:sub(self.i, self.i)
        if c == " " or c == "\t" or c == "\n" or c == "\r" then
            self.i = self.i + 1
        else
            break
        end
    end
end

function Parser:parseValue()
    self:skipWs()
    local c = self.s:sub(self.i, self.i)
    if c == "{" then return self:parseObject() end
    if c == "[" then return self:parseArray() end
    if c == '"' then return self:parseString() end
    if self.s:sub(self.i, self.i + 3) == "true" then self.i = self.i + 4; return true end
    if self.s:sub(self.i, self.i + 4) == "false" then self.i = self.i + 5; return false end
    if self.s:sub(self.i, self.i + 3) == "null" then self.i = self.i + 4; return nil end
    return self:parseNumber()
end

function Parser:parseObject()
    self.i = self.i + 1 -- {
    local out = {}
    self:skipWs()
    if self.s:sub(self.i, self.i) == "}" then self.i = self.i + 1; return out end
    while true do
        self:skipWs()
        local key = self:parseString()
        self:skipWs()
        if self.s:sub(self.i, self.i) ~= ":" then self:error("期望 ':'") end
        self.i = self.i + 1
        out[key] = self:parseValue()
        self:skipWs()
        local c = self.s:sub(self.i, self.i)
        self.i = self.i + 1
        if c == "}" then return out end
        if c ~= "," then self:error("期望 ',' 或 '}'") end
    end
end

function Parser:parseArray()
    self.i = self.i + 1 -- [
    local out = {}
    self:skipWs()
    if self.s:sub(self.i, self.i) == "]" then self.i = self.i + 1; return out end
    while true do
        out[#out + 1] = self:parseValue()
        self:skipWs()
        local c = self.s:sub(self.i, self.i)
        self.i = self.i + 1
        if c == "]" then return out end
        if c ~= "," then self:error("期望 ',' 或 ']'") end
    end
end

local ESCAPES = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

function Parser:parseString()
    -- 调用前 self.i 指向起始引号
    local s, n = self.s, self.n
    self.i = self.i + 1
    local buf = {}
    while self.i <= n do
        local c = s:sub(self.i, self.i)
        if c == '"' then
            self.i = self.i + 1
            return table.concat(buf)
        elseif c == "\\" then
            local e = s:sub(self.i + 1, self.i + 1)
            if e == "u" then
                local hex = s:sub(self.i + 2, self.i + 5)
                local cp = tonumber(hex, 16)
                if not cp then self:error("非法 \\u 转义") end
                buf[#buf + 1] = utf8.char(cp)
                self.i = self.i + 6
            else
                local mapped = ESCAPES[e]
                if not mapped then self:error("非法转义 \\" .. tostring(e)) end
                buf[#buf + 1] = mapped
                self.i = self.i + 2
            end
        else
            buf[#buf + 1] = c
            self.i = self.i + 1
        end
    end
    self:error("字符串未闭合")
end

function Parser:parseNumber()
    local start = self.i
    local s, n = self.s, self.n
    while self.i <= n do
        local c = s:sub(self.i, self.i)
        if c:match("[%-%+%.%deE]") then
            self.i = self.i + 1
        else
            break
        end
    end
    local num = tonumber(s:sub(start, self.i - 1))
    if num == nil then self:error("非法数字") end
    return num
end

function M.decode(str)
    if type(str) ~= "string" then return nil end
    local p = newParser(str)
    local value = p:parseValue()
    p:skipWs()
    return value
end

return M
