-- 离线关卡生成器（lua54 运行，不依赖引擎）。
--
-- 生成流程见 DEV §5.1。本实现在文档之外补了三件必须做的事：
--   1) 交叉数受 config.difficulty.segments[].cross 约束（超出即换候选）；
--   2) 预填格（presets）由「可解性推导」自动补齐 —— 全空棋盘无法起步；
--      推导时用**真实的备选字**（空位字 + 干扰字），否则规则失效；
--   3) 首条成语的位置按「能接出多少交叉候选」打分，避免放下去就接不上。
--
-- P2 约束：单关不重复汉字 ≤ config.glyph.max_distinct_chars_per_level。
--
-- CLI:
--   lua54 scripts/tools/levelgen.lua --seg 1 --from 1 --to 50 --seed 20261023
--   lua54 scripts/tools/levelgen.lua --seg 1 --from 1 --to 5 --dry-run
--   DEBUG_LEVELGEN=1 lua54 scripts/tools/levelgen.lua --seg 1 --from 1 --to 1

package.path = "scripts/?.lua;" .. package.path

local json = require("core.json")
local fs = require("core.fs")
local util = require("core.util")
local Config = require("core.config")
local Idioms = require("core.idioms")
local Solver = require("core.solver")

local M = {}
local DBG = os.getenv("DEBUG_LEVELGEN") ~= nil

local function dbg(fmt, ...)
    if DBG then print(string.format("   [dbg] " .. fmt, ...)) end
end

------------------------------------------------------------------------------
-- 参数
------------------------------------------------------------------------------

-- 说明：CLI 的解析必须支持「无值开关」（--dry-run）。
-- BUGFIX T24-1：旧实现 `args[a:sub(3)] = v` 在开关位于**最后一个参数**时 v 为 nil，
-- 于是 key 根本不会创建，`args["dry-run"] ~= nil` 判为 false —— --dry-run 静默失效，
-- 试跑会真的落盘并污染 manifest。现统一：无值开关置 true。
local function parseArgs(argv)
    local args = {}
    local i = 1
    while i <= #argv do
        local a = argv[i]
        local v = argv[i + 1]
        if type(a) == "string" and a:sub(1, 2) == "--" then
            local key = a:sub(3)
            if type(v) == "string" and v:sub(1, 2) == "--" then v = nil end
            args[key] = v ~= nil and v or true
            i = i + (v ~= nil and 2 or 1)
        else
            i = i + 1
        end
    end
    return args
end

------------------------------------------------------------------------------
-- 题库索引：char -> { {entry, j}, ... }  用于 O(1) 找「第 j 位是某字」的成语
------------------------------------------------------------------------------

local function buildIndex(pool)
    local index = {}
    for _, entry in ipairs(pool) do
        local chars = util.chars(entry.word)
        for j = 1, #chars do
            local ch = chars[j]
            index[ch] = index[ch] or {}
            index[ch][#index[ch] + 1] = { entry = entry, j = j }
        end
    end
    return index
end

--- 只保留「含可交叉字」的成语，缩小搜索空间
local function crossablePool()
    local counts = {}
    for _, e in ipairs(Idioms.all()) do
        for _, ch in ipairs(util.chars(e.word)) do
            counts[ch] = (counts[ch] or 0) + 1
        end
    end
    local out = {}
    for _, e in ipairs(Idioms.all()) do
        local ok = false
        for _, ch in ipairs(util.chars(e.word)) do
            if (counts[ch] or 0) >= 3 then ok = true; break end
        end
        if ok then out[#out + 1] = e end
    end
    if #out == 0 then return Idioms.all() end
    return out
end

------------------------------------------------------------------------------
-- 棋盘布局
------------------------------------------------------------------------------

local function step(dir)
    if dir == "h" then return 0, 1 end
    return 1, 0
end

local function inBounds(layout, r, c)
    return r >= 0 and r < layout.rows and c >= 0 and c < layout.cols
end

--- 判断能否放置；返回 crossings, reason（crossings = 0 表示不可放）
local function canPlace(layout, dir, row, col, chars)
    local dr, dc = step(dir)
    local board = layout.board

    for i = 1, #chars do
        local r, c = row + dr * (i - 1), col + dc * (i - 1)
        if not inBounds(layout, r, c) then return 0, "oob" end
    end

    -- 首尾外侧必须空，避免两条同向成语直接粘连
    local br, bc = row - dr, col - dc
    if inBounds(layout, br, bc) and board[br][bc] then return 0, "head_touch" end
    local er, ec = row + dr * #chars, col + dc * #chars
    if inBounds(layout, er, ec) and board[er][ec] then return 0, "tail_touch" end

    local crossings = 0
    for i = 1, #chars do
        local r, c = row + dr * (i - 1), col + dc * (i - 1)
        local occ = board[r][c]
        if occ then
            if occ.dir == dir then return 0, "parallel_overlap" end
            if occ.char ~= chars[i] then return 0, "char_mismatch" end
            crossings = crossings + 1
        else
            -- 空格：不允许与同向成语相邻（否则视觉上像一条长成语）
            if dir == "h" then
                for _, nr in ipairs({ r - 1, r + 1 }) do
                    if inBounds(layout, nr, c) and board[nr][c] and board[nr][c].dir == "h" then
                        return 0, "parallel_adjacent_h"
                    end
                end
            else
                for _, nc in ipairs({ c - 1, c + 1 }) do
                    if inBounds(layout, r, nc) and board[r][nc] and board[r][nc].dir == "v" then
                        return 0, "parallel_adjacent_v"
                    end
                end
            end
        end
    end
    return crossings, (crossings == 0) and "no_crossing" or nil
end

local function commit(layout, def, chars)
    local dr, dc = step(def.dir)
    for i = 1, #chars do
        local r, c = def.row + dr * (i - 1), def.col + dc * (i - 1)
        layout.board[r][c] = { char = chars[i], dir = def.dir, idiomId = def.id }
    end
    layout.idioms[#layout.idioms + 1] = def
    layout.usedWords[def.answer] = true
end

--- 某个位置放下某词后，还能接出多少条交叉成语（用于首条打分）
local function crossOptions(ctx, layout, wordChars, dir, row, col)
    local dr, dc = step(dir)
    local newDir = (dir == "h") and "v" or "h"
    local ndr, ndc = step(newDir)
    local total = 0
    for i = 1, #wordChars do
        local ar, ac = row + dr * (i - 1), col + dc * (i - 1)
        local ch = wordChars[i]
        local slots = ctx.index[ch]
        if slots then
            for _, slot in ipairs(slots) do
                if not layout.usedWords[slot.entry.word] then
                    local nrow = ar - ndr * (slot.j - 1)
                    local ncol = ac - ndc * (slot.j - 1)
                    if nrow >= 0 and nrow + 3 <= layout.rows - 1
                        and ncol >= 0 and ncol + 3 <= layout.cols - 1 then
                        total = total + 1
                    end
                end
            end
        end
    end
    return total
end

--- 放置第一条：在所有（词, 方向, 起点）组合里按交叉候选数择优
local function placeFirst(ctx, layout, rand, rareRatio)
    local order = {}
    for i = 1, #ctx.pool do order[i] = i end
    util.shuffle(order, rand)

    local best = nil
    for n = 1, math.min(#order, 40) do
        local entry = ctx.pool[order[n]]
        -- 冷门比例护栏：第一条就是冷门会直接突破段位阈值
        if entry.rare and (1 / 1) > rareRatio then goto continue_word end
        -- 去重复（DEV §0.0.5 Failure State ④）：用过的词越少越优先，
        -- 交叉候选数只作为同权重下的次要排序，避免"冷门但好接"的词被反复选中。
        local usage = ctx.usage[entry.word] or 0
        local chars = util.chars(entry.word)
        for _, dir in ipairs(util.shuffle({ "h", "v" }, rand)) do
            local dr, dc = step(dir)
            local maxR = layout.rows - 1 - dr * (#chars - 1)
            local maxC = layout.cols - 1 - dc * (#chars - 1)
            if maxR >= 0 and maxC >= 0 then
                local row, col = rand(maxR + 1) - 1, rand(maxC + 1) - 1
                local score = crossOptions(ctx, layout, chars, dir, row, col)
                if score > 0 then
                    local better = best == nil
                        or usage < best.usage
                        or (usage == best.usage and score > best.score)
                    if better then
                        best = { entry = entry, dir = dir, row = row, col = col,
                                 score = score, usage = usage }
                    end
                end
            end
        end
        if best and best.usage == 0 and best.score >= 8 then break end -- 够用就好
        ::continue_word::
    end

    if not best then return nil end
    local def = {
        id = "w1", dir = best.dir, row = best.row, col = best.col,
        answer = best.entry.word, idiom_ref = best.entry.id,
    }
    if canPlace(layout, def.dir, def.row, def.col, util.chars(def.answer)) < 0 then
        return nil
    end
    commit(layout, def, util.chars(def.answer))
    dbg("首条 %s dir=%s @(%d,%d) 交叉候选=%d", def.answer, def.dir, def.row, def.col, best.score)
    return def
end

--- 放置一条与已有成语交叉的新成语
local function placeCross(ctx, layout, rand, rareCount, totalCount, maxCross, rareRatio)
    local anchors = {}
    for _, def in ipairs(layout.idioms) do
        local dr, dc = step(def.dir)
        local chars = util.chars(def.answer)
        for i = 1, #chars do
            anchors[#anchors + 1] = {
                r = def.row + dr * (i - 1),
                c = def.col + dc * (i - 1),
                char = chars[i],
                fromDir = def.dir,
            }
        end
    end
    util.shuffle(anchors, rand)

    -- 去重复（DEV §0.0.5 Failure State ④）：不再"命中第一个能放的就返回"，
    -- 而是先攒一批可放候选，再挑全批次里被用得最少的那个。
    -- CANDIDATE_CAP 控制搜索广度，SLOT_BUDGET 控制最坏耗时。
    local CANDIDATE_CAP, SLOT_BUDGET = 24, 6000
    local cands, tried, examined = {}, 0, 0

    for _, a in ipairs(anchors) do
        if #cands >= CANDIDATE_CAP or examined >= SLOT_BUDGET then break end
        local newDir = (a.fromDir == "h") and "v" or "h"
        local dr, dc = step(newDir)
        local slots = ctx.index[a.char]
        if slots then
            local order = {}
            for i = 1, #slots do order[i] = i end
            util.shuffle(order, rand)
            for _, si in ipairs(order) do
                if #cands >= CANDIDATE_CAP or examined >= SLOT_BUDGET then break end
                local slot = slots[si]
                local entry = slot.entry
                if not layout.usedWords[entry.word] then
                    local newRare = rareCount + (entry.rare and 1 or 0)
                    if newRare / (totalCount + 1) <= rareRatio then
                        local chars = util.chars(entry.word)
                        local row = a.r - dr * (slot.j - 1)
                        local col = a.c - dc * (slot.j - 1)
                        tried = tried + 1
                        examined = examined + 1
                        local crossings, reason = canPlace(layout, newDir, row, col, chars)
                        if crossings >= 1 and layout.crossings + crossings <= maxCross then
                            cands[#cands + 1] = {
                                entry = entry, dir = newDir, row = row, col = col,
                                chars = chars, crossings = crossings,
                                usage = ctx.usage[entry.word] or 0,
                            }
                        else
                            dbg("拒绝 %s @(%d,%d) 原因=%s", entry.word, row, col, tostring(reason))
                        end
                    end
                end
            end
        end
    end

    if #cands == 0 then
        dbg("无可用交叉（尝试 %d 次）", tried)
        return nil
    end

    -- 使用次数最少优先；同次数时交叉数多的优先（保留"越接越紧"的手感）
    local pick = cands[1]
    for _, c in ipairs(cands) do
        if c.usage < pick.usage or (c.usage == pick.usage and c.crossings > pick.crossings) then
            pick = c
        end
    end

    local def = {
        id = "w" .. (#layout.idioms + 1),
        dir = pick.dir, row = pick.row, col = pick.col,
        answer = pick.entry.word, idiom_ref = pick.entry.id,
    }
    commit(layout, def, pick.chars)
    layout.crossings = layout.crossings + pick.crossings
    dbg("接入 %s dir=%s @(%d,%d) 交叉+%d 已用%d次",
        pick.entry.word, pick.dir, pick.row, pick.col, pick.crossings, pick.usage)
    return def, pick.entry.rare and 1 or 0
end

------------------------------------------------------------------------------
-- 备选字与预填
------------------------------------------------------------------------------

--- 当前预填方案下的空位字（每个空位一块）
local function blankCharsFor(base, presets)
    local presetKeys = {}
    for _, p in ipairs(presets or {}) do
        presetKeys[p.r .. "," .. p.c] = true
    end
    local out, seen = {}, {}
    for _, def in ipairs(base.idioms) do
        local dr, dc = step(def.dir)
        local chars = util.chars(def.answer)
        for i = 1, #chars do
            local key = (def.row + dr * (i - 1)) .. "," .. (def.col + dc * (i - 1))
            if not seen[key] then
                seen[key] = true
                if not presetKeys[key] then out[#out + 1] = chars[i] end
            end
        end
    end
    return out
end

local function withPresets(base, presets, distractors)
    local copy = util.deepcopy(base)
    copy.presets = presets
    local bank = blankCharsFor(base, presets)
    for _, ch in ipairs(distractors or {}) do bank[#bank + 1] = ch end
    copy.bank = bank
    return copy
end

--- 自动补齐预填格，使关卡可推导
local function augmentPresets(base, rand, distractors)
    local maxRatio = Config.num("difficulty.presets.max_ratio", 0.4)
    local minCount = Config.num("difficulty.presets.min_count", 1)

    local seen, cellCount = {}, 0
    for _, def in ipairs(base.idioms) do
        local dr, dc = step(def.dir)
        for i = 1, 4 do
            local key = (def.row + dr * (i - 1)) .. "," .. (def.col + dc * (i - 1))
            if not seen[key] then seen[key] = true; cellCount = cellCount + 1 end
        end
    end
    local maxPresets = math.max(minCount, math.floor(cellCount * maxRatio))

    local presets = {}
    for _ = 1, 64 do
        local candidate = withPresets(base, presets, distractors)
        local ok, info = Solver.isDerivable(candidate)
        if ok then
            if #presets >= minCount then return presets end
        end
        if #presets >= maxPresets then
            dbg("预填达上限 %d/%d 仍不可解", #presets, maxPresets)
            return nil
        end
        -- 从停滞成语里挑一个还没预填的格子补上
        local stalled = (info and info.stalledIdioms) or {}
        local target = nil
        for _, id in ipairs(stalled) do
            for _, def in ipairs(base.idioms) do
                if def.id == id then
                    local dr, dc = step(def.dir)
                    local chars = util.chars(def.answer)
                    local order = {}
                    for i = 1, #chars do order[i] = i end
                    util.shuffle(order, rand)
                    for _, i in ipairs(order) do
                        local r, c = def.row + dr * (i - 1), def.col + dc * (i - 1)
                        local dup = false
                        for _, p in ipairs(presets) do
                            if p.r == r and p.c == c then dup = true; break end
                        end
                        if not dup then target = { r = r, c = c, char = chars[i] }; break end
                    end
                end
                if target then break end
            end
            if target then break end
        end
        if not target then
            dbg("无停滞成语可补，但仍有未完成项")
            return nil
        end
        presets[#presets + 1] = target
    end
    return nil
end

------------------------------------------------------------------------------
-- 生成单关
------------------------------------------------------------------------------

--- 生成单关；失败返回 nil + 原因
function M.generate(levelId, seg, rand, ctx)
    local rows, cols = seg.grid[1], seg.grid[2]
    local layout = {
        rows = rows, cols = cols, board = {}, idioms = {},
        usedWords = {}, crossings = 0,
    }
    for r = 0, rows - 1 do layout.board[r] = {} end

    local targetIdioms = rand(seg.idiom_count[2] - seg.idiom_count[1] + 1) + seg.idiom_count[1] - 1
    local rareCount = 0
    local maxCross = seg.cross and seg.cross[2] or 2
    local rareRatio = seg.rare_ratio or 0

    if not placeFirst(ctx, layout, rand, rareRatio) then
        return nil, "首条成语放置失败（题库交叉能力不足）"
    end

    local guard = 0
    while #layout.idioms < targetIdioms do
        guard = guard + 1
        if guard > 12 then break end
        local def, addedRare = placeCross(ctx, layout, rand, rareCount, #layout.idioms,
            maxCross, rareRatio)
        if not def then break end
        rareCount = rareCount + (addedRare or 0)
    end

    if #layout.idioms < seg.idiom_count[1] then
        return nil, string.format("成语数不足 (%d < %d)", #layout.idioms, seg.idiom_count[1])
    end
    if layout.crossings < (seg.cross[1] or 0) then
        return nil, string.format("交叉数不足 (%d < %d)", layout.crossings, seg.cross[1])
    end

    --------------------------------------------------------------------------
    -- 组装
    --------------------------------------------------------------------------
    local base = {
        level_id = levelId,
        segment = seg.index,
        size = { rows, cols },
        idioms = {},
        presets = {},
        bank = {},
        distractors = {},
        rare_ratio = rareCount / #layout.idioms,
        generated_by = "levelgen v1",
    }
    -- kind：挑战卷标记（每日挑战校验走 difficulty.challenge 阈值，而非主线段位）
    if seg.kind then base.kind = seg.kind end
    for _, def in ipairs(layout.idioms) do
        base.idioms[#base.idioms + 1] = {
            id = def.id, dir = def.dir, row = def.row, col = def.col,
            answer = def.answer, idiom_ref = def.idiom_ref,
        }
    end

    -- 干扰字：先定，预填推导时带上（否则推导会过于乐观）
    local dmin, dmax = seg.distractors[1], seg.distractors[2]
    local dcount = rand(dmax - dmin + 1) + dmin - 1
    local allChars = {}
    for _, e in ipairs(ctx.pool) do
        for _, ch in ipairs(util.chars(e.word)) do
            allChars[#allChars + 1] = ch
        end
    end
    for _ = 1, dcount do
        base.distractors[#base.distractors + 1] = allChars[rand(#allChars)]
    end

    local presets = augmentPresets(base, rand, base.distractors)
    if not presets then
        return nil, "无法在预填上限内保证可解性"
    end
    base.presets = presets

    local bank = blankCharsFor(base, presets)
    for _, ch in ipairs(base.distractors) do bank[#bank + 1] = ch end
    util.shuffle(bank, rand)
    base.bank = bank

    --------------------------------------------------------------------------
    -- 校验
    --------------------------------------------------------------------------
    local distinct = Solver.distinctCharCount(base)
    local maxDistinct = Config.num("glyph.max_distinct_chars_per_level", 80)
    if distinct > maxDistinct then
        return nil, string.format("不重复汉字 %d 超过 P2 上限 %d", distinct, maxDistinct)
    end
    if not Solver.isDerivable(base) then
        return nil, "可解性校验失败"
    end

    base.cells = M.buildCells(base)
    base.distinct_chars = distinct
    base.crossings = layout.crossings
    return base
end

--- 生成 cells（含 owners），DEV §3.3 要求它是交叉关系的唯一数据源
function M.buildCells(level)
    local map, order = {}, {}
    local function touch(r, c, id)
        local key = r .. "," .. c
        local cell = map[key]
        if not cell then
            cell = { r = r, c = c, owners = {} }
            map[key] = cell
            order[#order + 1] = cell
        end
        if not util.contains(cell.owners, id) then
            cell.owners[#cell.owners + 1] = id
        end
    end
    for _, def in ipairs(level.idioms) do
        local dr, dc = step(def.dir)
        for i = 1, 4 do
            touch(def.row + dr * (i - 1), def.col + dc * (i - 1), def.id)
        end
    end
    for _, p in ipairs(level.presets or {}) do
        local cell = map[p.r .. "," .. p.c]
        if cell then cell.preset = true end
    end
    table.sort(order, function(a, b)
        if a.r == b.r then return a.c < b.c end
        return a.r < b.r
    end)
    return order
end

------------------------------------------------------------------------------
-- 批量
------------------------------------------------------------------------------

function M.generateRange(segIndex, fromId, toId, seed, opts)
    opts = opts or {}
    local okInit, errInit = Idioms.init(fs.data("idioms.json"))
    if not okInit then return nil, errInit end
    local okCfg, errCfg = Config.load()
    if not okCfg then return nil, errCfg end

    local segs = Config.get("difficulty.segments", {})
    -- opts.seg：允许调用方直接注入难度段（每日挑战用 difficulty.challenge 预设）
    local seg = opts.seg or segs[segIndex]
    if not seg then return nil, "难度段不存在: " .. tostring(segIndex) end
    seg.index = seg.index or segIndex

    local pool = crossablePool()
    -- usage：整批生成过程中的用词计数（只在关卡最终产出后才累加，重试不计），
    -- 驱动 placeFirst / placeCross 的"少用优先"，压低 300 关的重复率。
    local ctx = { pool = pool, index = buildIndex(pool), usage = {} }
    dbg("题库 %d 条，可交叉 %d 条，索引字 %d 个", #Idioms.all(), #pool, util.countKeys(ctx.index))

    local written, failures = {}, {}

    for levelId = fromId, toId do
        local produced, reason = nil, "未知"
        for attempt = 1, 120 do
            local rand = util.rng(seed * 7919 + levelId * 1000 + attempt)
            local level, errGen = M.generate(levelId, seg, rand, ctx)
            if level then
                produced = level
                break
            end
            reason = errGen or reason
        end
        if not produced then
            failures[#failures + 1] = { levelId = levelId, reason = reason }
        else
            for _, def in ipairs(produced.idioms) do
                ctx.usage[def.answer] = (ctx.usage[def.answer] or 0) + 1
            end
            local path = fs.data(string.format(opts.pathFmt or "levels/%04d.json", levelId))
            if not opts.dryRun then
                local okWrite, errWrite = fs.writeText(path, json.encode(produced) .. "\n")
                if not okWrite then
                    failures[#failures + 1] = { levelId = levelId, reason = tostring(errWrite) }
                else
                    written[#written + 1] = { levelId = levelId, path = path, level = produced }
                end
            else
                written[#written + 1] = { levelId = levelId, path = path, level = produced }
            end
        end
    end

    return { written = written, failures = failures, segment = seg }
end

--- 更新 manifest
function M.updateManifest(entries)
    local path = fs.data("levels/manifest.json")
    local manifest = { version = 1, generator = "levelgen v1", levels = {} }
    local text = fs.readText(path)
    if text then
        local ok, existing = pcall(json.decode, text)
        if ok and type(existing) == "table" then
            manifest = existing
            manifest.levels = manifest.levels or {}
        end
    end
    local index = {}
    for i, e in ipairs(manifest.levels) do index[e.level_id] = i end
    for _, e in ipairs(entries) do
        local rec = {
            level_id = e.levelId,
            file = string.format("%04d.json", e.levelId),
            segment = e.level.segment,
            size = e.level.size,
            idiom_count = #e.level.idioms,
            crossings = e.level.crossings,
            distinct_chars = e.level.distinct_chars,
        }
        local at = index[e.levelId]
        if at then manifest.levels[at] = rec else manifest.levels[#manifest.levels + 1] = rec end
    end
    table.sort(manifest.levels, function(a, b) return a.level_id < b.level_id end)
    manifest.count = #manifest.levels
    fs.writeText(path, json.encode(manifest) .. "\n")
    return manifest
end

------------------------------------------------------------------------------
-- CLI
------------------------------------------------------------------------------

local function main(argv)
    local args = parseArgs(argv)
    local segIndex = tonumber(args.seg) or 1
    local fromId = tonumber(args.from) or 1
    local toId = tonumber(args.to) or fromId
    local seed = tonumber(args.seed) or 20261023
    local dryRun = args["dry-run"] ~= nil

    local result, err = M.generateRange(segIndex, fromId, toId, seed, { dryRun = dryRun })
    if not result then
        print("❌ " .. tostring(err))
        return 1
    end

    for _, e in ipairs(result.written) do
        local lv = e.level
        print(string.format("✅ %04d  成语%d 交叉%d 预填%d 备选%d 不重复字%d",
            e.levelId, #lv.idioms, lv.crossings or 0, #(lv.presets or {}), #lv.bank,
            lv.distinct_chars or 0))
    end
    for _, f in ipairs(result.failures) do
        print(string.format("❌ %04d  %s", f.levelId, f.reason))
    end

    if not dryRun and #result.written > 0 then
        M.updateManifest(result.written)
        print(string.format("manifest 已更新：%d 关写入/更新", #result.written))
    end

    if #result.failures > 0 then
        print(string.format("⚠️ %d 关生成失败", #result.failures))
        return 1
    end
    return 0
end

-- 直接执行判定：主 chunk 里 arg[0] 是脚本自身路径
local function isMainChunk()
    return type(arg) == "table" and type(arg[0]) == "string"
        and arg[0]:match("levelgen%.lua$") ~= nil
end

if isMainChunk() then
    os.exit(main(arg))
end

return M
