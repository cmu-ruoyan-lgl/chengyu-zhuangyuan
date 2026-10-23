-- 存档系统（DEV §11 / §3.4，schema_version=1）。
-- 纪律：①写入先备份旧档到 .bak，再原子写（tmp → rename；引擎内无 rename 则直接写）；
-- ②读取损坏时回退 .bak；③schema_version 递增必须走 migrate，禁止就地丢字段；
-- ④云同步（clientCloud）是 best-effort 增强项，失败绝不阻塞本地流程。
-- 本模块属逻辑层：不 require UI。

local json = require("core.json")
local fs = require("core.fs")
local util = require("core.util")
local Config = require("core.config")

local M = {}

M.SCHEMA_VERSION = 1
M.CLOUD_KEY = "save_v1"

local path_ = "save.json"

--- 存档路径（测试可改）
function M.path(p)
    if p then path_ = p end
    return path_
end

local function bakPath()
    return path_ .. ".bak"
end

------------------------------------------------------------------------------
-- 默认档
------------------------------------------------------------------------------

--- 新档：体力满、金币 0、无进度。数值读 config，不硬编码。
function M.default()
    local uuid = string.format("p_%d_%d", os.time(), math.floor(os.clock() * 100000))
    return {
        schema_version = M.SCHEMA_VERSION,
        player_id = uuid,
        realname_status = "unverified",
        age_bracket = "unknown",
        rank_id = "tongsheng",
        manor_level = 1,
        followers = {},
        stamina = Config.num("stamina.max", 50),
        stamina_ts = 0,          -- 由调用方（Game.init）写入当前时间
        gold = 0,
        streak = 0,              -- 连对（清关无错填/无提示累积）
        items = { hint = 0, shuffle = 0, skip = 0, double = 0 },
        max_level_passed = 0,
        hints_used_today = 0,
        daily_reset_ts = 0,
        signin = { streak = 0, last_claim_day = 0 },
        book = { unlocked = {}, wrong = {} },
        achievements = {},
        settings = { big_text = false, sound = true, music = true },
        stats = { total_levels = 0, total_wrong = 0 },
        current = nil,           -- 中断续玩快照（S1 新增，见 RISK 记录）
    }
end

------------------------------------------------------------------------------
-- 迁移
------------------------------------------------------------------------------

--- schema_version 递增迁移。v0（无版本号/缺字段）→ v1：补默认字段。
function M.migrate(save)
    if type(save) ~= "table" then return M.default() end
    local ver = tonumber(save.schema_version) or 0
    while ver < M.SCHEMA_VERSION do
        local fn = M["migrate_v" .. ver .. "_to_v" .. (ver + 1)]
        if type(fn) == "function" then
            save = fn(save)
        end
        ver = ver + 1
    end
    save.schema_version = M.SCHEMA_VERSION
    -- 兜底：新档字段缺失时补齐（不覆盖已有值）
    local def = M.default()
    for k, v in pairs(def) do
        if save[k] == nil then
            save[k] = util.deepcopy(v)
        end
    end
    return save
end

--- v0 → v1
function M.migrate_v0_to_v1(save)
    save.schema_version = 1
    return save
end

------------------------------------------------------------------------------
-- 读 / 写
------------------------------------------------------------------------------

local function decode(text)
    local ok, data = pcall(json.decode, text)
    if ok and type(data) == "table" then return data end
    return nil
end

--- 读取存档。主档损坏回退 .bak；都没有则返回默认档。
--- 返回 save, source("main"|"bak"|"default")
function M.load()
    local text = fs.readText(path_)
    local save = text and decode(text) or nil
    if save then
        return M.migrate(save), "main"
    end
    text = fs.readText(bakPath())
    save = text and decode(text) or nil
    if save then
        print("[save] 主档损坏，已回退备份")
        return M.migrate(save), "bak"
    end
    return M.default(), "default"
end

--- 持久化：先备份旧档，再原子写。成功返回 true。
function M.write(save)
    if type(save) ~= "table" then return false, "save 无效" end
    save.schema_version = M.SCHEMA_VERSION

    -- 1) 旧档转备份（读旧 → 写 .bak；读不到就跳过）
    local old = fs.readText(path_)
    if old and #old > 0 then
        fs.writeText(bakPath(), old)
    end

    -- 2) 原子写主档
    local ok, err = fs.writeTextAtomic(path_, json.encode(save))
    if not ok then
        print("[save] 写入失败: " .. tostring(err))
        return false, err
    end
    return true
end

------------------------------------------------------------------------------
-- 云同步（best-effort，WASM 网页版刷新丢本地档时的兜底）
------------------------------------------------------------------------------

--- 同步到云。不登录 / 无 clientCloud / 超时均静默失败，不阻塞游戏。
function M.cloudSync(save)
    if type(_G.clientCloud) ~= "table" then return false, "no_client_cloud" end
    local ok, err = pcall(function()
        _G.clientCloud:Set(M.CLOUD_KEY, json.encode(save))
    end)
    if not ok then return false, err end
    return true
end

--- 从云端拉档并回调。冲突策略（DEV §11）：max_level_passed 与 stamina_ts 较大者为准。
--- callback(remoteSave | nil)
function M.cloudLoad(callback)
    if type(callback) ~= "function" then return false, "no_callback" end
    if type(_G.clientCloud) ~= "table" then callback(nil); return false, "no_client_cloud" end
    local ok, err = pcall(function()
        _G.clientCloud:Get(M.CLOUD_KEY, {
            ok = function(values)
                local raw = values and values[M.CLOUD_KEY]
                local remote = raw and decode(raw)
                callback(remote)
            end,
            error = function()
                callback(nil)
            end,
        })
    end)
    if not ok then
        callback(nil)
        return false, err
    end
    return true
end

--- 本地/云档合并（云档只在进度与时间基准更新时采纳）
function M.merge(localSave, remoteSave)
    if type(remoteSave) ~= "table" then return localSave, false end
    local lp = tonumber(localSave.max_level_passed) or 0
    local rp = tonumber(remoteSave.max_level_passed) or 0
    local lt = tonumber(localSave.stamina_ts) or 0
    local rt = tonumber(remoteSave.stamina_ts) or 0
    if rp > lp and rt >= lt then
        remoteSave = M.migrate(remoteSave)
        return remoteSave, true
    end
    return localSave, false
end

return M
