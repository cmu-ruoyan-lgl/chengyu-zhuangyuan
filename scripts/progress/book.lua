-- 图鉴 / 错题本 / 释义卡（T18，PRD §3.7）。
-- 图鉴：通关时解锁成语（按 idiom_ref 去重）；
-- 错题本：填错的字所属成语自动入册，答对后移出；
-- 释义卡：从题库取 word/pinyin/meaning/source，结算页可直接查看。
-- 纯逻辑层：不 require UI。

local Idioms = require("core.idioms")

local M = {}

local function ensure(save)
    if type(save.book) ~= "table" then save.book = {} end
    if type(save.book.unlocked) ~= "table" then save.book.unlocked = {} end
    if type(save.book.wrong) ~= "table" then save.book.wrong = {} end
    return save.book
end

------------------------------------------------------------------------------
-- 图鉴
------------------------------------------------------------------------------

--- 解锁一条（按 ref 去重）。返回 true 表示本次新解锁
function M.unlock(save, refId)
    if not refId then return false end
    local book = ensure(save)
    for _, r in ipairs(book.unlocked) do
        if r == refId then return false end
    end
    book.unlocked[#book.unlocked + 1] = refId
    return true
end

--- 批量解锁，返回新解锁数量
function M.unlockMany(save, refs)
    local n = 0
    for _, r in ipairs(refs or {}) do
        if M.unlock(save, r) then n = n + 1 end
    end
    return n
end

--- 按成语文本解锁（用于只有 word 的场合）
function M.unlockWord(save, word)
    local e = Idioms.getByWord(word)
    if not e then return false end
    return M.unlock(save, e.id)
end

function M.has(save, refId)
    local book = ensure(save)
    for _, r in ipairs(book.unlocked) do
        if r == refId then return true end
    end
    return false
end

function M.count(save)
    return #ensure(save).unlocked
end

--- 图鉴明细（含释义），按解锁顺序
function M.list(save)
    local out = {}
    for _, ref in ipairs(ensure(save).unlocked) do
        local e = Idioms.get(ref)
        if e then out[#out + 1] = e end
    end
    return out
end

------------------------------------------------------------------------------
-- 错题本
------------------------------------------------------------------------------

--- 记一条错题（按 ref 去重）
function M.addWrong(save, refId)
    if not refId then return false end
    local book = ensure(save)
    for _, r in ipairs(book.wrong) do
        if r == refId then return false end
    end
    book.wrong[#book.wrong + 1] = refId
    return true
end

function M.addWrongWord(save, word)
    local e = Idioms.getByWord(word)
    if not e then return false end
    return M.addWrong(save, e.id)
end

--- 答对后移出错题本
function M.removeWrong(save, refId)
    local book = ensure(save)
    for i, r in ipairs(book.wrong) do
        if r == refId then
            table.remove(book.wrong, i)
            return true
        end
    end
    return false
end

function M.wrongCount(save)
    return #ensure(save).wrong
end

function M.wrongList(save)
    local out = {}
    for _, ref in ipairs(ensure(save).wrong) do
        local e = Idioms.get(ref)
        if e then out[#out + 1] = e end
    end
    return out
end

------------------------------------------------------------------------------
-- 释义卡
------------------------------------------------------------------------------

--- 释义卡内容：{ word, pinyin, meaning, source, example, unlocked }
function M.card(save, refId)
    local e = Idioms.get(refId)
    if not e then return nil end
    return {
        id = e.id,
        word = e.word,
        pinyin = e.pinyin or "",
        meaning = e.meaning or "",
        source = e.source or "",
        example = e.example or "",
        unlocked = M.has(save, e.id),
    }
end

--- 关卡结算用：把本关成语打包成释义卡列表
function M.cardsFor(save, refs)
    local out = {}
    for _, ref in ipairs(refs or {}) do
        local c = M.card(save, ref)
        if c then out[#out + 1] = c end
    end
    return out
end

return M
