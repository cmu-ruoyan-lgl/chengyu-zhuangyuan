-- 每日挑战（T20，PRD §3.7）：限时 10 词，复用 core/session 与预生成关卡池。
-- 设计取舍：挑战关卡是**预生成**的（data/levels/challenge/NNN.json），按天序号轮转，
-- 不在运行时跑生成器 —— 运行时生成会引入不可控耗时与失败分支，且无法保证同一天
-- 所有玩家拿到同一张卷子（排行/公平性）。
-- 不扣体力、不推进主线进度（max_level_passed），仅产金币与图鉴解锁。

local Config = require("core.config")
local Time = require("system.time")
local Session = require("core.session")
local Currency = require("econ.currency")
local Book = require("progress.book")
local Daily = require("system.daily")
local fs = require("core.fs")
local json = require("core.json")

local M = {}

------------------------------------------------------------------------------
-- 存档结构：save.challenge = { day, plays, best, started_ts }
------------------------------------------------------------------------------

local function ensure(save)
    if type(save.challenge) ~= "table" then save.challenge = {} end
    local c = save.challenge
    if type(c.day) ~= "number" then c.day = 0 end
    if type(c.plays) ~= "number" then c.plays = 0 end
    if type(c.best) ~= "number" then c.best = 0 end
    if type(c.started_ts) ~= "number" then c.started_ts = 0 end
    return c
end

function M.poolSize()
    return math.max(1, Config.num("challenge.pool_size", 20))
end

function M.pathFmt()
    return Config.get("challenge.path_fmt", "levels/challenge/%03d.json")
end

function M.fileFor(index)
    return string.format(M.pathFmt(), tonumber(index) or 1)
end

--- 目标词数：优先取当前卷子的实际成语数（生成器在 8~10 间浮动），
--- 未开始时回退到 config 的设计值
function M.idiomTarget(session)
    if session and type(session.levelData) == "table" and type(session.levelData.idioms) == "table" then
        return #session.levelData.idioms
    end
    return Config.num("challenge.idiom_count", 10)
end

function M.timeLimit()
    return Config.num("challenge.time_limit_sec", 180)
end

function M.dailyLimit()
    return Config.num("challenge.daily_limit", 1)
end

------------------------------------------------------------------------------
-- 每日轮转与可用性
------------------------------------------------------------------------------

function M.rollDay(save, nowTs)
    local c = ensure(save)
    local day = Daily.dayKey(nowTs)
    if c.day ~= day then
        c.day = day
        c.plays = 0
    end
    return c
end

function M.remainingPlays(save, nowTs)
    local c = M.rollDay(save, nowTs)
    return math.max(0, M.dailyLimit() - c.plays)
end

function M.canStart(save, nowTs)
    if M.remainingPlays(save, nowTs) <= 0 then return false, "limit_reached" end
    -- 注意：不能用 fs.exists 预判包内资源——设备上包内 JSON 在 ResourceCache 里，
    -- 不在沙箱文件系统，FileExists 恒 false（S7：主页挑战入口因此静默失效）。
    -- 可读性以 loadLevelData 的实际读取为准。
    return true
end

--- 今日卷子序号（按天轮转，所有人当天同卷）
function M.indexForDay(save, nowTs)
    local day = Daily.dayKey(nowTs)
    return (day % M.poolSize()) + 1
end

--- 读取今日卷子关卡数据
function M.loadLevelData(save, nowTs)
    local idx = M.indexForDay(save, nowTs)
    local path = fs.data(M.fileFor(idx))
    local text = fs.readText(path)
    if not text then return nil, "挑战关卡缺失: " .. path end
    local ok, data = pcall(json.decode, text)
    if not ok or type(data) ~= "table" then return nil, "挑战关卡解析失败: " .. path end
    return data, nil, idx
end

------------------------------------------------------------------------------
-- 计时
------------------------------------------------------------------------------

--- 已开始则剩余秒数；未开始返回总时长
function M.left(save, nowTs)
    local c = ensure(save)
    local now = tonumber(nowTs) or Time.now()
    if c.started_ts <= 0 then return M.timeLimit() end
    return math.max(0, M.timeLimit() - (now - c.started_ts))
end

function M.expired(save, nowTs)
    return M.left(save, nowTs) <= 0
end

function M.elapsed(save, nowTs)
    local c = ensure(save)
    local now = tonumber(nowTs) or Time.now()
    if c.started_ts <= 0 then return 0 end
    return math.max(0, now - c.started_ts)
end

------------------------------------------------------------------------------
-- 结算
------------------------------------------------------------------------------

--- 统计已完成成语数（复用 Grid 的 done 标记）
local function doneIdioms(session)
    local n, refs = 0, {}
    if not session or not session.grid then return n, refs end
    for _, id in ipairs(session.grid.idiomOrder or {}) do
        local it = session.grid.idioms[id]
        if it and it.done then
            n = n + 1
            if it.idiom_ref then refs[#refs + 1] = it.idiom_ref end
        end
    end
    return n, refs
end

--- 结算挑战。done 条数 × per_idiom + 全达成额外 reward_gold
--- 返回 { gold, idioms, target, allDone, best }
function M.finish(save, session, nowTs)
    local c = ensure(save)
    local done, refs = doneIdioms(session)
    local perIdiom = Config.num("challenge.reward_gold_per_idiom", 5)
    local finishBonus = Config.num("challenge.reward_gold", 60)
    local target = M.idiomTarget(session)
    local allDone = done >= target
    local gold = done * perIdiom + (allDone and finishBonus or 0)
    if gold > 0 then Currency.add(save, gold, "challenge") end
    Book.unlockMany(save, refs)
    if done > c.best then c.best = done end
    c.started_ts = 0
    return {
        gold = gold,
        idioms = done,
        target = target,
        allDone = allDone,
        best = c.best,
        refs = refs,
    }
end

------------------------------------------------------------------------------
-- 开始
------------------------------------------------------------------------------

--- 开始今日挑战。返回 session 或 nil,err
--- opts.hooks: { onCellFilled, onIdiomCompleted } 等额外事件回调
function M.start(save, nowTs, opts)
    M.rollDay(save, nowTs)
    local okStart, errStart = M.canStart(save, nowTs)
    if not okStart then return nil, errStart end
    local data, errLoad = M.loadLevelData(save, nowTs)
    if not data then return nil, errLoad end

    local c = ensure(save)
    c.started_ts = tonumber(nowTs) or Time.now()
    c.plays = c.plays + 1

    local session
    session = Session.start(data.level_id, {
        levelData = data,
        isChallenge = true,
        settle = function(levelId, stats)
            return M.finish(save, session, c.started_ts)
        end,
    })
    if not session then
        -- 启动失败要退还次数，避免白白消耗当日机会
        c.plays = math.max(0, c.plays - 1)
        c.started_ts = 0
        return nil, "challenge_start_failed"
    end
    return session
end

--- 展示用状态
function M.info(save, nowTs)
    M.rollDay(save, nowTs)
    local c = ensure(save)
    return {
        remaining = math.max(0, M.dailyLimit() - c.plays),
        limit = M.dailyLimit(),
        best = c.best,
        timeLimit = M.timeLimit(),
        target = M.idiomTarget(),
        index = M.indexForDay(save, nowTs),
        started = c.started_ts > 0,
    }
end

return M
