-- 生成「每日挑战」关卡池（T20）。
-- 挑战卷子是预生成的：同一天所有玩家拿到同一张卷子，运行时绝不跑生成器
-- （避免耗时抖动与失败分支，见 system/challenge.lua 顶部说明）。
--
-- 用法：
--   lua54 scripts/tools/gen_challenge.lua [--count=20] [--seed=20261024] [--dry-run]

package.path = "scripts/?.lua;" .. package.path

local Config = require("core.config")
local fs = require("core.fs")
local json = require("core.json")
local levelgen = require("tools.levelgen")

local function parseArgs(argv)
    local out = {}
    for _, a in ipairs(argv or {}) do
        local k, v = a:match("^%-%-([%w_%-]+)=?(.*)$")
        if k then out[k] = (v ~= "" and v) or true end
    end
    return out
end

local function main(argv)
    local args = parseArgs(argv)
    local cfgOk, cfgErr = Config.load()
    if not cfgOk then print("❌ " .. tostring(cfgErr)); return 1 end

    local count = tonumber(args.count) or Config.num("challenge.pool_size", 20)
    local seed = tonumber(args.seed) or 20261024
    local seg = Config.get("difficulty.challenge", {})
    seg.kind = "challenge"
    local pathFmt = Config.get("challenge.path_fmt", "levels/challenge/%03d.json")
    local dryRun = args["dry-run"] == true

    print(string.format("挑战池：%d 张，grid=%dx%d，成语 %d~%d，seed=%d",
        count, seg.grid[1], seg.grid[2], seg.idiom_count[1], seg.idiom_count[2], seed))

    local res, err = levelgen.generateRange(1, 1, count, seed, {
        seg = seg,
        pathFmt = pathFmt,
        dryRun = dryRun,
    })
    if not res then print("❌ " .. tostring(err)); return 1 end

    for _, w in ipairs(res.written) do
        print(string.format("  ✅ %-28s 成语 %d，交叉 %d，汉字 %d",
            w.path, #w.level.idioms, w.level.crossings or 0, w.level.distinct_chars or 0))
    end
    for _, f in ipairs(res.failures) do
        print(string.format("  ❌ %04d %s", f.levelId, f.reason))
    end

    if dryRun then return 0 end

    -- 挑战池 manifest（与主线的 levels/manifest.json 分开，避免污染主线 count）
    local manifest = {
        count = #res.written,
        generator = "levelgen v1 (challenge)",
        path_fmt = pathFmt,
        levels = {},
    }
    for _, w in ipairs(res.written) do
        manifest.levels[#manifest.levels + 1] = {
            index = w.levelId,
            file = string.format("%03d.json", w.levelId),
            size = w.level.size,
            idiom_count = #w.level.idioms,
            crossings = w.level.crossings,
            distinct_chars = w.level.distinct_chars,
        }
    end
    local okWrite = fs.writeText(fs.data("levels/challenge/manifest.json"),
        json.encode(manifest) .. "\n")
    if not okWrite then print("❌ manifest 写入失败"); return 1 end
    print(string.format("manifest 已更新：%d 张", #res.written))

    if #res.failures > 0 then
        print(string.format("⚠️ %d 张生成失败", #res.failures))
        return 1
    end
    return 0
end

local function isMainChunk()
    return type(arg) == "table" and type(arg[0]) == "string"
        and arg[0]:match("gen_challenge%.lua$") ~= nil
end

if isMainChunk() then
    os.exit(main(arg))
end

return { main = main }
