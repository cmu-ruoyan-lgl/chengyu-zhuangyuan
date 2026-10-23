-- 核心逻辑离线单测（lua54 跑，不依赖引擎）。
-- 覆盖：json / util / grid / validator / solver / session
--
-- CLI:
--   lua54 scripts/tools/run_tests.lua
--   lua54 scripts/tools/run_tests.lua --module core

package.path = "scripts/?.lua;" .. package.path

local json = require("core.json")
local util = require("core.util")
local fs = require("core.fs")
local Grid = require("core.grid")
local Validator = require("core.validator")
local Solver = require("core.solver")
local Session = require("core.session")
local Config = require("core.config")

------------------------------------------------------------------------------
-- 迷你测试框架
------------------------------------------------------------------------------
local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = { name = name, err = tostring(err) }
        print("❌ " .. name .. "\n   " .. tostring(err))
    end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: 期望 %s，实际 %s", msg or "eq",
            tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(v, msg)
    if not v then error((msg or "truthy") .. ": 期望真值，实际 " .. tostring(v), 2) end
end

------------------------------------------------------------------------------
-- 测试夹具：4×4，横「一马当先」× 竖「马到成功」，交叉于 (0,1)=马
------------------------------------------------------------------------------
local function fixture()
    return {
        level_id = 1,
        segment = 1,
        size = { 4, 4 },
        idioms = {
            { id = "h1", dir = "h", row = 0, col = 0, answer = "一马当先", idiom_ref = "i0001" },
            { id = "v1", dir = "v", row = 0, col = 1, answer = "马到成功", idiom_ref = "i0002" },
        },
        presets = {
            { r = 0, c = 0, char = "一" },
            { r = 0, c = 2, char = "当" },
            { r = 0, c = 3, char = "先" },
            { r = 2, c = 1, char = "成" },
            { r = 3, c = 1, char = "功" },
        },
        bank = { "马", "到" },
        distractors = {},
        generated_by = "test",
    }
end

--- 4 个空位的变体（用于测提示上限）
local function fixtureFourBlanks()
    local lv = fixture()
    lv.presets = {
        { r = 0, c = 0, char = "一" },
        { r = 0, c = 2, char = "当" },
        { r = 0, c = 3, char = "先" },
    }
    lv.bank = { "马", "到", "成", "功" }
    return lv
end

------------------------------------------------------------------------------
-- json
------------------------------------------------------------------------------
test("json 编解码往返（含中文）", function()
    local data = { a = 1, b = { "汉字", "成语" }, c = { x = true } }
    local text = json.encode(data)
    local back = json.decode(text)
    eq(back.a, 1, "a")
    eq(back.b[1], "汉字", "b[1]")
    eq(back.c.x, true, "c.x")
end)

test("json 数组保持 1-based", function()
    local back = json.decode('[10,20,30]')
    eq(back[1], 10)
    eq(#back, 3)
end)

------------------------------------------------------------------------------
-- util
------------------------------------------------------------------------------
test("util.chars 按码点切分", function()
    local cs = util.chars("一马当先")
    eq(#cs, 4)
    eq(cs[2], "马")
end)

test("util.rng 同种子可复现", function()
    local a, b = util.rng(42), util.rng(42)
    eq(a(), b())
    eq(a(100), b(100))
end)

-- RISK S4-2 回归：相邻 seed 的**首个输出**不能有强相关。
-- 修复前 MINSTD 直接吃原始 seed，attempt+1 只让首输出变化 0.0008%，
-- 关卡生成器的 120 次重试等于只试了一次。
test("util.rng 相邻 seed 首输出去相关", function()
    local a, b = util.rng(1000001), util.rng(1000002)
    local d = math.abs(a() - b())
    truthy(d > 0.05, string.format("首输出差异过小 (%.6f)，seed 混洗失效", d))
end)

test("util.unique 去重保序", function()
    local out = util.unique({ "a", "b", "a", "c", "b" })
    eq(#out, 3)
    eq(out[1], "a")
    eq(out[3], "c")
end)

------------------------------------------------------------------------------
-- grid
------------------------------------------------------------------------------
test("grid 交叉关系与 owner", function()
    local g = Grid.new(fixture())
    truthy(g:isCrossPoint(0, 1), "(0,1) 应为交叉点")
    eq(#g:idiomsOfCell(0, 1), 2)
    eq(g:getCell(0, 0).value, "一", "预填格应有值")
end)

test("grid 写错字不落盘", function()
    local g = Grid.new(fixture())
    local ok = g:setValue(0, 1, "错")
    eq(ok, false, "错字应返回 false")
    eq(g:getCell(0, 1).value, nil, "错字不应写入")
end)

test("grid 写对字并撤销", function()
    local g = Grid.new(fixture())
    eq(g:setValue(0, 1, "马"), true)
    eq(g:getCell(0, 1).value, "马")
    eq(g:blanksLeft(), 1)
    eq(g:clearCell(0, 1), true)
    eq(g:getCell(0, 1).value, nil)
    eq(g:blanksLeft(), 2)
end)

test("grid 快照与恢复", function()
    local g = Grid.new(fixture())
    g:setValue(0, 1, "马")
    local snap = g:snapshot()
    local g2 = Grid.restore(snap)
    eq(g2:getCell(0, 1).value, "马")
    eq(g2:blanksLeft(), 1)
end)

test("grid 交叉字符冲突应报错", function()
    local bad = fixture()
    bad.idioms[2].answer = "牛到成功" -- (0,1) 与横的「马」冲突
    local ok, err = pcall(Grid.new, bad)
    eq(ok, false, "冲突时应 assert 失败")
    truthy(tostring(err):find("交叉字符冲突"), "错误信息应含关键点")
end)

------------------------------------------------------------------------------
-- validator
------------------------------------------------------------------------------
test("validator 成语完成与通关", function()
    local g = Grid.new(fixture())
    g:setValue(0, 1, "马")
    local ok = Validator.checkIdiom(g, "h1")
    eq(ok, true, "h1 应完成")
    eq(Validator.checkLevel(g), false, "v1 未完成时不应通关")
    g:setValue(1, 1, "到")
    Validator.checkIdiom(g, "v1")
    eq(Validator.checkLevel(g), true, "全部完成后应通关")
end)

test("validator onCellFilled 增量返回", function()
    local g = Grid.new(fixture())
    g:setValue(0, 1, "马")
    local res = Validator.onCellFilled(g, 0, 1)
    eq(#res.completedIdiomIds, 1)
    eq(res.completedIdiomIds[1], "h1")
end)

------------------------------------------------------------------------------
-- solver
------------------------------------------------------------------------------
test("solver 可解关卡返回 true", function()
    local ok = Solver.isDerivable(fixture())
    eq(ok, true, "夹具应可推导")
end)

test("solver 无预填的关卡不可解", function()
    local lv = fixture()
    lv.presets = {}
    local ok, info = Solver.isDerivable(lv)
    eq(ok, false, "全空棋盘无法起步")
    truthy(#info.stalledIdioms > 0, "应给出停滞成语")
end)

test("solver.hintCell 优先只剩一空的成语", function()
    local g = Grid.new(fixture())
    local hint = Solver.hintCell(g)
    truthy(hint, "应给出提示")
    eq(hint.r, 0)
    eq(hint.c, 1)
    eq(hint.char, "马")
end)

test("solver.distinctCharCount 统计去重汉字", function()
    local n = Solver.distinctCharCount(fixture())
    eq(n, 7, "一马当先 + 马到成功 = 7 个不重复字")
end)

------------------------------------------------------------------------------
-- session
------------------------------------------------------------------------------
test("session 事件序列与通关", function()
    local events = {}
    local s = Session.start(1, { levelData = fixture() })
    truthy(s, "session 应创建成功")
    s:on("on_cell_filled", function() events[#events + 1] = "filled" end)
    s:on("on_idiom_completed", function(p) events[#events + 1] = "idiom:" .. p.idiomId end)
    s:on("on_level_cleared", function() events[#events + 1] = "cleared" end)

    s:selectCell(0, 1)
    local r1 = s:selectBankIndex(1) -- bank[1] = 马
    truthy(r1 and r1.ok, "第一次填写应成功")
    eq(#s.history, 1)

    local idx2 = nil
    for i, b in ipairs(s.bank) do if b.char == "到" and not b.used then idx2 = i end end
    s:selectCell(1, 1)
    local r2 = s:selectBankIndex(idx2)
    truthy(r2 and r2.cleared, "第二次填写应通关")

    eq(table.concat(events, ","), "filled,idiom:h1,filled,idiom:v1,cleared")
end)

test("session 撤销无损", function()
    local s = Session.start(1, { levelData = fixture() })
    s:selectCell(0, 1)
    s:selectBankIndex(1)
    eq(s.bank[1].used, true)
    eq(s:undo(), true)
    eq(s.bank[1].used, false)
    eq(s.grid:getCell(0, 1).value, nil)
    eq(s.wrongCount, 0)
end)

test("session 填错计数且不上盘", function()
    local s = Session.start(1, { levelData = fixture() })
    s:selectCell(0, 1)
    s:fill(0, 1, "错")
    eq(s.wrongCount, 1)
    eq(s.grid:getCell(0, 1).value, nil)
end)

test("session 提示受单关上限约束", function()
    local maxHints = Config.num("hints.max_per_level", 3)
    local s = Session.start(1, { levelData = fixtureFourBlanks() })
    local lastErr = nil
    for _ = 1, maxHints + 2 do
        local _, err = s:useHint()
        if err then lastErr = err end
    end
    eq(s.hintsUsed, maxHints, "提示次数应被 config 上限截断")
    eq(lastErr, "hint_limit", "超限后应返回 hint_limit")
end)

test("session 无空可提时返回 nothing_to_hint", function()
    local s = Session.start(1, { levelData = fixture() })
    s:fill(0, 1, "马")
    s:fill(1, 1, "到")
    local hint, err = s:useHint()
    eq(hint, nil)
    eq(err, "nothing_to_hint")
end)

test("session 洗牌不改变字块可用性", function()
    local s = Session.start(1, { levelData = fixture() })
    local before = {}
    for _, b in ipairs(s.bank) do before[#before + 1] = b.char end
    s:useShuffle()
    local after = {}
    for _, b in ipairs(s.bank) do after[#after + 1] = b.char end
    eq(#after, #before)
    table.sort(before)
    table.sort(after)
    eq(table.concat(after, ""), table.concat(before, ""), "洗牌不应丢字")
end)

test("session 中途退出与恢复", function()
    local s = Session.start(1, { levelData = fixture() })
    s:selectCell(0, 1)
    s:selectBankIndex(1)
    local snap = s:abandon()
    local s2 = Session.resume(snap, { levelData = fixture() })
    truthy(s2, "应能恢复")
    eq(s2.grid:getCell(0, 1).value, "马")
    eq(s2.hintsUsed, 0)
end)

------------------------------------------------------------------------------
-- S1 新增：save / time / stamina / currency / game
------------------------------------------------------------------------------
local Save = require("system.save")
local Time = require("system.time")
local Stamina = require("econ.stamina")
local Currency = require("econ.currency")
local Game = require("system.game")

local TEST_SAVE_PATH = ".tmp_test_save.json"

local function cleanupSaveFiles()
    os.remove(TEST_SAVE_PATH)
    os.remove(TEST_SAVE_PATH .. ".bak")
    os.remove(TEST_SAVE_PATH .. ".tmp")
end

test("save 读写往返一致（T3）", function()
    cleanupSaveFiles()
    Save.path(TEST_SAVE_PATH)
    local save = Save.default()
    save.gold = 123
    save.max_level_passed = 7
    truthy(Save.write(save), "写入应成功")
    local back, source = Save.load()
    eq(source, "main")
    eq(back.gold, 123, "gold 应一致")
    eq(back.max_level_passed, 7, "max_level_passed 应一致")
    eq(back.schema_version, Save.SCHEMA_VERSION)
    cleanupSaveFiles()
end)

test("save 主档损坏回退 .bak（T3 断电保护）", function()
    cleanupSaveFiles()
    Save.path(TEST_SAVE_PATH)
    local save = Save.default()
    save.gold = 456
    truthy(Save.write(save))
    -- 再写一次：旧档转 .bak
    save.gold = 789
    truthy(Save.write(save))
    -- 破坏主档
    local f = io.open(TEST_SAVE_PATH, "wb"); f:write("{corrupted!!!"); f:close()
    local back, source = Save.load()
    eq(source, "bak", "应回退备份档")
    eq(back.gold, 456, "备份应是上一版")
    cleanupSaveFiles()
end)

test("save 迁移：v0 档补默认字段不丢进度（T3）", function()
    local legacy = { schema_version = 0, gold = 77, max_level_passed = 12 }
    local m = Save.migrate(legacy)
    eq(m.schema_version, Save.SCHEMA_VERSION)
    eq(m.gold, 77)
    eq(m.max_level_passed, 12)
    eq(m.stamina, Config.num("stamina.max", 50), "缺失字段补默认")
    truthy(m.settings, "settings 补齐")
end)

test("stamina 离线恢复与封顶（T12）", function()
    local max = Config.num("stamina.max", 50)
    local iv = Config.num("stamina.recover_interval_sec", 360)
    local save = { stamina = 10, stamina_ts = 1000 }
    -- 过 3 个 interval：+3
    local st = Stamina.sync(save, 1000 + 3 * iv)
    eq(st, 13)
    eq(save.stamina_ts, 1000 + 3 * iv, "余量应保留")
    -- 离线上限：过 10000 个 interval 不溢出
    st = Stamina.sync(save, 1000 + 10000 * iv)
    eq(st, max)
    -- 时钟回退：不恢复、不推进基准
    local tsBefore = save.stamina_ts
    st = Stamina.sync(save, 500)
    eq(st, max)
    eq(save.stamina_ts, tsBefore, "时钟回退不得推进基准")
end)

test("stamina 消耗不足返回 false（T12）", function()
    local save = { stamina = 4, stamina_ts = 1000 }
    local ok = Stamina.consume(save, 5, 1000)
    eq(ok, false, "体力不足应拒绝")
    eq(save.stamina, 4, "不得扣成负数")
    ok = Stamina.consume(save, 4, 1000)
    truthy(ok, "恰好够应通过")
    eq(save.stamina, 0)
end)

test("stamina 广告奖励封顶（T12）", function()
    local max = Config.num("stamina.max", 50)
    local save = { stamina = max - 3, stamina_ts = 1000 }
    local st = Stamina.addByAd(save, 1000)
    eq(st, max, "不得超上限")
end)

test("currency 结算公式与 config 一致（T13）", function()
    local base = Config.num("gold.base_per_level", 10)
    local bonus = Config.num("gold.bonus_per_unused_hint", 5)
    local maxHints = Config.num("hints.max_per_level", 3)
    local save = { gold = 0, streak = 0 }
    -- 无提示：base + bonus*maxHints
    local r = Currency.settleLevel(save, { hintsUsed = 0, wrongCount = 0 })
    eq(r.gold, base + bonus * maxHints)
    eq(save.gold, r.gold)
    -- 用 1 提示：少一份 bonus，且连对中断
    save.streak = 5
    local r2 = Currency.settleLevel(save, { hintsUsed = 1, wrongCount = 0 })
    eq(r2.gold, base + bonus * (maxHints - 1), "提示减少 bonus")
    eq(r2.streakMultiplier, 1, "用提示不得触发连对倍率")
    eq(save.streak, 0, "用提示连对中断")
end)

test("currency 连对倍率与中断（T13，裁决 #14）", function()
    local base = Config.num("gold.base_per_level", 10)
    local bonus = Config.num("gold.bonus_per_unused_hint", 5)
    local maxHints = Config.num("hints.max_per_level", 3)
    local threshold = Config.num("gold.streak_threshold", 3)
    local mult = Config.num("gold.streak_multiplier", 2)
    local save = { gold = 0, streak = 0 }
    for i = 1, threshold do
        local r = Currency.settleLevel(save, { hintsUsed = 0, wrongCount = 0 })
        if i < threshold then
            eq(r.streakMultiplier, 1, "连对未达标无倍率")
        else
            eq(r.streakMultiplier, mult, "连对达标触发倍率")
            eq(r.gold, (base + bonus * maxHints) * mult)
        end
    end
    -- 错填中断
    local r = Currency.settleLevel(save, { hintsUsed = 0, wrongCount = 1 })
    eq(r.streakMultiplier, 1)
    eq(save.streak, 0, "错填连对清零")
end)

test("currency 余额不足返回 false（T13）", function()
    local save = { gold = 10 }
    eq(Currency.spend(save, 20), false)
    eq(save.gold, 10, "不得扣成负数")
    truthy(Currency.spend(save, 10))
    eq(save.gold, 0)
end)

test("game 进关扣体力、通关结算、进度推进（T10/T12/T13 串联）", function()
    cleanupSaveFiles()
    Save.path(TEST_SAVE_PATH)
    Time.setTestNow(100000)
    local save = Save.default()
    save.stamina_ts = 100000
    Game.init({ save = save, persist = false })
    local cost = Config.num("stamina.cost_per_level", 5)
    local before = save.stamina
    local s = Game.enterLevel(1)
    truthy(s, "进关应成功")
    eq(save.stamina, before - cost, "进关扣体力")
    -- 通关：按答案填满
    local grid = s.grid
    for r = 0, grid.rows - 1 do
        for c = 0, grid.cols - 1 do
            local cell = grid:getCell(r, c)
            if cell and cell.answer and cell.value == nil then
                s:fill(r, c, cell.answer)
            end
        end
    end
    eq(s.state, "LevelCleared", "应通关")
    eq(save.max_level_passed, 1)
    local expect = Config.num("gold.base_per_level", 10)
        + Config.num("gold.bonus_per_unused_hint", 5) * Config.num("hints.max_per_level", 3)
    eq(save.gold, expect, "首关结算 = base + bonus*maxHints")
    eq(save.streak, 1)
    eq(save.current, nil, "通关后无中断快照")
    Time.setTestNow(nil)
    cleanupSaveFiles()
end)

test("game 体力不足进关被拒且不扣体力（T12）", function()
    cleanupSaveFiles()
    Save.path(TEST_SAVE_PATH)
    Time.setTestNow(200000)
    local save = Save.default()
    save.stamina = Config.num("stamina.cost_per_level", 5) - 1
    save.stamina_ts = 200000
    Game.init({ save = save, persist = false })
    local s, err = Game.enterLevel(2)
    eq(s, nil)
    eq(err, "stamina_gate", "应返回 stamina_gate")
    eq(save.stamina, Config.num("stamina.cost_per_level", 5) - 1, "不得扣体力")
    Time.setTestNow(nil)
    cleanupSaveFiles()
end)

test("game 中断快照与恢复（T3+T10：杀进程不丢）", function()
    cleanupSaveFiles()
    Save.path(TEST_SAVE_PATH)
    Time.setTestNow(300000)
    local save = Save.default()
    save.stamina_ts = 300000
    Game.init({ save = save, persist = false })
    local s = Game.enterLevel(1)
    truthy(s)
    -- 填一格 → 中断
    local grid = s.grid
    local filled = nil
    for r = 0, grid.rows - 1 do
        for c = 0, grid.cols - 1 do
            local cell = grid:getCell(r, c)
            if cell and cell.answer and cell.value == nil and not filled then
                s:fill(r, c, cell.answer)
                filled = { r = r, c = c, char = cell.answer }
            end
        end
    end
    truthy(filled, "应能填一格")
    Game.abandon()
    truthy(save.current, "应有中断快照")
    eq(save.current.level_id, 1)
    -- 恢复（不重复扣体力）
    local before = save.stamina
    local s2 = Game.enterLevel(nil, { resume = true })
    truthy(s2, "应能恢复")
    eq(save.stamina, before, "恢复不得再扣体力")
    eq(s2.grid:getCell(filled.r, filled.c).value, filled.char, "已填格应保留")
    Time.setTestNow(nil)
    cleanupSaveFiles()
end)

------------------------------------------------------------------------------
-- S2 新增：items / rank / manor / followers / economy / book / daily / achv / challenge
------------------------------------------------------------------------------
local Items = require("econ.items")
local Rank = require("progress.rank")
local Manor = require("progress.manor")
local Followers = require("econ.followers")
local Economy = require("econ.economy")
local Book = require("progress.book")
local Daily = require("system.daily")
local Achv = require("progress.achievements")
local Challenge = require("system.challenge")
local fs = require("core.fs")

local function freshSave()
    local s = Save.default()
    s.stamina_ts = Time.now()
    return s
end

local function sumArray(arr)
    local n = 0
    for _, v in ipairs(arr or {}) do n = n + (tonumber(v) or 0) end
    return n
end

test("items 提示：免费额度 → 道具 → 金币（T14）", function()
    local s = freshSave()
    local free = Config.num("hints.free_per_day", 3)
    for i = 1, free do
        local ok, src = Items.useHint(s)
        truthy(ok, "第 " .. i .. " 次提示应可用")
        eq(src, "free", "应走免费额度")
    end
    eq(Items.freeHintsLeft(s), 0, "免费额度应耗尽")
    local okNo = Items.useHint(s)
    eq(okNo, false, "无道具无金币时应失败")
    -- 道具
    Items.grant(s, "hint", 1)
    local _, srcItem = Items.useHint(s)
    eq(srcItem, "item", "应消耗提示卡")
    eq(Items.count(s, "hint"), 0)
    -- 金币
    local price = Config.num("items.hint_price_gold", 20)
    s.gold = price
    local okGold, srcGold = Items.useHint(s)
    truthy(okGold, "金币应可买提示")
    eq(srcGold, "gold")
    eq(s.gold, 0, "金币应被扣光")
end)

test("items 双倍卡时限 / 撤销无限 / 洗牌跳过（T14）", function()
    local s = freshSave()
    Items.grant(s, "double", 1)
    local dur = Config.num("items.double_duration_sec", 1800)
    local untilTs = Items.activateDouble(s, 1000)
    eq(untilTs, 1000 + dur)
    truthy(Items.doubleActive(s, 1000))
    eq(Items.doubleActive(s, untilTs), false, "到期应失效")
    eq(Items.doubleLeft(s, 1000), dur)
    truthy(Items.undoUnlimited(), "撤销应无限")
    -- 洗牌：金币路径
    s.gold = Config.num("items.shuffle_price", 15)
    local okSh, srcSh = Items.useShuffle(s)
    truthy(okSh)
    eq(srcSh, "gold")
    -- 跳过不产金币
    s.gold = Config.num("items.skip_price", 30)
    local okSk = Items.useSkip(s)
    truthy(okSk)
    eq(Items.skipRewardRatio(), Config.num("items.skip_gold_ratio", 0), "跳过不得产金币")
end)

test("rank 八阶阈值与俸禄（T15）", function()
    local tiers = Rank.tiers()
    eq(#tiers, 8, "应 8 阶")
    for i = 2, #tiers do
        truthy((tonumber(tiers[i].need) or 0) > (tonumber(tiers[i - 1].need) or 0),
            "阈值应单调递增")
    end
    local s = freshSave()
    eq(Rank.indexFor(0), 1)
    eq(Rank.name(s), tiers[1].name)
    s.max_level_passed = tiers[#tiers].need
    eq(Rank.indexFor(s.max_level_passed), #tiers, "满进度应到状元")
    eq(Rank.salary(s), #tiers * Config.num("rank.salary_gold_per_tier", 20))
    s.rank_id = nil
    local up = Rank.refresh(s)
    truthy(up, "首次刷新应返回晋升结果")
    eq(s.rank_id, tiers[#tiers].id)
    eq(Rank.refresh(s), nil, "阶位未变不应返回晋升")
    local nxt, ratio = Rank.next({ max_level_passed = 0 })
    truthy(nxt, "童生应有下一阶")
    eq(ratio, 0)
end)

test("manor 六级成本曲线与金币加成（T16）", function()
    local names = Config.get("manor.names", {})
    local costs = Config.get("manor.costs", {})
    eq(#names, 6, "府邸应 6 级")
    eq(#costs, 5, "5 次升级")
    local s = freshSave()
    eq(Manor.level(s), 1)
    eq(Manor.name(s), names[1])
    eq(Manor.isMax(s), false)
    for i, c in ipairs(costs) do
        s.gold = c
        local lv = Manor.upgrade(s)
        eq(lv, i + 1, "第 " .. i .. " 次升级应到 " .. (i + 1) .. " 级")
        eq(s.gold, 0, "应扣光金币")
    end
    eq(Manor.isMax(s), true)
    eq(Manor.upgrade(s), nil, "满级后不可再升")
    local ratio = tonumber(Config.get("manor.gold_bonus_ratio", {})[#names]) or 0
    eq(Manor.applyBonus(s, 100), math.floor(100 * (1 + ratio)), "应施加满级加成")
    eq(Manor.totalCost(), sumArray(costs))
end)

test("followers 招募/升级/挂机时间封顶（T17）", function()
    local s = freshSave()
    local def = Config.get("followers.list", {})[1]
    s.gold = Followers.costFor(def, 1)
    local f = Followers.recruit(s, def.id, 1000)
    truthy(f, "应能招募")
    eq(s.gold, 0)
    eq(f.level, 1)
    truthy(Followers.outputFor(def, 2) > Followers.outputFor(def, 1), "产出应随等级增长")
    s.gold = Followers.costFor(def, 2)
    eq(Followers.upgrade(s, def.id), 2)
    eq(Followers.upgrade(s, def.id), nil, "金币不足不应升级")
    -- 时间封顶
    local capSec = Config.num("followers.idle_cap_hours", 8) * Config.num("time.sec_per_hour", 3600)
    local p1 = Followers.pending(s, 1000 + capSec)
    local p2 = Followers.pending(s, 1000 + capSec * 3)
    eq(p1.gold, p2.gold, "超过封顶时长不再累积")
    truthy(p2.capped, "应标记已封顶")
    -- 金币封顶（护栏②）
    local p3 = Followers.pending(s, 1000 + capSec * 3, 1)
    eq(p3.gold, 1, "金币封顶应生效")
end)

test("经济护栏：挂机占比受控 + 30 天不通胀（T17）", function()
    -- 最坏情况：全门客满级 + 府邸满级
    local s = freshSave()
    s.manor_level = #Config.get("manor.names", {})
    s.followers = {}
    for _, def in ipairs(Config.get("followers.list", {})) do
        s.followers[#s.followers + 1] = {
            id = def.id, level = Config.num("followers.max_level", 10), ts = 0,
        }
    end
    local rep = Economy.guardReport(s, Economy.referenceActiveDaily(s))
    truthy(rep.ok, string.format("挂机占比 %.3f 应 ≤ %.2f", rep.ratio, rep.cap))
    truthy(Followers.dailyIdleCap(s) > rep.dailyIdle, "理论上产出应被护栏压住")
    local sim = Economy.simulate(30, Config.num("economy_guard.reference_levels_per_day", 30))
    truthy(sim.totalGold < sim.fullBuildCost,
        string.format("30 天产出 %d 应小于全建满成本 %d（否则金币通胀）",
            sim.totalGold, sim.fullBuildCost))
    truthy(sim.idleRatio <= rep.cap + 1e-9, "模拟期挂机占比应受控")
    truthy(sim.daysToFullBuild > 30, "全建满应超过 30 天")
end)

test("book 图鉴去重 / 错题本 / 释义卡（T18）", function()
    local s = freshSave()
    eq(Book.unlock(s, "i0001"), true)
    eq(Book.unlock(s, "i0001"), false, "不应重复解锁")
    eq(Book.count(s), 1)
    truthy(Book.has(s, "i0001"))
    eq(Book.addWrong(s, "i0002"), true)
    eq(Book.wrongCount(s), 1)
    truthy(Book.removeWrong(s, "i0002"))
    eq(Book.wrongCount(s), 0)
    local card = Book.card(s, "i0001")
    truthy(card, "释义卡应存在")
    truthy(card.word and #card.word > 0, "词条非空")
    truthy(card.meaning and #card.meaning > 0, "释义非空（T8 口径）")
end)

test("daily 跨天重置 / 签到连签断签 / 任务领取（T19）", function()
    local day = Config.num("time.sec_per_day", 86400)
    local t0 = day * 100
    local s = freshSave()
    Daily.resetIfNeeded(s, t0)
    eq(s.daily.day, 100)
    s.hints_used_today = 3
    Daily.bump(s, "clear_3", 1, t0)
    eq(Daily.taskProgress(s, "clear_3"), 1)
    -- 跨天
    truthy(Daily.resetIfNeeded(s, t0 + day), "跨天应触发重置")
    eq(s.hints_used_today, 0, "跨天清零提示额度")
    eq(Daily.taskProgress(s, "clear_3"), 0, "跨天清零任务进度")
    -- 签到
    local r1 = Daily.claimSignin(s, t0)
    truthy(r1, "首日应可签")
    eq(s.signin.streak, 1)
    local r2 = Daily.claimSignin(s, t0 + day)
    truthy(r2)
    eq(s.signin.streak, 2, "连续签到应递增")
    eq(Daily.claimSignin(s, t0 + day), nil, "同日不可重复领取")
    local r3 = Daily.claimSignin(s, t0 + day * 5)
    truthy(r3)
    eq(s.signin.streak, 1, "断签应归 1")
    -- 任务
    local def = Config.get("daily_task.tasks", {})[1]
    for _ = 1, (tonumber(def.target) or 1) do
        Daily.bump(s, def.id, 1, t0 + day * 5)
    end
    truthy(Daily.isDone(s, def.id), "任务应达成")
    local got = Daily.claimTask(s, def.id, t0 + day * 5)
    truthy(got, "应能领取")
    eq(Daily.claimTask(s, def.id, t0 + day * 5), nil, "不可重复领取")
    eq(Daily.claimTask(s, "not_done_task", t0 + day * 5), nil, "未达成不可领取")
end)

test("achievements 达成发放且不重复（T19）", function()
    local s = freshSave()
    local def = Config.get("achievements.list", {})[1]
    s.stats.total_levels = tonumber(def.target) or 10
    local gained = Achv.refresh(s)
    eq(#gained, 1, "应达成 1 项")
    eq(gained[1].id, def.id)
    eq(s.gold, tonumber(def.reward_gold) or 0, "应发放奖励金币")
    eq(#Achv.refresh(s), 0, "不应重复发放")
    local done, total = Achv.progress(s)
    eq(done, 1)
    eq(total, #Config.get("achievements.list", {}))
end)

test("challenge 每日限次 + 复用 session（T20）", function()
    cleanupSaveFiles()
    Save.path(TEST_SAVE_PATH)
    local t = 500000
    Time.setTestNow(t)
    local save = Save.default()
    save.stamina_ts = t
    Game.init({ save = save, persist = false })
    local s, err = Game.startChallenge()
    truthy(s, "应能开始挑战: " .. tostring(err))
    eq(Game.mode(), "challenge")
    eq(Challenge.remainingPlays(save, t), 0, "每日仅一次")
    eq(Game.startChallenge(), nil, "第二次应被拒")
    eq(Game.challengeLeft(), Config.num("challenge.time_limit_sec", 180))
    eq(Game.challengeExpired(), false)
    Time.setTestNow(t + Config.num("challenge.time_limit_sec", 180) + 1)
    eq(Game.challengeLeft(), 0, "超时应归零")
    eq(Game.challengeExpired(), true)
    local res = Game.finishChallenge()
    truthy(res, "应能结算")
    eq(Game.mode(), "level", "结算后回到主线模式")
    truthy(res.target > 0, "目标词数应 > 0")
    Time.setTestNow(nil)
    cleanupSaveFiles()
end)

test("game 通关链路：图鉴解锁 + 任务推进 + 官职晋升（T18/T19/T15）", function()
    cleanupSaveFiles()
    Save.path(TEST_SAVE_PATH)
    local t = 600000
    Time.setTestNow(t)
    local save = Save.default()
    save.stamina_ts = t
    Game.init({ save = save, persist = false })
    local s = Game.enterLevel(1)
    truthy(s, "应能进关")
    -- 直接按答案填满（不走提示，验证结算链路）
    local g = s.grid
    for r = 0, g.rows - 1 do
        for c = 0, g.cols - 1 do
            local cell = g:getCell(r, c)
            if cell and cell.answer and cell.value == nil then
                s:fill(r, c, cell.answer)
            end
        end
    end
    eq(save.max_level_passed, 1, "通关应推进进度")
    eq(save.stats.total_levels, 1)
    eq(Book.count(save), #s.levelData.idioms, "本关成语应全部入图鉴")
    eq(Daily.taskProgress(save, "clear_3"), 1, "通关任务应推进")
    eq(Daily.taskProgress(save, "no_hint_2"), 1, "无提示通关应推进")
    truthy(Game.rank().name, "官职应可读")
    truthy(Game.manor().name, "府邸应可读")
    truthy(Game.economyReport().ok, "护栏应通过")
    Time.setTestNow(nil)
    cleanupSaveFiles()
end)

------------------------------------------------------------------------------
-- S3 新增：compliance（T23） / ad（T21） / iap（T22）
------------------------------------------------------------------------------
local Compliance = require("system.compliance")
local Ad = require("ads.ad")
local IAP = require("econ.iap")

-- 测试用时间戳（本地时区构造，仅用于星期/小时判定）
local function tsOf(y, m, d, h, mi)
    return os.time({ year = y, month = m, day = d, hour = h or 12, min = mi or 0, sec = 0 })
end

local function expectedLimit(age)
    for _, l in ipairs(Config.get("iap.limits", {})) do
        if age <= (tonumber(l.age_max) or 0) then return l end
    end
    return nil
end

test("compliance 未实名禁入 + 成年放行（T23）", function()
    local s = freshSave()
    eq(Compliance.isVerified(s), false, "初始应为未实名")
    local ok, reason = Compliance.canPlay(s, tsOf(2026, 10, 23, 20, 30))
    eq(ok, false)
    eq(reason, "realname_required")
    Compliance.setVerified(s, 30)
    eq(s.age_bracket, "adult")
    eq(Compliance.isMinor(s), false)
    eq(Compliance.canPlay(s, tsOf(2026, 10, 26, 20, 30)), true, "成年人不受时段限制")
end)

test("compliance 未成年时段与每日时长（T23）", function()
    local s = freshSave()
    Compliance.setVerified(s, 12)
    eq(s.age_bracket, "minor_8_15")
    local fri = tsOf(2026, 10, 23, 20, 30)     -- 周五 20:30
    local mon = tsOf(2026, 10, 26, 20, 30)     -- 周一 20:30
    eq(Compliance.inAllowedWindow(s, fri), true, "周五 20 点应开放")
    eq(Compliance.inAllowedWindow(s, mon), false, "周一应关闭")
    eq(Compliance.inAllowedWindow(s, tsOf(2026, 10, 23, 19, 0)), false, "非开放小时应关闭")
    local okMon, rMon = Compliance.canPlay(s, mon)
    eq(okMon, false)
    eq(rMon, "minor_out_of_window")
    -- 超时长
    Compliance.tick(s, Compliance.dailyLimitSec(), fri)
    local okOver, rOver = Compliance.canPlay(s, fri)
    eq(okOver, false)
    eq(rOver, "minor_overtime")
    eq(Compliance.remainingMinutes(s, fri), 0)
end)

test("compliance 付费上限按年龄分档（T22）", function()
    local s = freshSave()
    eq(Compliance.paymentLimit(s).monthly_cny, 0, "未实名不得付费")
    Compliance.setVerified(s, 7)
    eq(Compliance.paymentLimit(s).per_payment_cny, 0, "8 岁以下不得付费")
    Compliance.setVerified(s, 12)
    local l12 = Compliance.paymentLimit(s)
    eq(l12.per_payment_cny, tonumber(expectedLimit(12).per_payment_cny))
    eq(l12.monthly_cny, tonumber(expectedLimit(12).monthly_cny))
    Compliance.setVerified(s, 17)
    eq(Compliance.paymentLimit(s).monthly_cny, tonumber(expectedLimit(17).monthly_cny))
    Compliance.setVerified(s, 30)
    truthy(Compliance.paymentLimit(s).monthly_cny > 10000, "成年人不设上限")
end)

test("ad 四点位均有免费出口 + 冷却 + 发奖（T21）", function()
    local placements = Ad.placements()
    eq(#placements, 4, "应为 4 个广告点位")
    for _, p in ipairs(placements) do
        truthy(Ad.hasFreeExit(p.id), p.id .. " 缺少免费出口")
    end
    truthy(Ad.allHaveFreeExit())
    eq(Ad.personalizedForMinor(), false, "未成年人不得个性化投放")

    local s = freshSave()
    local t = 900000
    eq(Ad.canShow(s, "stamina", t), true)
    local r = Ad.grant(s, "stamina", t)
    eq(r.kind, "stamina")
    local okC, rC = Ad.canShow(s, "stamina", t + 1)
    eq(okC, false)
    eq(rC, "cooldown")
    eq(Ad.canShow(s, "stamina", t + Ad.cooldownSec() + 1), true, "冷却结束后应可再看")

    local before = Items.count(s, "hint")
    Ad.grant(s, "hint", t)
    eq(Items.count(s, "hint"), before + Config.num("items.ad_grant.hint", 1))

    s.no_ad = true
    eq(Ad.canShow(s, "stamina", t + Ad.cooldownSec() * 2), false, "去广告后不再展示")
end)

test("iap 未实名/未成年拦截 + 发货记账（T22）", function()
    local s = freshSave()
    local t = 900000
    local products = IAP.products()
    truthy(#products > 0, "应有商品")
    local p = products[1]
    local ok0, r0 = IAP.canBuy(s, p.id, t)
    eq(ok0, false)
    eq(r0, "realname_required")

    Compliance.setVerified(s, 7)
    local ok7, r7 = IAP.canBuy(s, p.id, t)
    eq(ok7, false)
    eq(r7, "blocked_by_age", "8 岁以下应被拦截")

    Compliance.setVerified(s, 12)
    local lim = Compliance.paymentLimit(s)
    local cheap = nil
    for _, q in ipairs(products) do
        local price = tonumber(q.price_cny) or 0
        if price > 0 and price <= lim.per_payment_cny then cheap = q end
    end
    truthy(cheap, "未成年人限内应有可购商品")
    s.gold = 0
    local res = IAP.purchase(s, cheap.id, t)
    truthy(res, "应购买成功")
    eq(s.gold, tonumber(cheap.gold) or 0, "应发放金币")
    eq(IAP.monthSpent(s, t), tonumber(cheap.price_cny) or 0, "应记账")

    -- 月度限额用满后拦截
    s.iap_spend = { month = os.date("%Y%m", t), amount = lim.monthly_cny }
    local okM, rM = IAP.canBuy(s, cheap.id, t)
    eq(okM, false)
    eq(rM, "over_monthly")
end)

------------------------------------------------------------------------------
-- 数据资产门禁（T8 题库 / T24 关卡总量）
------------------------------------------------------------------------------
test("T8 题库字段完整且规模达标", function()
    local text = fs.readText(fs.data("idioms.json"))
    truthy(text, "题库文件应存在")
    local ok, data = pcall(json.decode, text)
    truthy(ok and type(data) == "table", "题库 JSON 应可解析")
    local items = data.items or {}
    truthy(#items >= 800, string.format("题库应 ≥800 条，实际 %d", #items))
    local seen = {}
    for _, e in ipairs(items) do
        local w = e.word or ""
        eq(#util.chars(w), 4, "成语必须四字: " .. w)
        truthy(not seen[w], "成语重复: " .. w)
        seen[w] = true
        truthy((e.pinyin or "") ~= "", "拼音不可为空: " .. w)
        truthy((e.meaning or "") ~= "", "释义不可为空: " .. w)
        truthy(type(e.rare) == "boolean", "rare 必须是布尔: " .. w)
    end
    -- 冷门词要够多，否则高段位关卡凑不出配置里的冷门占比
    local rare = 0
    for _, e in ipairs(items) do if e.rare then rare = rare + 1 end end
    truthy(rare >= 60, string.format("冷门词条应 ≥60，实际 %d", rare))
end)

test("T24 主线 300 关且第 3 段为 7×7", function()
    local text = fs.readText(fs.data("levels/manifest.json"))
    truthy(text, "manifest 应存在")
    local ok, data = pcall(json.decode, text)
    truthy(ok and type(data) == "table", "manifest JSON 应可解析")
    eq(tonumber(data.count), 300, "主线关卡总数")
    eq(#data.levels, 300, "manifest.levels 条目数")
    local seg3 = 0
    for _, rec in ipairs(data.levels) do
        if rec.level_id >= 151 then
            seg3 = seg3 + 1
            eq(rec.size[1], 7, string.format("%04d 行数", rec.level_id))
            eq(rec.size[2], 7, string.format("%04d 列数", rec.level_id))
        end
    end
    eq(seg3, 150, "第 3 段关卡数")
end)

------------------------------------------------------------------------------
-- 输出
------------------------------------------------------------------------------
print(string.format("===== 单测：%d passed，%d failed =====", passed, failed))
if failed > 0 then
    for _, f in ipairs(failures) do
        print(" - " .. f.name .. ": " .. f.err)
    end
    os.exit(1)
end
os.exit(0)
