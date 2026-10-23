-- 关卡批量校验（离线 lua54 运行）。
-- 校验项（DEV §5.1 第 6 步 + P2 约束）：
--   1) JSON 可解析、字段完整
--   2) 成语覆盖不越界、交叉字符一致
--   3) Solver.isDerivable == true（不会卡死玩家）
--   4) 无重复成语
--   5) rare_ratio ≤ 段位阈值
--   6) 网格内无「孤立单字」（每个有字格都至少属于一条成语）
--   7) bank 覆盖全部空位（数量足够）
--   8) 不重复汉字 ≤ config.glyph.max_distinct_chars_per_level（P2）
--
-- CLI:
--   lua54 scripts/tools/verify_levels.lua --all
--   lua54 scripts/tools/verify_levels.lua --level 1

package.path = "scripts/?.lua;" .. package.path

local json = require("core.json")
local fs = require("core.fs")
local util = require("core.util")
local Config = require("core.config")
local Idioms = require("core.idioms")
local Solver = require("core.solver")

local M = {}

local function parseArgs(argv)
    local args = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        if a and a:sub(1, 2) == "--" then
            args[a:sub(3)] = argv[i + 1]
            i = i + 2
        else
            i = i + 1
        end
    end
    return args
end

local function step(dir)
    if dir == "h" then return 0, 1 end
    return 1, 0
end

--- 单关校验；返回 { errors = {...}, warnings = {...} }
function M.verify(levelData)
    local errors, warnings = {}, {}
    local function err(fmt, ...) errors[#errors + 1] = string.format(fmt, ...) end

    if type(levelData) ~= "table" then
        return { errors = { "关卡数据不是 table" }, warnings = {} }
    end
    if type(levelData.idioms) ~= "table" or #levelData.idioms == 0 then
        return { errors = { "缺少 idioms" }, warnings = {} }
    end

    local size = levelData.size or {}
    local rows, cols = size[1] or 0, size[2] or 0
    if rows <= 0 or cols <= 0 then err("size 非法: %s", tostring(size)) end

    -- 2) 覆盖与交叉一致性
    local words = {}
    for _, def in ipairs(levelData.idioms) do
        if words[def.answer] then err("重复成语: %s", tostring(def.answer)) end
        words[def.answer] = true
        local dr, dc = step(def.dir)
        local chars = util.chars(def.answer or "")
        if #chars ~= 4 then err("成语非四字: %s", tostring(def.answer)) end
        for i = 1, #chars do
            local r, c = def.row + dr * (i - 1), def.col + dc * (i - 1)
            if r < 0 or r >= rows or c < 0 or c >= cols then
                err("成语 %s 越界 (%d,%d)", tostring(def.answer), r, c)
            end
        end
    end

    -- 交叉字符一致性由 Grid.new 断言覆盖，这里用 pcall 捕获
    local okGrid, gridOrErr = pcall(require("core.grid").new, levelData)
    if not okGrid then
        err("Grid 构建失败: %s", tostring(gridOrErr))
    end

    -- 3) 可解性
    local derivable, info = Solver.isDerivable(levelData)
    if not derivable then
        err("不可推导（玩家会卡死），停滞成语: %s",
            table.concat((info and info.stalledIdioms) or {}, ","))
    end

    -- 5) 冷门比例
    local segs = Config.get("difficulty.segments", {})
    local seg = nil
    -- 挑战卷走独立阈值（difficulty.challenge），主线按关卡号落段
    if levelData.kind == "challenge" then
        seg = Config.get("difficulty.challenge", {})
    else
        for _, s in ipairs(segs) do
            if levelData.level_id >= (s.from or 0) and levelData.level_id <= (s.to or 0) then
                seg = s
                break
            end
        end
    end
    if seg then
        local rare = 0
        for _, def in ipairs(levelData.idioms) do
            local entry = Idioms.get(def.idiom_ref)
            if entry and entry.rare then rare = rare + 1 end
        end
        local ratio = rare / #levelData.idioms
        if ratio > (seg.rare_ratio or 0) + 1e-9 then
            err("冷门比例 %.2f 超过阈值 %.2f", ratio, seg.rare_ratio or 0)
        end
    end

    -- 6) 孤立单字：所有格子的 owners 非空
    if type(levelData.cells) == "table" then
        for _, cell in ipairs(levelData.cells) do
            if type(cell.owners) ~= "table" or #cell.owners == 0 then
                err("孤立单字 (%s,%s)", tostring(cell.r), tostring(cell.c))
            end
        end
    else
        warnings[#warnings + 1] = "缺少 cells 字段（DEV §3.3 要求 owners 落盘）"
    end

    -- 7) bank 覆盖：空位数 = 覆盖格数 - 预填数
    local covered, presetKeys = 0, {}
    for _, p in ipairs(levelData.presets or {}) do
        presetKeys[p.r .. "," .. p.c] = true
    end
    local seen = {}
    for _, def in ipairs(levelData.idioms) do
        local dr, dc = step(def.dir)
        for i = 1, 4 do
            local key = (def.row + dr * (i - 1)) .. "," .. (def.col + dc * (i - 1))
            if not seen[key] then
                seen[key] = true
                covered = covered + 1
            end
        end
    end
    local blanks = covered - util.countKeys(presetKeys)
    local bankCount = #(levelData.bank or {})
    if bankCount < blanks then
        err("bank 数量 %d < 空位数 %d", bankCount, blanks)
    end

    -- 8) P2 字形预算
    local distinct = Solver.distinctCharCount(levelData)
    local maxDistinct = Config.num("glyph.max_distinct_chars_per_level", 80)
    if distinct > maxDistinct then
        err("不重复汉字 %d 超过 P2 上限 %d", distinct, maxDistinct)
    end

    return { errors = errors, warnings = warnings, distinct = distinct, blanks = blanks }
end

--- 列出全部关卡文件
function M.listLevels()
    local manifestText = fs.readText(fs.data("levels/manifest.json"))
    local out = {}
    if manifestText then
        local ok, manifest = pcall(json.decode, manifestText)
        if ok and type(manifest.levels) == "table" then
            for _, rec in ipairs(manifest.levels) do
                out[#out + 1] = rec.level_id
            end
        end
    end
    if #out > 0 then return out end
    -- 退化：扫目录
    for i = 1, 9999 do
        local path = fs.data(string.format("levels/%04d.json", i))
        if fs.exists(path) then
            out[#out + 1] = i
        elseif i > 1 then
            break
        end
    end
    return out
end

--- 校验每日挑战关卡池（T20）：返回 errorCount, warnCount, count
function M.checkChallenge()
    local pathFmt = Config.get("challenge.path_fmt", "levels/challenge/%03d.json")
    local size = Config.num("challenge.pool_size", 20)
    local errorCount, warnCount, count = 0, 0, 0
    for i = 1, size do
        local path = fs.data(string.format(pathFmt, i))
        local text = fs.readText(path)
        if not text then
            print(string.format("❌ 挑战卷 %03d 文件缺失", i))
            errorCount = errorCount + 1
        else
            count = count + 1
            local ok, data = pcall(json.decode, text)
            if not ok then
                print(string.format("❌ 挑战卷 %03d JSON 解析失败: %s", i, tostring(data)))
                errorCount = errorCount + 1
            else
                local res = M.verify(data)
                for _, e in ipairs(res.errors) do
                    print(string.format("❌ 挑战卷 %03d %s", i, e))
                end
                for _, w in ipairs(res.warnings) do
                    print(string.format("⚠️ 挑战卷 %03d %s", i, w))
                end
                errorCount = errorCount + #res.errors
                warnCount = warnCount + #res.warnings
            end
        end
    end
    return errorCount, warnCount, count
end

--- 平衡报告：按段位比对 config.difficulty 的区间，并统计重复率。
-- 返回 error 数（区间越界）。DEV §0.0.5 把「同一个成语反复出现」列为 Failure State ④。
function M.reportBalance(stats, usage)
    local segs = Config.get("difficulty.segments", {})
    local errors = 0
    print("--- 难度分布（对照 config.difficulty）---")

    local function inSeg(seg, id) return id >= (seg.from or 0) and id <= (seg.to or 0) end
    local function fmtRange(lo, hi) return string.format("%d~%d", lo, hi) end

    for _, seg in ipairs(segs) do
        local n, cross, dist, rare, gridBad = {}, {}, {}, {}, 0
        for _, s in ipairs(stats) do
            if inSeg(seg, s.id) then
                n[#n + 1] = s.n
                cross[#cross + 1] = s.cross
                dist[#dist + 1] = s.distractors
                rare[#rare + 1] = s.rare
                if s.rows ~= seg.grid[1] or s.cols ~= seg.grid[2] then
                    gridBad = gridBad + 1
                end
            end
        end
        if #n == 0 then goto continue_seg end
        table.sort(n); table.sort(cross); table.sort(dist); table.sort(rare)
        local lo, hi = n[1], n[#n]
        print(string.format("  段 %d-%d  %d 关 | 成语 %s (配置 %s) | 交叉 %s (配置 %s) "
            .. "| 干扰字 %s (配置 %s) | 冷门峰值 %.2f (封顶 %.2f) | 网格 %dx%d",
            seg.from, seg.to, #n,
            fmtRange(lo, hi), fmtRange(seg.idiom_count[1], seg.idiom_count[2]),
            fmtRange(cross[1], cross[#cross]), fmtRange(seg.cross[1], seg.cross[2]),
            fmtRange(dist[1], dist[#dist]), fmtRange(seg.distractors[1], seg.distractors[2]),
            rare[#rare], seg.rare_ratio or 0, seg.grid[1], seg.grid[2]))

        if lo < seg.idiom_count[1] or hi > seg.idiom_count[2] then
            print(string.format("  ❌ 段 %d-%d 成语数越界", seg.from, seg.to)); errors = errors + 1
        end
        if cross[1] < seg.cross[1] or cross[#cross] > seg.cross[2] then
            print(string.format("  ❌ 段 %d-%d 交叉数越界", seg.from, seg.to)); errors = errors + 1
        end
        if dist[1] < seg.distractors[1] or dist[#dist] > seg.distractors[2] then
            print(string.format("  ❌ 段 %d-%d 干扰字数越界", seg.from, seg.to)); errors = errors + 1
        end
        if gridBad > 0 then
            print(string.format("  ❌ 段 %d-%d 有 %d 关网格尺寸与配置不符",
                seg.from, seg.to, gridBad)); errors = errors + 1
        end
        ::continue_seg::
    end

    --------------------------------------------------------------------------
    -- 重复率（DEV §0.0.5 Failure State ④）
    --------------------------------------------------------------------------
    local slots, distinct = 0, 0
    local hot = {}
    for w, c in pairs(usage) do
        slots = slots + c
        distinct = distinct + 1
        hot[#hot + 1] = { w = w, c = c }
    end
    table.sort(hot, function(a, b) return a.c > b.c end)
    local over3 = 0
    for _, h in ipairs(hot) do if h.c >= 3 then over3 = over3 + 1 end end
    local top = {}
    for i = 1, math.min(5, #hot) do top[#top + 1] = string.format("%s×%d", hot[i].w, hot[i].c) end
    print(string.format("--- 用词分布 ---  词次 %d / 不重复 %d / 复用率 %.2f；出现≥3次 %d 条；最热 %s",
        slots, distinct, slots / math.max(1, distinct), over3, table.concat(top, "、")))
    return errors
end

function M.runAll()
    local okInit, errInit = Idioms.init(fs.data("idioms.json"))
    if not okInit then
        print("❌ " .. tostring(errInit))
        return 1
    end
    local okCfg, errCfg = Config.load()
    if not okCfg then
        print("❌ " .. tostring(errCfg))
        return 1
    end

    -- 挑战池先校验（T20，与主线同一套规则）
    local chErrors, chWarns, chCount = M.checkChallenge()

    local ids = M.listLevels()
    if #ids == 0 then
        print("⚠️ 没有找到关卡，先跑 levelgen")
        return 1
    end

    local errorCount, warnCount = 0, 0
    -- 平衡校验（T24 验收项「难度分布符合 PRD §3.2.2」）：
    -- 逐关收集实际参数，按段位与 config.difficulty 的区间比对，越界即 error。
    local stats = {}
    local usage = {}

    for _, id in ipairs(ids) do
        local path = fs.data(string.format("levels/%04d.json", id))
        local text = fs.readText(path)
        if not text then
            print(string.format("❌ %04d 文件缺失", id))
            errorCount = errorCount + 1
        else
            local ok, data = pcall(json.decode, text)
            if not ok then
                print(string.format("❌ %04d JSON 解析失败: %s", id, tostring(data)))
                errorCount = errorCount + 1
            else
                local res = M.verify(data)
                if #res.errors > 0 then
                    errorCount = errorCount + #res.errors
                    for _, e in ipairs(res.errors) do
                        print(string.format("❌ %04d %s", id, e))
                    end
                end
                if #res.warnings > 0 then
                    warnCount = warnCount + #res.warnings
                    for _, w in ipairs(res.warnings) do
                        print(string.format("⚠️ %04d %s", id, w))
                    end
                end
                local rare = 0
                for _, def in ipairs(data.idioms or {}) do
                    local entry = Idioms.get(def.idiom_ref)
                    if entry and entry.rare then rare = rare + 1 end
                    usage[def.answer] = (usage[def.answer] or 0) + 1
                end
                stats[#stats + 1] = {
                    id = id,
                    n = #(data.idioms or {}),
                    cross = tonumber(data.crossings) or 0,
                    rare = rare / math.max(1, #(data.idioms or {})),
                    distractors = #(data.distractors or {}),
                    rows = (data.size or {})[1] or 0,
                    cols = (data.size or {})[2] or 0,
                    distinct = res.distinct or 0,
                }
            end
        end
    end

    errorCount = errorCount + M.reportBalance(stats, usage)

    local totalErrors = errorCount + chErrors
    local totalWarns = warnCount + chWarns
    print(string.format("===== 校验完成：%d 关 + %d 张挑战卷，%d error，%d warning =====",
        #ids, chCount, totalErrors, totalWarns))
    return totalErrors == 0 and 0 or 1
end

local function isMainChunk()
    return type(arg) == "table" and type(arg[0]) == "string"
        and arg[0]:match("verify_levels%.lua$") ~= nil
end

if isMainChunk() then
    local args = parseArgs(arg)
    if args.all ~= nil or (args.level == nil and true) then
        os.exit(M.runAll())
    end
    local id = tonumber(args.level)
    Idioms.init(fs.data("idioms.json"))
    Config.load()
    local text = fs.readText(fs.data(string.format("levels/%04d.json", id)))
    local ok, data = pcall(json.decode, text or "")
    local res = M.verify(ok and data or {})
    for _, e in ipairs(res.errors) do print("❌ " .. e) end
    for _, w in ipairs(res.warnings) do print("⚠️ " .. w) end
    os.exit(#res.errors == 0 and 0 or 1)
end

return M
