-- 题库索引：加载 data/idioms.json，建立「字 → 成语」倒排索引。
-- 关卡生成器靠 byChar 找可交叉的成语；运行时靠 get(refId) 取释义。

local json = require("core.json")
local fs = require("core.fs")
local util = require("core.util")

local M = {}

local DATA_PATH = "data/idioms.json"

local state_ = {
    loaded = false,
    items = {},
    byId = {},
    byWord = {},
    byChar = {},   -- char -> { entry, ... }
    byLevel = {},  -- level -> { entry, ... }
}

--- 加载题库（幂等）
function M.init(path, force)
    if state_.loaded and not force then return true, nil end
    local text, err = fs.readText(path or DATA_PATH)
    if not text then
        return false, "读取题库失败: " .. tostring(err)
    end
    local ok, data = pcall(json.decode, text)
    if not ok or type(data) ~= "table" or type(data.items) ~= "table" then
        return false, "解析题库失败: " .. tostring(data)
    end

    state_.items = data.items
    state_.byId, state_.byWord, state_.byChar, state_.byLevel = {}, {}, {}, {}
    for _, e in ipairs(data.items) do
        if type(e.word) == "string" and util.len(e.word) == 4 then
            state_.byId[e.id] = e
            state_.byWord[e.word] = e
            for _, ch in ipairs(util.chars(e.word)) do
                local bucket = state_.byChar[ch]
                if not bucket then
                    bucket = {}
                    state_.byChar[ch] = bucket
                end
                bucket[#bucket + 1] = e
            end
            local lvl = e.level or 1
            local lbucket = state_.byLevel[lvl] or {}
            lbucket[#lbucket + 1] = e
            state_.byLevel[lvl] = lbucket
        end
    end
    state_.loaded = true
    return true, nil
end

function M.ensure()
    if not state_.loaded then
        local ok, err = M.init()
        if not ok then error(err) end
    end
end

function M.get(refId)
    M.ensure()
    return state_.byId[refId]
end

function M.getByWord(word)
    M.ensure()
    return state_.byWord[word]
end

function M.all()
    M.ensure()
    return state_.items
end

function M.count()
    M.ensure()
    return #state_.items
end

--- 包含指定汉字的成语列表；第 pos 位（1-4）限定可选
function M.byChar(ch, pos)
    M.ensure()
    local bucket = state_.byChar[ch] or {}
    if not pos then return bucket end
    local out = {}
    for _, e in ipairs(bucket) do
        if util.charAt(e.word, pos) == ch then
            out[#out + 1] = e
        end
    end
    return out
end

--- 按难度层取（level 为 nil 时取全部）
function M.byLevel(level, tags)
    M.ensure()
    local pool = level and (state_.byLevel[level] or {}) or state_.items
    if not tags then return pool end
    local out = {}
    for _, e in ipairs(pool) do
        if e.tags then
            for _, want in ipairs(tags) do
                if util.contains(e.tags, want) then
                    out[#out + 1] = e
                    break
                end
            end
        end
    end
    return out
end

--- 按段位难度随机取一条：rareRatio 控制冷门比例
function M.randomByDifficulty(seg, rareRatio, rand)
    M.ensure()
    rand = rand or math.random
    local wantRare = (rand() < (rareRatio or 0))
    local pool = wantRare and (state_.byLevel[3] or {}) or (state_.byLevel[1] or {})
    if #pool == 0 then pool = state_.items end
    return pool[rand(#pool)]
end

function M.reset()
    state_.loaded = false
    state_.items, state_.byId, state_.byWord = {}, {}, {}
    state_.byChar, state_.byLevel = {}, {}
end

return M
