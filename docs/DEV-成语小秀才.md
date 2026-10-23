# 《成语小秀才》复刻版 开发文档（Agent 可执行版）

配套文档：`docs/PRD-成语小秀才.md`（产品定义、数值 rationale、验收指标）
本版本：v0.2 · 目标用户 **全年龄泛用户** · 策略 **1:1 复刻原版**

---

## 0. 如何使用本文档

### 0.0 开工前必读（新会话 Agent 的第一件事，按顺序读）

| 顺序 | 文件 | 读什么 |
|---|---|---|
| 1 | 本文档 §0、§16、§17 | 执行规则、任务清单、自测命令 |
| 2 | `docs/PRD-成语小秀才.md` §3.5 | 数值总表（数值冲突以此为准） |
| 3 | `docs/RISK-成语小秀才.md` §1.6 + 第 3 章 | 未解决清单 + 24 条默认裁决 |
| 4 | `.workbuddy/memory/MEMORY.md` | **项目长期约定**：运行时三要素、P2 字形方案、Yoga 三个坑、可解性双规则 |
| 5 | `.workbuddy/memory/2026-10-23.md` | M1 实施记录与已踩过的坑（含 Lua、bash、Yoga、探针） |

> 第 4、5 条里的坑是**花了一整个晚上才试出来的**，不读必然重踩。

### 0.0.1 增量开发禁令（禁止返工）

M1 已完成并通过全链路验证，**以下产物只做增量扩展，不得重写**：

| 产物 | 状态 |
|---|---|
| `scripts/core/*.lua`（9 个模块） | 23 项单测全绿 |
| `scripts/tools/levelgen.lua` + `verify_levels.lua` | 150 关，0 error / 0 warning |
| `scripts/ui/pages/play.lua`、`ui/theme.lua`、`main.lua` | 引擎 validate PASS，Layout Warning 0 |
| `data/idioms.json`（189 条）、`data/config.json`、`data/levels/*.json` | 已入库 |

- 已生成的 150 关**不得全量重生成**（除非校验失败）；
- 每次改动后必跑 `bash tools/verify.sh`，且必须维持 **0 error / 0 warning / validate PASS**；
- 需要改既有模块的**行为**时，先写清"为什么要改"再动手。

### 0.0.2 分阶段交付（禁止一口气跑完 T1–T24）

一次会话跑完全部 24 个任务必然中途降级或上下文溢出。按阶段推进，**每阶段结束必须 commit 并汇报**：

| 阶段 | 任务 | 阶段验收（不过不得进入下一阶段） |
|---|---|---|
| **S1 可玩核心** | T3、T9、T10、T11、T12、T13 | 新号 → 连续通关 10 关 → 存档杀进程不丢、体力生效、金币结算与 config 一致 |
| **S2 系统层** | T14–T20 | 五种道具全通、官职/府邸/门客曲线正确、30 天模拟不通胀 |
| **S3 商业化与合规** | T21–T23 | 4 个广告点位可用且有免费出口、未成年拦截生效、未实名禁入 |
| **S4 内容与平衡** | T8（扩库）、T24（300 关） | 见 §0.0.5 的题库硬约束 |

### 0.0.3 上线边界（能做什么、不能做什么，禁止伪造完成状态）

| Agent 能做 | 必须由用户/平台侧处理（Agent 只列清单，不得假装完成） |
|---|---|
| `maker_build_current_directory` 构建与提交代码 | **版号与出版审批** |
| 生成远端 Web 预览链接（可试玩） | TapTap 开发者后台：游戏信息、简介、分级、送审 |
| 生成图标/截图/音频素材 | 实名认证与防沉迷的**资质申请与 SDK 配置** |
| 本地 `taptap-maker preview` 窗口预览 | 隐私政策 URL 托管、支付签约、内购 SKU 后台配置 |

### 0.0.4 视觉验证的替代通路（不得跳过，也不得谎称已验证）

Agent 上下文**拿不到 WindowServer**，任何截图脚本都出不了图（已实测：去掉 `-validate` 直接 `-screenshot` 也不行）。UI 改动后必须：

1. 跑 `bash tools/verify.sh`，保证 **Layout Warning = 0**、missing_resources 为空；
2. 在汇报里单列「需用户目视确认」项，并给出命令：`bash tools/screenshot.sh`。

### 0.0.5 题库是当前唯一的硬瓶颈（数据，2026-10-23 实测）

150 关共 456 词次，**只用到 112 条不重复成语**（题库有 189 条，但受交叉约束只有 59% 能被放进棋盘）。最热的词出现 **16 次**，出现 ≥3 次的有 **59 条**。记忆型玩法里第三次见到同一个词，学习快感就没了 —— 这是 Failure State ④。

因此**扩库优先级高于扩关**：

- T8 的 800 条不是"锦上添花"，是 300 关体验的**前置条件**；
- 关卡数扩到 300 之前，先把题库做到 ≥600 条，否则重复率会击穿体验；
- 同时要提高生成器的词可用率（当前 59%），否则扩库收益打折。

### 0.1 给 Agent 的执行规则（必须遵守）

1. **先读 PRD 再动手**：本文档解决"怎么做"，PRD 解决"为什么这么做"。遇到数值冲突以 PRD 第 3.5 节数值总表为准。
2. **按第 16 章任务清单顺序执行**（T1 → T24），每个任务末尾有验收条件，**未通过不得进入下一任务**。
3. **数值一律不写死在代码里**，全部读 `data/config.json`。代码中出现数字常量（除 0/1/循环边界外）视为缺陷。
4. **UI 层不得持有游戏状态**，**逻辑层不得 require UI 模块**。违反此条的代码必须重构。
5. **每次改动后必须跑第 17 章的自测命令**，把输出贴回给用户。
6. 本文档未定义的数值/行为，标记为 `[NEEDS-DECISION]` 并向用户提问，**禁止自行假设**。
7. **禁止绕过验证链**：`bash tools/verify.sh` 不通过时，不允许"先继续做下一项，之后再补"。
8. **素材降级优先**：AI 生成图/音需要配额与时间，先用程序化降级（纯色 Panel + 文字 + NanoVG 绘制）保证功能可跑，素材生成并行推进，**配额不足不得阻塞开发**。

### 0.2 硬性禁止事项

| 禁止 | 原因 |
|---|---|
| 在 Lua 源码中硬编码成语、关卡、价格 | 破坏数据驱动，后续无法运营调整 |
| 用 `os.time()` 做体力恢复基准 | 本地时间可被改；须用服务端时间或单调时钟 + 服务端校准 |
| 在逻辑层直接调用 `UI.xxx` | 分层约束 |
| 生成未通过可解性校验的关卡 | 玩家卡死即 Failure State ① |
| 跳过 M0 技术验证 | 中文渲染若不达标，后面全部返工 |

---

## 1. 技术栈与工程约束

| 项 | 值 |
|---|---|
| 引擎 | TapTap Maker（UrhoX） |
| 脚本 | Lua 5.4 |
| UI | `urhox-libs/UI`（Yoga 布局 + NanoVG 渲染，40+ 控件） |
| 存档 | 本地 `file-storage` + 云存档 `clientCloud` / `serverCloud` |
| 编码 | 全项目 UTF-8，禁止 GBK |
| 屏幕基准 | 竖屏 1080×1920，Yoga 使用百分比布局，禁止硬编码像素 |
| 资源配置 | `assets/image`、`assets/audio`，meta 由 `generate_resource_meta` 生成，禁止手写 UUID |

**关键前置风险（M0 必须验证）**：
- 中文字体加载方式、字库体积、全屏汉字渲染帧率；
- 6×6 网格 + 全屏汉字在目标机型是否稳定 60fps；
- 存档写入/读取往返一致性。

---

## 2. 目录结构（完整，按此创建）

```
demo-game/
├── assets/
│   ├── image/          格子底、格子高亮、按钮、府邸 L1-L6、门客头像、官职徽章
│   ├── audio/          fill_ok.wav / fill_err.wav / idiom_done.wav / cross_ok.wav / level_win.wav
│   └── sprites/
├── data/
│   ├── config.json          全部数值（唯一数值来源）
│   ├── idioms.json          题库（含释义/出处/难度/标签）
│   ├── ranks.json           官职 8 阶定义
│   ├── manor.json           府邸 6 级定义
│   ├── followers.json       门客定义（含产出）
│   ├── items.json           道具定义
│   ├── achievements.json    成就定义
│   ├── dailyquests.json     每日任务定义
│   ├── signin.json          7 日签到奖励
│   └── levels/
│       ├── manifest.json    关卡索引（含难度段映射）
│       ├── 0001.json … 0300.json
│       └── challenge_*.json 支线典故挑战关
├── scripts/
│   ├── main.lua             入口：初始化 UI、加载存档、进入 Boot
│   ├── app/
│   │   ├── state.lua        全局状态机（AppState 枚举 + 转换）
│   │   └── router.lua       页面路由
│   ├── core/                纯逻辑，不依赖 UI
│   │   ├── grid.lua         网格模型
│   │   ├── validator.lua    成语/通关判定
│   │   ├── session.lua      单关会话状态机
│   │   ├── idioms.lua       题库索引与查询
│   │   └── solver.lua       可解性校验（关卡生成与运行时兜底）
│   ├── econ/
│   │   ├── stamina.lua      体力（时间戳恢复）
│   │   ├── currency.lua     金币收支
│   │   ├── items.lua        道具库存与使用
│   │   └── followers.lua    门客挂机产出
│   ├── progress/
│   │   ├── rank.lua         官职晋升
│   │   ├── manor.lua        府邸升级
│   │   ├── book.lua         成语图鉴 + 错题本
│   │   └── achievement.lua  成就判定
│   ├── system/
│   │   ├── save.lua         存档读写 + 版本迁移
│   │   ├── time.lua         时间基准（服务端校准）
│   │   ├── realname.lua     实名（合规必做）
│   │   ├── antiaddiction.lua 防沉迷（合规必做）
│   │   └── analytics.lua    埋点上报
│   ├── shop/
│   │   ├── iap.lua          内购（含未成年付费上限校验）
│   │   └── ad.lua           广告点位封装
│   ├── ui/
│   │   ├── theme.lua        主题（字号/颜色/间距，含大字模式）
│   │   ├── common/          Cell.lua / HanziBlock.lua / TopBar.lua / Dialog.lua
│   │   └── pages/           login / home / levelmap / play / result / stamina_gate
│   │                        / shop / book / followers / daily / settings
│   └── tools/
│       ├── levelgen.lua     离线关卡生成器
│       └── verify_levels.lua 关卡批量校验
└── docs/
    ├── PRD-成语小秀才.md
    └── DEV-成语小秀才.md
```

---

## 3. 数据层规范

### 3.1 `data/config.json`（数值唯一来源）

```json
{
  "version": 1,
  "stamina": { "max": 50, "cost_per_level": 5, "recover_interval_sec": 360, "ad_reward": 10 },
  "gold": {
    "base_per_level": 10,
    "bonus_per_unused_hint": 5,
    "streak_threshold": 3,
    "streak_multiplier": 2
  },
  "hints": { "free_per_day": 3, "price_gold": 20, "max_per_level": 3 },
  "items": { "shuffle_price": 15, "skip_price": 30, "double_duration_sec": 1800 },
  "difficulty": {
    "segments": [
      { "from": 1,   "to": 50,  "grid": [4,4], "idiom_count": [2,3], "cross": [1,2], "rare_ratio": 0.08, "distractors": [0,2] },
      { "from": 51,  "to": 150, "grid": [6,6], "idiom_count": [3,4], "cross": [2,4], "rare_ratio": 0.18, "distractors": [2,4] },
      { "from": 151, "to": 300, "grid": [7,7], "idiom_count": [4,6], "cross": [4,8], "rare_ratio": 0.25, "distractors": [4,6] }
    ],
    "challenge": { "grid": [8,8], "idiom_count": [5,7], "cross": [5,8], "rare_ratio": 0.40, "distractors": [6,8] }
  },
  "economy_guard": { "idle_output_ratio_cap": 0.30 }
}
```

### 3.2 `data/idioms.json`

```json
{
  "meta": { "version": 1, "count": 3800 },
  "items": [
    {
      "id": "i0001",
      "word": "毛骨悚然",
      "pinyin": "máo gǔ sǒng rán",
      "meaning": "形容非常恐惧的样子。",
      "source": "……",
      "example": "……",
      "level": 2,
      "rare": false,
      "tags": ["情绪"]
    }
  ]
}
```

> `level`：1=高频 / 2=中频 / 3=冷门。`rare = (level == 3)`，供生成器按 `rare_ratio` 控制。

### 3.3 `data/levels/0001.json`

```json
{
  "level_id": 1,
  "segment": 1,
  "size": [4, 4],
  "idioms": [
    { "id": "h1", "dir": "h", "row": 0, "col": 0, "answer": "一马当先", "idiom_ref": "i0123" },
    { "id": "v1", "dir": "v", "row": 0, "col": 1, "answer": "马到成功", "idiom_ref": "i0456" }
  ],
  "cells": [
    { "r": 0, "c": 0, "char": "一", "owners": ["h1"] },
    { "r": 0, "c": 1, "char": "马", "owners": ["h1", "v1"] }
  ],
  "bank": ["一", "马", "当", "先", "到", "成", "功", "人", "山"],
  "distractors": ["人", "山"],
  "rare_ratio": 0.0,
  "generated_by": "levelgen v1"
}
```

**字段纪律**：
- `cells[].owners` 是交叉关系与"交叉点亮"动画的唯一数据源，**不可省略**；
- `bank` 必须包含全部目标字符（去重后），外加 `distractors`；
- `idiom_ref` 关联题库，用于结算页展示释义。

### 3.4 存档 `save.json`

```json
{
  "schema_version": 1,
  "player_id": "uuid",
  "realname_status": "verified",
  "age_bracket": "adult",
  "rank_id": "xiucai",
  "manor_level": 2,
  "followers": [{ "id": "f_lisbai", "level": 3 }],
  "stamina": 35,
  "stamina_ts": 1792747387243,
  "gold": 1200,
  "items": { "hint": 2, "shuffle": 1, "skip": 0, "double": 0 },
  "max_level_passed": 87,
  "hints_used_today": 1,
  "daily_reset_ts": 1792747387243,
  "signin": { "streak": 3, "last_claim_day": 20261023 },
  "book": { "unlocked": ["i0001"], "wrong": ["i0888"] },
  "achievements": { "xuefu_wuche": { "progress": 5, "done": false } },
  "settings": { "big_text": false, "sound": true, "music": true },
  "stats": { "total_levels": 87, "total_wrong": 41 },
  "current": {
    "level_id": 87,
    "grid": { "levelData": "…关卡快照…", "values": [{ "r": 1, "c": 2, "char": "马" }] },
    "bank": [{ "char": "马", "used": true }],
    "hints_used": 1,
    "wrong_count": 2
  }
}
```

> `current`（S1 新增）：中断续玩快照。每次填字/撤销/提示后刷新，通关或跳过置 `null`；
> 启动时若存在则以 `Session.resume` 恢复且**不重复扣体力**。字段随 schema v1 一起首发（未对外发布过旧版）。

**迁移约定**：`schema_version` 递增时必须在 `scripts/system/save.lua` 中追加 `migrate_vN_to_vN1()`，禁止就地改结构而丢旧档。

---

## 4. 核心模块设计

### 4.1 `scripts/core/grid.lua`

```lua
local Grid = {}
Grid.__index = Grid

-- 由关卡数据构建运行时网格
function Grid.new(levelData) --> Grid
-- 查询
function Grid:getCell(r, c)        --> {char, owners, filled, value}
function Grid:idiomsOfCell(r, c)   --> {idiomId, ...}
function Grid:isCrossPoint(r, c)   --> boolean   -- #owners > 1
function Grid:size()               --> rows, cols

-- 写入与撤销
function Grid:setValue(r, c, char) --> boolean   -- 空位才可写
function Grid:clearCell(r, c)      --> boolean

-- 序列化（供存档中断续玩）
function Grid:snapshot()           --> table
function Grid.restore(snapshot)    --> Grid
```

**运行时结构**（内存中）：

```lua
grid = {
  rows = 6, cols = 6,
  cells = { [r] = { [c] = { owners = {"h1","v1"}, answer = "马", value = nil } } },
  idioms = { h1 = { dir="h", row=0, col=0, answer="一马当先", done=false } },
  filledCount = 0, totalBlanks = 24
}
```

### 4.2 `scripts/core/validator.lua`

```lua
-- 单条成语是否已完整且正确
function Validator.checkIdiom(grid, idiomId) --> boolean, {cells = {...}}

-- 全关是否通过
function Validator.checkLevel(grid) --> boolean

-- 单格写入后的增量校验：返回本次因该格而完成的所有成语
function Validator.onCellFilled(grid, r, c) --> {completedIdiomIds = {...}, newlyValidCross = {...}}
```

**算法**：`checkIdiom` 取该成语覆盖的 4 个格子，若全部 `value ~= nil` 且拼接串 `== answer`，标记 `done = true`。`onCellFilled` 只检查该格 `owners` 列表中的成语（O(1)，不做全量扫描）。

### 4.3 `scripts/core/session.lua`（单关状态机）

```
Idle → CellSelected → (选字) → Filled → [检查 owners] → (完成成语?) → IdiomCompleted
                                                      → (全完成?)   → LevelCleared
Filled → (撤销) → Idle
任意状态 → (体力不足) → StaminaGate
任意状态 → (停滞 ≥60s 且无免费提示) → HintOffer
```

```lua
function Session.start(levelId, ctx)   --> Session   -- ctx 含 stamina/items 服务
function Session:selectCell(r, c)      --> boolean
function Session:fill(char)            --> FillResult { ok, completedIdioms, cleared }
function Session:undo()                --> boolean
function Session:useHint()             --> { r, c, char }  -- 返回应填位置
function Session:useShuffle()          --> newBankOrder
function Session:useSkip()             --> nil
function Session:abandon()             --> ProgressSnapshot  -- 中途退出保存
```

**Session 输出事件**（供 UI/音频/埋点订阅，逻辑层只发事件不碰 UI）：

```
on_cell_filled(correct) / on_idiom_completed(idiomId) / on_cross_validated(r,c)
on_level_cleared(reward) / on_hint_used / on_undo / on_invalid
```

### 4.4 `scripts/core/solver.lua`（可解性校验）

用途：① 关卡生成时剔除不可推导的关；② 运行时兜底（若玩家填错导致死局，提示可"修正"）。

```lua
-- 模拟"锚点推理"：反复填补"仅剩一个空位"的成语，直到无进展
function Solver.isDerivable(levelData) --> boolean, { stalledIdioms = {...} }
```

**算法**：
```
repeat
  for each idiom with exactly 1 unfilled blank:
     fill it (from bank)
     propagate to cross cells
until no progress
return allFilled
```
若 `isDerivable == false`，说明关卡存在"必须先猜"的部分 → 生成器丢弃该关。

### 4.5 `scripts/core/idioms.lua`

```lua
function Idioms.init(path)
function Idioms.get(refId)              --> idiomEntry
function Idioms.byLevel(level, tags)    --> {entries}
function Idioms.randomByDifficulty(seg, rareRatio) --> entry
```

启动时建立「首字/尾字 → 成语」索引，供接龙规则与生成器快速查询。

---

## 5. 关卡生成器（离线工具 `scripts/tools/levelgen.lua`）

### 5.1 生成算法

```
输入：seg（难度段）、seed、题库
1. 取网格尺寸 N×N（来自 config.difficulty.segments）
2. 放置第 1 条成语：随机选方向 + 合法起点
3. 循环放置后续成语：
   a. 从已放置成语中挑一个未使用的字符作为交叉候选
   b. 以该字符为"包含字"检索题库中可放置的成语（方向相反）
   c. 校验：不越界、不与已有成语非法重叠、交叉字符一致
   d. 若接龙规则启用：校验首尾相接
   e. 失败则回溯重试（限 maxRetry）
4. 达成目标条数 → 生成 cells（含 owners）与 bank
5. 加干扰字：从同难度层随机取字，数量取 config 区间
6. 校验（全部通过才落盘）：
   - Solver.isDerivable == true
   - 无重复成语
   - rare_ratio ≤ 段位阈值
   - 网格内无"孤立单字"（不属于任何成语的填充格）
7. 写入 data/levels/XXXX.json + 更新 manifest.json
```

### 5.2 CLI

```bash
lua scripts/tools/levelgen.lua --seg 1 --from 1 --to 50 --seed 20261023
lua scripts/tools/verify_levels.lua --all        # 批量校验，失败关卡列出
```

**验收**：`verify_levels --all` 输出 `0 error` 才允许进入 M1 之后的阶段。

---

## 6. 经济与进度模块

### 6.1 `econ/stamina.lua`

```lua
function Stamina.current(save, nowTs) --> int      -- 按 recover_interval_sec 计算恢复量
function Stamina.consume(save, amount) --> boolean -- 不足返回 false，由 UI 弹出 StaminaGate
function Stamina.addByAd(save)         --> boolean -- 受 config.stamina.ad_reward 限制
```

**纪律**：恢复基准时间必须来自 `system/time.lua`（服务端时间校准），不得用本地 `os.time()`；离线恢复上限 = `max`，不可溢出。

### 6.2 `econ/currency.lua`

```lua
function Currency.add(save, amount, reason)   -- reason 用于埋点
function Currency.spend(save, amount, reason) --> boolean
function Currency.settleLevel(save, { unusedHints, streak }) --> rewardTable
```

结算公式（读 config）：
```
gold = base_per_level + bonus_per_unused_hint * unusedHints
if streak >= streak_threshold then gold = gold * streak_multiplier end
```

### 6.3 `econ/followers.lua`

```lua
function Followers.tick(save, nowTs) --> collectedGold   -- 挂机产出结算
function Followers.recruit(save, followerId) --> boolean
function Followers.upgrade(save, followerId) --> boolean
```

**通胀护栏（必须实现）**：门客总挂机产出 ≤ 主动游玩产出的 `idle_output_ratio_cap`（默认 0.30）。实现为在 `tick` 中按玩家近期活跃产出做上限裁剪，超出部分不予发放并记埋点 `idle_capped`。

### 6.4 `progress/rank.lua` / `manor.lua` / `book.lua` / `achievement.lua`

| 模块 | 关键函数 | 数据 |
|---|---|---|
| rank | `Rank.evaluate(save)` → 是否晋升 + 新阶 | `data/ranks.json`（8 阶，累计关卡阈值见 PRD §3.4） |
| manor | `Manor.upgrade(save)` → boolean | `data/manor.json`（6 级，成本 100/300/800/2000/5000） |
| book | `Book.unlock(save, idiomRef)` / `Book.addWrong(save, idiomRef)` | 图鉴 + 错题本 |
| achievement | `Achievement.check(save, event)` | `data/achievements.json` |

---

## 7. 道具系统

| 道具 | 函数 | 规则 |
|---|---|---|
| 提示 | `Items.useHint(session)` | 优先扣每日免费额度（`hints_used_today < free_per_day`），超出则扣库存或金币；单关上限 `max_per_level` |
| 撤销 | `Session:undo()` | **无限次**，无消耗（降低全年龄试错成本，PRD §3.3.1） |
| 洗牌 | `Items.useShuffle(session)` | 重排 bank 顺序，不改变解 |
| 跳过 | `Items.useSkip(session)` | 直接通关，**不产出金币**（防刷） |
| 双倍 | `Items.activateDouble(save)` | 限时 `double_duration_sec`，期间结算 ×2 |

道具获取：`signin.json`（签到）、`dailyquests.json`（每日任务）、金币购买、广告奖励、成就奖励。

---

## 8. 养成系统

| 系统 | 数据文件 | 与核心玩法耦合点 |
|---|---|---|
| 官职（8 阶） | `ranks.json` | 累计通关数达阈值即晋升；晋升节点与难度台阶（第 50/150 关）对齐 |
| 府邸（6 级） | `manor.json` | 消耗金币；每级提供金币产出加成与立绘变化 |
| 门客（N 名） | `followers.json` | 消耗金币招募/升级；按小时产出金币（受通胀护栏约束） |

**实现纪律**：三者都只读 `save` 与 `data/*.json`，不得反向调用 `core` 模块。

---

## 9. 支线玩法模块

| 玩法 | 优先级 | 实现要点 |
|---|---|---|
| 每日挑战（限时 10 词） | P0 | 复用 `core/session`，`data/levels/challenge_*.json`，每日按 seed 轮换 |
| 错题本 / 成语图鉴 | P0 | `progress/book.lua` + 结算页释义卡 |
| 看图猜成语 | P1 | 复用题库，新增图片资源与 4 选 1 交互 |
| 好友 PK / 排行榜 | P2 | 依赖平台社交能力，M3 前评估 |
| 成语接龙 | P2 | 复用 `Idioms` 首尾索引 |

---

## 10. UI 层

### 10.1 页面清单与路由

| 页面 | 路径 | 主要职责 |
|---|---|---|
| login | `ui/pages/login.lua` | 实名、适龄提示、健康忠告 |
| home | `ui/pages/home.lua` | 府邸立绘 + 官职 + 入口（闯关/每日/图鉴/门客/商店/设置） |
| levelmap | `ui/pages/levelmap.lua` | 关卡进度、章节分段 |
| play | `ui/pages/play.lua` | **核心**：状态条 + 矩阵 + 备选区 + 道具栏 |
| result | `ui/pages/result.lua` | 金币结算 + 成语释义卡 + 下一关 |
| stamina_gate | `ui/pages/stamina_gate.lua` | 等待 / 广告 / 道具补体力（**必须保留免费出口**） |
| book | `ui/pages/book.lua` | 图鉴 + 错题本 |
| followers | `ui/pages/followers.lua` | 招募/升级 |
| shop | `ui/pages/shop.lua` | 内购（含未成年付费上限校验） |
| daily | `ui/pages/daily.lua` | 每日挑战、签到、每日任务 |
| settings | `ui/pages/settings.lua` | 大字模式、音效、账号 |

### 10.2 `play` 页 widget 树

```
Root (Column, 100%)
├── TopBar (8%)            : stamina | gold | levelNo | rankBadge
├── BoardArea (48%)        : Grid (rows × cols)
│   └── Cell (flex)        : bg + Label(char) + crossHighlight
├── BankArea (26%)         : Wrap grid of HanziBlock
│   └── HanziBlock         : min 88px 触控区, 选中/已用状态
└── ToolBar (12%)          : HintBtn | UndoBtn | ShuffleBtn
```

**布局纪律**：全部使用 Yoga 百分比/弹性布局；字号、颜色、间距统一从 `ui/theme.lua` 读取，支持「大字模式」整体缩放（PRD §3.3.1）。

### 10.3 反馈事件映射（PRD §3.3.3）

| Session 事件 | 视觉 | 音频 | 触觉 |
|---|---|---|---|
| `on_cell_filled(true)` | 格子填充 + 笔画动画 | fill_ok | 振动 10ms |
| `on_cell_filled(false)` | 抖动 + 红描边 | fill_err | 无 |
| `on_idiom_completed` | 整条流光 | idiom_done | 振动 15ms |
| `on_cross_validated` | 交叉格辉光 | cross_ok | 振动 20ms |
| `on_level_cleared` | 全矩阵点亮 + 金币飞入 | level_win | 无 |

所有响应必须在 **100ms 内**触发。

---

## 11. 存档系统

```lua
function Save.load()            --> saveTable   -- 损坏则回退上一版备份
function Save.write(save)       --> boolean     -- 原子写：tmp → rename
function Save.migrate(save)     --> saveTable   -- schema_version 递增迁移
function Save.cloudSync(save)   --> boolean     -- clientCloud / serverCloud
```

**纪律**：
- 每次写入先写 `.tmp` 再 rename，防断电损坏；
- 保留上一版备份 `save.json.bak`；
- 云存档冲突以 `max_level_passed` 与 `stamina_ts` 较大者为准，并记录 `save_conflict` 埋点。

---

## 12. 音频与反馈

音频文件放 `assets/audio`，通过 Audio 模块播放；`settings.sound/music` 控制开关，写入存档。
触觉为移动端能力，需确认 TapTap Maker 侧支持；若不支持，降级为"视觉抖动增强"（记为 `[NEEDS-DECISION]`）。

---

## 13. 商业化

### 13.1 广告点位（`shop/ad.lua`）

| 点位 | 触发 | 奖励 |
|---|---|---|
| 体力补充 | stamina_gate 点击 | `+ad_reward` 体力 |
| 提示奖励 | 免费额度用尽后 | +1 提示 |
| 双倍金币 | 结算页 | 本次结算 ×2 |
| 关卡间插屏 | 每 N 关一次 | 无（纯曝光，N 待定 `[NEEDS-DECISION]`） |

**合规**：不得有"不看完无法继续"的强制逻辑；未成年账号不展示个性化广告。

### 13.2 内购 SKU（`shop/iap.lua`）

| SKU | 内容 |
|---|---|
| 金币包 ×3 档 | 小额 / 中额 / 大额 |
| 去广告 | 移除插屏 |
| 门客礼包 | 门客 + 金币 |
| 月卡 | 每日返还金币 |

**付费前必须调用** `system/realname.lua` 的年龄分段接口，命中未成年则按上限拦截（PRD §5.1）。

---

## 14. 合规模块（必做，不可裁剪）

| 模块 | 函数 | 说明 |
|---|---|---|
| `realname.lua` | `Realname.status()` / `Realname.ageBracket()` | 未实名禁止进入游戏 |
| `antiaddiction.lua` | `AntiAddiction.canPlay(nowTs)` / `.tick()` | 未成年仅周五六日及节假日 20:00–21:00，每日 1 小时；到点强制下线提示 |
| `iap.lua` | 付费上限校验 | 见 PRD §5.1 表格 |
| `login.lua` | 适龄提示 + 健康忠告 | 启动页展示 |

---

## 15. 埋点（`system/analytics.lua`）

```
level_start(level_id, segment)
level_end(level_id, duration_ms, hints_used, wrong_count, cleared)
cell_fill(level_id, correct)
stamina_gate_show / stamina_gate_action(action)   -- action: wait|ad|item
ad_request(placement) / ad_complete(placement)
hint_used(source)           -- source: free|item|gold
rank_up(from, to) / manor_upgrade(to_level) / follower_recruit(id)
wrong_book_add(idiom_ref) / book_open
iap_attempt(sku) / iap_blocked(reason)
idle_capped(amount)         -- 通胀护栏触发
age_bracket_stat(bracket)   -- 仅统计用
```

**纪律**：埋点字段含年龄分段，用于分年龄段看指标（PRD §7.1）。

---

## 16. 实施任务清单（按顺序执行，逐条验收）

| # | 任务 | 产出 | 验收条件 |
|---|---|---|---|
| T1 | 中文字体渲染验证 | 验证脚本 + 截图 | 全屏汉字清晰、无豆腐块、帧率 ≥55fps |
| T2 | 6×6 网格 UI 原型 | `ui/pages/play.lua` 骨架 | 布局按 §10.2，触控区 ≥88px |
| T3 | 存档读写往返 | `system/save.lua` | 写→读一致，模拟断电不损坏 |
| T4 | `core/grid.lua` | 网格模型 | 单测：set/clear/owners 正确 |
| T5 | `core/validator.lua` | 判定逻辑 | 单测：成语完成、通关判定 |
| T6 | `core/solver.lua` | 可解性校验 | 对不可解样例返回 false |
| T7 | `tools/levelgen.lua` | 生成器 | 生成 50 关，`verify_levels` 0 error |
| T8 | `data/idioms.json` L1 800 条 | 题库 | 字段完整，释义非空 |
| T9 | `core/session.lua` | 关卡状态机 | 事件序列正确，undo 无损 |
| T10 | play 页接入 session | 可玩核心 | 手动通关 5 关无异常 |
| T11 | 反馈通道（音/视/触） | 音频 + 动画 | 响应 <100ms |
| T12 | `econ/stamina.lua` + 时间校准 | 体力 | 离线恢复正确，改系统时间不生效 |
| T13 | `econ/currency.lua` + 结算 | 金币 | 结算公式与 config 一致 |
| T14 | 道具系统 | items | 提示/撤销/洗牌/跳过/双倍 全通 |
| T15 | `progress/rank.lua` | 官职 8 阶 | 阈值与 PRD §3.4 一致 |
| T16 | `progress/manor.lua` | 府邸 6 级 | 成本曲线正确 |
| T17 | `econ/followers.lua` + 护栏 | 门客 | `idle_capped` 生效，30 天模拟不通胀 |
| T18 | 图鉴 + 错题本 + 释义卡 | book | 结算页可查看释义/出处 |
| T19 | 签到 + 每日任务 + 成就 | 三系统 | 每日重置正确 |
| T20 | 每日挑战（限时 10 词） | daily | 复用 session |
| T21 | 广告点位接入 | ad | 4 个点位可用，有免费出口 |
| T22 | 内购 + 付费上限 | iap | 未成年拦截生效 |
| T23 | 实名 + 防沉迷 | system | 未实名禁入；超时下线提示 |
| T24 | 全量 300 关 + 平衡校验 | levels | `verify_levels --all` 0 error，难度分布符合 §3.1 |

---

## 17. 自测命令（每次改动后必跑）

> ⚠️ 引擎内嵌 **Lua 5.4**，离线工具必须用 `lua54` / `luac54`（brew 默认 `lua` 是 5.5，语义有差异）。

```bash
# 0. 一键全量（推荐：语法 + 单测 + 关卡校验 + 引擎 validate）
bash tools/verify.sh

# 1. 语法检查（全量 Lua）
for f in $(find scripts -name "*.lua"); do luac54 -p "$f" || echo "SYNTAX FAIL: $f"; done

# 2. 关卡校验
lua54 scripts/tools/verify_levels.lua --all

# 3. 关卡生成（指定段位）
lua54 scripts/tools/levelgen.lua --seg 2 --from 51 --to 60 --seed 1

# 4. 核心逻辑单测
lua54 scripts/tools/run_tests.lua

# 5. 静态检查
luacheck scripts

# 6. 题库重建（拼音由 pypinyin 生成）
python3 tools/build_idioms.py
```

### 17.1 M1 实施记录（2026-10-23 21:30）

| 交付 | 路径 | 结果 |
|---|---|---|
| 题库种子 | `data/idioms.json` | 189 条，唯一汉字 388 |
| 数值唯一来源 | `data/config.json` | 含 `glyph.*`（P2）与 `ui.*` |
| 核心逻辑 | `scripts/core/*` | 9 个模块，纯逻辑可离线单测 |
| 单测 | `scripts/tools/run_tests.lua` | 23 passed / 0 failed |
| 关卡生成 | `scripts/tools/levelgen.lua` | 段位 1–2 共 150 关 |
| 关卡校验 | `scripts/tools/verify_levels.lua` | 0 error / 0 warning |
| play 页 | `scripts/ui/pages/play.lua` | 引擎内挂载成功，Layout Warning 0 |
| 字形预热 | `scripts/system/glyphwarm.lua` | 进关预热本关字形（P2） |
| 关卡数据 | `data/levels/*.json` + `manifest.json` | 150 关，单关不重复汉字 ≤ 17 |

**冒烟清单（人工）**：
1. 新号进入 → 实名 → 首关完成 → 晋升童生
2. 连续通关至体力耗尽 → StaminaGate → 等待/广告两条路均可用
3. 填错 → 撤销 → 无损恢复
4. 提示用尽 → 付费/广告路径 → 单关上限生效
5. 杀进程重进 → 进度、体力、金币一致

---

## 18. 编码规范与禁忌

| 规范 | 说明 |
|---|---|
| 文件 UTF-8，无 BOM | 中文注释允许 |
| 模块返回 table，不污染全局 | `local M = {} ... return M` |
| 逻辑层禁止 `require("urhox-libs/UI")` | 分层约束 |
| 数值禁止硬编码 | 一律 `Config.get("gold.base_per_level")` |
| 事件驱动，UI 订阅逻辑层事件 | 逻辑层不得直接调用 UI 函数 |
| 每个模块顶部写职责注释（3 行内） | 便于 agent 后续维护 |
| 错误用返回值，不用 `error()` 抛 | 逻辑层保持可测试 |

**原 `[NEEDS-DECISION]` 项已裁决**（见 `docs/RISK-成语小秀才.md` 第 3 章「默认裁决表」，共 24 条）：
1. 触觉反馈 → 按**不可用**处理，降级为视觉抖动增强
2. 插屏广告频次 → **每 5 关一次**（进 config，可调）
3. 中文字体 → 引擎内置 `Fonts/MiSans-Regular.ttf`，不内嵌；不依赖粗体
4. 排行榜 → **MVP 不接**
5. 大字模式 → **默认关闭**，字号 ×1.2，切换时重建当前页

**⚠️ 第 17 章自测命令需重写**：本机无 `lua` / `luac`，`lua`/`luac -p` 命令无法执行。离线工具链（levelgen / verify_levels / 题库构建 / 音频合成 / 经济模拟）改用 **Python** 实现；Lua 运行时验证改用 `run-lua-validate`（先跑 `python3 .cli/install-urhox-runtime.py --dest .cli`）。
