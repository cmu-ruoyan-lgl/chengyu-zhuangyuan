-- 游戏控制器：串联 存档 / 体力 / 金币 / 关卡会话（逻辑层，不 require UI）。
-- 职责：①启动读档与云合并；②进关扣体力、体力不足返回 stamina_gate；
-- ③通关结算（经 ctx.settle 注入 Session）；④中断续玩快照（杀进程不丢进度）；
-- ⑤会话内每次填字/撤销后落盘（崩溃安全）。
-- UI 只调用本模块方法并订阅 Session 事件，绝不反向。

local Save = require("system.save")
local Stamina = require("econ.stamina")
local Currency = require("econ.currency")
local Time = require("system.time")
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
}

------------------------------------------------------------------------------
-- 初始化
------------------------------------------------------------------------------

--- 读 levels/manifest.json 的关卡总数（增量开发：当前 150 关）
local function loadMaxLevel()
    local text = fs.readText("data/levels/manifest.json")
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
    hookPersistListeners(s)
    save.current = nil
    M.persist()
    return s
end

--- 结算钩子（注入 Session.ctx.settle）：金币 + 进度 + 落盘
function settleHook(levelId, stats)
    local save = state.save
    local reward = Currency.settleLevel(save, stats)
    local passed = tonumber(save.max_level_passed) or 0
    if (tonumber(levelId) or 0) > passed then
        save.max_level_passed = tonumber(levelId)
    end
    local st = save.stats or {}
    st.total_levels = (tonumber(st.total_levels) or 0) + 1
    st.total_wrong = (tonumber(st.total_wrong) or 0) + (tonumber(stats.wrongCount) or 0)
    save.stats = st
    save.current = nil
    M.persist()
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

return M
