-- 游戏控制器：串联 存档 / 体力 / 金币 / 关卡会话（逻辑层，不 require UI）。
-- 职责：①启动读档与云合并；②进关扣体力、体力不足返回 stamina_gate；
-- ③通关结算（经 ctx.settle 注入 Session）；④中断续玩快照（杀进程不丢进度）；
-- ⑤会话内每次填字/撤销后落盘（崩溃安全）。
-- UI 只调用本模块方法并订阅 Session 事件，绝不反向。

local Save = require("system.save")
local Stamina = require("econ.stamina")
local Currency = require("econ.currency")
local Items = require("econ.items")
local Followers = require("econ.followers")
local Economy = require("econ.economy")
local Time = require("system.time")
local Daily = require("system.daily")
local Challenge = require("system.challenge")
local Rank = require("progress.rank")
local Manor = require("progress.manor")
local Book = require("progress.book")
local Achievements = require("progress.achievements")
local Session = require("core.session")
local Config = require("core.config")
local json = require("core.json")
local fs = require("core.fs")

local M = {}

local settleHook -- 前置声明（enterLevel 与定义都在下方）

local state = {
    save = nil,
    session = nil,
    maxLevel = 0,
    persist = true,
    mode = "level",      -- "level" | "challenge"（T20 复用同一会话与棋盘）
    rankUp = nil,        -- 上次结算的晋升结果（UI 弹窗用）
    lastAchievements = nil,
}

------------------------------------------------------------------------------
-- 初始化
------------------------------------------------------------------------------

--- 读 levels/manifest.json 的关卡总数（增量开发：当前 150 关）
local function loadMaxLevel()
    local text = fs.readText(fs.data("levels/manifest.json"))
    if not text then return 150 end
    local ok, data = pcall(json.decode, text)
    if ok and type(data) == "table" and tonumber(data.count) then
        return tonumber(data.count)
    end
    return 150
end

--- opts: { save = 注入存档（测试用), persist = false 关闭落盘（测试用） }
function M.init(opts)
    opts = opts or {}
    state.maxLevel = loadMaxLevel()
    state.persist = opts.persist ~= false
    if opts.save then
        state.save = opts.save
    else
        state.save = Save.load()
    end
    -- 新档/基准缺失时补当前时间
    if not state.save.stamina_ts or state.save.stamina_ts <= 0 then
        state.save.stamina_ts = Time.now()
    end
    Stamina.sync(state.save)
    -- 跨天重置（提示额度 / 每日任务 / 挑战次数）与官职刷新（T15/T19/T20）
    Daily.resetIfNeeded(state.save, Time.now())
    Rank.refresh(state.save)
    state.rankUp = nil
    if state.persist then M.persist() end
    return state.save
end

function M.save()
    return state.save
end

function M.session()
    return state.session
end

function M.maxLevel()
    return state.maxLevel
end

--- 落盘 + 云同步（best-effort）。测试模式（persist=false）跳过。
function M.persist()
    if not state.persist then return true end
    local ok, err = Save.write(state.save)
    if not ok then
        print("[game] 存档写入失败: " .. tostring(err))
    end
    Save.cloudSync(state.save)
    return ok
end

------------------------------------------------------------------------------
-- 查询（UI 显示用）
------------------------------------------------------------------------------

function M.stamina()
    return Stamina.sync(state.save)
end

function M.gold()
    return Currency.balance(state.save)
end

function M.staminaCost()
    return Config.num("stamina.cost_per_level", 5)
end

--- 下一关（未通关的最低关）
function M.currentLevelId()
    local passed = tonumber(state.save.max_level_passed) or 0
    return math.min(passed + 1, state.maxLevel)
end

function M.hasInProgress()
    return type(state.save.current) == "table" and state.save.current.level_id ~= nil
end

--- 云档启动合并（异步回调，结果落盘）。可选增强，失败不影响本地。
function M.tryCloudMerge(callback)
    Save.cloudLoad(function(remote)
        if not remote then
            if type(callback) == "function" then callback(false) end
            return
        end
        local merged, adopted = Save.merge(state.save, remote)
        if adopted then
            state.save = merged
            Stamina.sync(state.save)
            M.persist()
            print("[game] 采纳云端存档")
        end
        if type(callback) == "function" then callback(adopted) end
    end)
end

------------------------------------------------------------------------------
-- 进关 / 出关
------------------------------------------------------------------------------

--- 每次会话动作后同步中断快照（填字/撤销/提示/洗牌都算会话动作）
local function hookPersistListeners(s)
    local function snapshotCurrent()
        -- 挑战模式不写主线中断快照（T20：挑战关卡不进主线进度）
        if state.mode == "challenge" then return end
        -- 已通关/跳过的会话不再保留中断快照
        if s.state == "LevelCleared" or s.state == "Skipped" then
            state.save.current = nil
        else
            state.save.current = {
                level_id = s.levelId,
                grid = s.grid:snapshot(),
                bank = s.bank,
                hints_used = s.hintsUsed,
                wrong_count = s.wrongCount,
            }
        end
        M.persist()
    end
    -- 错题本 / 图鉴 / 每日任务（T18/T19）
    s:on("on_invalid", function(payload)
        for _, ref in ipairs(payload and payload.refs or {}) do
            Book.addWrong(state.save, ref)
        end
    end)
    s:on("on_idiom_completed", function(payload)
        local ref = payload and payload.ref
        if not ref then return end
        Book.unlock(state.save, ref)
        Book.removeWrong(state.save, ref)
        Daily.bump(state.save, "idiom_8", 1, Time.now())
    end)
    s:on("on_cell_filled", snapshotCurrent)
    s:on("on_undo", snapshotCurrent)
    s:on("on_hint_used", snapshotCurrent)
end

--- 进关。
--- opts.resume = true：从 save.current 中断快照恢复，不扣体力（同一次尝试续玩）。
--- 成功返回 Session；体力不足返回 nil,"stamina_gate"；其它错误返回 nil,原因。
function M.enterLevel(levelId, opts)
    opts = opts or {}
    local save = state.save

    if opts.resume and type(save.current) == "table" then
        local snap = save.current
        local s = Session.resume({
            levelId = snap.level_id,
            grid = snap.grid,
            bank = snap.bank,
            hintsUsed = snap.hints_used,
            wrongCount = snap.wrong_count,
        }, { settle = settleHook })
        if not s then return nil, "resume_failed" end
        state.session = s
        state.mode = "level"
        hookPersistListeners(s)
        return s
    end

    if not Stamina.consume(save, M.staminaCost()) then
        return nil, "stamina_gate"
    end

    local s, err = Session.start(levelId, { settle = settleHook })
    if not s then
        -- 关卡加载失败：退还体力，避免白扣
        save.stamina = math.min(Config.num("stamina.max", 50), (save.stamina or 0) + M.staminaCost())
        return nil, err or "level_load_failed"
    end
    state.session = s
    state.mode = "level"
    hookPersistListeners(s)
    save.current = nil
    M.persist()
    return s
end

--- 结算钩子（注入 Session.ctx.settle）：
--- 金币（连对倍率）→ 府邸加成（T16）→ 双倍卡（T14）→ 图鉴/任务/官职/成就（T18/T19）
--- 返回 { gold, base, manorRatio, doubled, unusedHints, streak, streakMultiplier,
---        rankUp, achievements }
function settleHook(levelId, stats)
    local save = state.save
    local now = Time.now()
    local reward = Currency.settleLevel(save, stats)

    -- 府邸加成（T16，唯一加成入口）
    local base = reward.gold
    local manorRatio = Manor.ratio(save)
    local gold = Manor.applyBonus(save, base)
    if gold > base then
        Currency.add(save, gold - base, "manor_bonus")
    end
    -- 双倍卡（T14）
    local doubled = Items.doubleActive(save, now)
    if doubled then
        Currency.add(save, gold, "double_card")
        gold = gold * 2
    end

    local passed = tonumber(save.max_level_passed) or 0
    if (tonumber(levelId) or 0) > passed then
        save.max_level_passed = tonumber(levelId)
    end

    -- 图鉴：本关达成的成语（T18）
    Book.unlockMany(save, stats.completedRefs or {})

    -- 每日任务（T19）
    Daily.bump(save, "clear_3", 1, now)
    if (tonumber(stats.hintsUsed) or 0) == 0 then
        Daily.bump(save, "no_hint_2", 1, now)
    end

    local st = save.stats or {}
    st.total_levels = (tonumber(st.total_levels) or 0) + 1
    st.total_wrong = (tonumber(st.total_wrong) or 0) + (tonumber(stats.wrongCount) or 0)
    save.stats = st

    local rankUp = Rank.refresh(save)
    local gained = Achievements.refresh(save)
    state.rankUp = rankUp
    state.lastAchievements = gained

    save.current = nil
    M.persist()

    reward.gold = gold
    reward.base = base
    reward.manorRatio = manorRatio
    reward.doubled = doubled
    reward.rankUp = rankUp
    reward.achievements = gained
    return reward
end

--- 中途退出（页面卸载时调用）：写中断快照
function M.abandon()
    local s = state.session
    if not s then return end
    if s.state == "LevelCleared" or s.state == "Skipped" then
        state.save.current = nil
    elseif s.state then
        state.save.current = {
            level_id = s.levelId,
            grid = s.grid:snapshot(),
            bank = s.bank,
            hints_used = s.hintsUsed,
            wrong_count = s.wrongCount,
        }
    end
    M.persist()
end

--- 进下一关：优先恢复中断快照，否则开新关
function M.nextLevel()
    if M.hasInProgress() then
        return M.enterLevel(nil, { resume = true })
    end
    return M.enterLevel(M.currentLevelId())
end

--- 广告补体力（S1 mock，S3 接真实广告位）
function M.claimAdStamina()
    Stamina.addByAd(state.save)
    M.persist()
    return M.stamina()
end

--- 距下次体力恢复剩余秒数
function M.staminaSecondsToNext()
    return Stamina.secondsToNext(state.save)
end

------------------------------------------------------------------------------
-- S2-A：道具（T14）
------------------------------------------------------------------------------

function M.now()
    return Time.now()
end

function M.itemCount(key)
    return Items.count(state.save, key)
end

function M.items()
    local out = {}
    for _, k in ipairs({ "hint", "shuffle", "skip", "double" }) do
        out[k] = Items.count(state.save, k)
    end
    return out
end

function M.freeHintsLeft()
    return Items.freeHintsLeft(state.save)
end

--- 使用提示：扣资源（免费 → 道具 → 金币）后落子
function M.useHint()
    local s = state.session
    if not s then return false, nil, "no_session" end
    if s.hintsUsed >= Config.num("hints.max_per_level", 3) then
        return false, nil, "hint_limit"
    end
    local ok, source, err = Items.useHint(state.save)
    if not ok then return false, nil, err end
    s.ctx.hintSource = source
    local hint, herr = s:useHint()
    if not hint then
        -- 无可提示位置时退还本次消耗（免费额度）
        if source == "free" then
            state.save.hints_used_today = math.max(0, (tonumber(state.save.hints_used_today) or 1) - 1)
        elseif source == "item" then
            Items.grant(state.save, "hint", 1)
        elseif source == "gold" then
            Currency.add(state.save, Config.num("items.hint_price_gold", 20), "hint_refund")
        end
        return false, nil, herr
    end
    M.persist()
    return true, source, hint
end

function M.useShuffle()
    local s = state.session
    if not s then return false, nil, "no_session" end
    local ok, source, err = Items.useShuffle(state.save)
    if not ok then return false, nil, err end
    s:useShuffle()
    M.persist()
    return true, source
end

--- 跳过：不产金币（防刷），只标记跳过并结束会话
function M.useSkip()
    local s = state.session
    if not s then return false, nil, "no_session" end
    local ok, source, err = Items.useSkip(state.save)
    if not ok then return false, nil, err end
    s:useSkip()
    state.save.current = nil
    M.persist()
    return true, source
end

function M.undoUnlimited()
    return Items.undoUnlimited()
end

function M.doubleLeft()
    return Items.doubleLeft(state.save, Time.now())
end

function M.activateDouble()
    local untilTs = Items.activateDouble(state.save, Time.now())
    M.persist()
    return untilTs
end

function M.grantItem(key, amount)
    local n = Items.grant(state.save, key, amount)
    M.persist()
    return n
end

------------------------------------------------------------------------------
-- S2-B：官职 / 府邸 / 俸禄（T15/T16）
------------------------------------------------------------------------------

function M.rank()
    local save = state.save
    local tier = Rank.current(save)
    local nxt, ratio, have, need = Rank.next(save)
    return {
        id = tier and tier.id,
        name = Rank.name(save),
        next = nxt,
        ratio = ratio,
        have = have,
        need = need,
        salary = Rank.salary(save),
        levelsPassed = tonumber(save.max_level_passed) or 0,
    }
end

--- 领取当日俸禄（每日一次）
function M.claimSalary()
    local day = Daily.dayKey(Time.now())
    if (tonumber(state.save.salary_day) or 0) == day then return nil, "already_claimed" end
    state.save.salary_day = day
    local gold = Rank.salary(state.save)
    Currency.add(state.save, gold, "salary")
    M.persist()
    return gold
end

function M.manor()
    return Manor.info(state.save)
end

function M.upgradeManor()
    local lv, err = Manor.upgrade(state.save)
    M.persist()
    return lv, err
end

------------------------------------------------------------------------------
-- S2-C：门客与经济护栏（T17）
------------------------------------------------------------------------------

function M.followers()
    return Followers.list(state.save)
end

function M.recruitFollower(id)
    local entry, err = Followers.recruit(state.save, id, Time.now())
    M.persist()
    return entry, err
end

function M.upgradeFollower(id)
    local lv, err = Followers.upgrade(state.save, id)
    M.persist()
    return lv, err
end

function M.idlePending()
    return Followers.pending(state.save, Time.now())
end

function M.collectIdle()
    local gold = Economy.collectIdle(state.save, Time.now())
    if gold > 0 then M.persist() end
    return gold
end

--- 经济护栏报告（挂机占比 vs 上限）
function M.economyReport()
    local rep = Economy.guardReport(state.save, Economy.referenceActiveDaily(state.save))
    rep.fullBuildCost = Economy.fullBuildCost()
    return rep
end

------------------------------------------------------------------------------
-- S2-D：图鉴 / 错题本 / 释义卡（T18）
------------------------------------------------------------------------------

function M.bookCount()
    return Book.count(state.save)
end

function M.bookList()
    return Book.list(state.save)
end

function M.wrongList()
    return Book.wrongList(state.save)
end

function M.card(refId)
    return Book.card(state.save, refId)
end

--- 本关（当前会话）达成的成语释义卡，结算页直接展示
function M.sessionCards()
    local s = state.session
    if not s then return {} end
    return Book.cardsFor(state.save, s.completedRefs or {})
end

------------------------------------------------------------------------------
-- S2-E：签到 / 每日任务 / 成就（T19）
------------------------------------------------------------------------------

function M.signinInfo()
    return Daily.signinInfo(state.save, Time.now())
end

function M.claimSignin()
    local r, err = Daily.claimSignin(state.save, Time.now())
    if r then M.persist() end
    return r, err
end

function M.taskList()
    return Daily.taskList(state.save, Time.now())
end

function M.claimTask(id)
    local r, err = Daily.claimTask(state.save, id, Time.now())
    if r then M.persist() end
    return r, err
end

function M.hasPendingDaily()
    return Daily.hasPending(state.save, Time.now())
end

function M.achievements()
    return Achievements.list(state.save)
end

function M.refreshAchievements()
    local gained = Achievements.refresh(state.save)
    if #gained > 0 then M.persist() end
    return gained
end

------------------------------------------------------------------------------
-- S2-F：每日挑战（T20，复用同一会话与棋盘）
------------------------------------------------------------------------------

function M.mode()
    return state.mode
end

function M.challengeInfo()
    return Challenge.info(state.save, Time.now())
end

function M.challengeLeft()
    return Challenge.left(state.save, Time.now())
end

function M.challengeExpired()
    return Challenge.expired(state.save, Time.now())
end

--- 开始挑战：把挑战会话挂到 state.session，棋盘页无需改动即可复用
function M.startChallenge()
    local s, err = Challenge.start(state.save, Time.now())
    if not s then return nil, err end
    state.session = s
    state.mode = "challenge"
    hookPersistListeners(s)
    M.persist()
    return s
end

--- 结束挑战（时间到或玩家主动结束）：结算并发放奖励
function M.finishChallenge()
    local s = state.session
    if not s then return nil, "no_session" end
    local res = Challenge.finish(state.save, s, Time.now())
    state.mode = "level"
    state.save.current = nil
    M.persist()
    return res
end

return M
