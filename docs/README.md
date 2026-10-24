# 文档索引（成语小秀才）

> 最后更新：2026-10-25　代码状态：S14 美术升级第一批（main，与 origin 同步）
> 全部验证口径：`bash tools/verify.sh`（54 单测 / 300 关 + 20 挑战卷 0 error 0 warning / validate PASS）
> + `bash tools/verify.sh validate_pages.lua`（11 站页面巡检，Layout Warning = 0）+ `luacheck scripts/` 0/0

## 一、按用途查文档

| 你想做什么 | 读哪个 |
|---|---|
| **接手下一阶段开发** | `docs/交接-下一阶段开发提示词.md`（含完整提示词；S13/S14 已部分消化，接手前先读本文件「五、当前状态」） |
| 上架 TapTap | `docs/上架TapTap-操作手册.md`（资质矩阵、认证、打包、送审、驳回规避） |
| 看完成度与待办 | `docs/交付说明-成语小秀才.md`（T1–T24 + 待用户处理清单） |
| 查已知问题与踩坑 | `docs/RISK-成语小秀才.md`（问题/根因/解法/状态；第 5–14 章是 UI 与动画踩坑） |
| 查工程约定与实现 | `docs/DEV-成语小秀才.md` §0 / §16 / §17 |
| 查数值 | `docs/PRD-成语小秀才.md` §3.5 数值总表；运行时真源是 `assets/data/config.json` |
| 查美术素材 | `docs/美术素材清单.md`（用途/尺寸/体积/引用位置/生成命令） |
| 项目长期约定与踩坑速查 | `.workbuddy/memory/MEMORY.md` + 当日日志 `.workbuddy/memory/YYYY-MM-DD.md` |
| 素材处理流水线命令 | `scripts/tools/README.md`（抠底/拼图集/图标/字体子集） |

## 二、代码分层

| 目录 | 职责 |
|---|---|
| `scripts/core/` | 纯逻辑：config / grid / idioms / session / solver / util / validator / fs / json |
| `scripts/system/` | 运行时：game（指令层）/ save / challenge / compliance / daily / time / audio / glyphwarm |
| `scripts/econ/` | 金币、道具、内购、体力、门客、经济 |
| `scripts/progress/` | 图鉴、成就、官职、排行 |
| `scripts/ui/` | theme / widgets / nav / modal / admodal / fx / ticker + `pages/*`（home、play、court、shop、book、login） |
| `scripts/tools/` | 关卡生成、校验、单测入口 + 素材流水线（`scholar_spritesheet.py`、`make_icons.py` 等，见其 README） |
| `assets/data/` | config.json（数值与配色真源）、题库、300 关 + 20 挑战卷 |
| `assets/Textures/` | 大图（bg_main / scholar / icon_game），均已配 `.meta` |
| `assets/sprites/` | `icons/`（14 枚 UI 图标）+ `scholar/`（书童序列帧图集） |
| `assets/Fonts/` | NotoSansSC（UI 实际字体）+ MiSans（引擎硬编码兜底副本），各 2.14 MB×2 |

分层铁律：**逻辑层禁止 require UI 模块**；UI 不许直接改存档，一律走 `system/game.lua` 指令。

## 三、美术状态（S14 第一批后）

已就位：主页/游戏图标体系（14 枚）、书童序列帧图集、量化瘦身背景、512 上架 icon 首版。
**仍缺（等生成积分充值后 AI 产出）**：图标 AI 精修、按钮 normal/pressed 九宫格、格子三态贴图、
游戏内背景、氛围粒子贴图。清单与体积见 `docs/美术素材清单.md`。

## 四、常用命令

```bash
bash tools/verify.sh                       # 全量验证（必跑）
bash tools/verify.sh validate_pages.lua    # 11 站页面巡检
VALIDATE_FRAMES=760 bash tools/verify.sh validate_scholar.lua   # 书童动画长冒烟
luac54 -p scripts/ui/pages/home.lua        # 单文件语法检查
luacheck scripts/                          # 静态检查（红线 0/0）
node tools/maker_call.mjs list             # Maker 工具列表（直连兜底）
node tools/maker_call.mjs call maker_build_current_directory '{}'   # 远端构建
node tools/maker_call.mjs call generate_resource_meta '{"target_dir":"<绝对路径>","paths":["assets/..."]}'
python3 tools/build_verification_font.py --chars 12000   # 字体子集重建（改中文文案后必跑，见 scripts/tools/README.md）
node ~/.taptap-maker/mcp-runtime/0.0.38/dist/maker.js logs watch --target-dir <项目绝对路径> --interval 5s
```

## 五、当前状态要点（2026-10-25）

1. **书童动画（S13）**：默认 `ui.scholar.mode = "sprite"`（`UI.Sprite` 图集序列帧，
   24 帧 / 320px / 372KB / 循环 5s）。当前帧素材是 `scholar_spritesheet.py --from-base`
   零积分烘焙（视觉与整图模式同源）；**充值后用 ImageGen 出胶片图一键换 AI 帧**
   （命令见 `scripts/tools/README.md`，代码零改动）。回退：config 改 `mode = "image"`。
2. **生成积分已耗尽**（INSUFFICIENT_BALANCE）：AI 图标精修、按钮/格子贴图、游戏内背景
   均阻塞待充值；另 `create_video_task` 三次返回 unknown（上游是否创建了任务/扣费，
   **需在 maker.taptap.cn 后台核对账单**，详见 RISK S13-1/S13-2）。
3. **待真人处理**（清单见 `docs/交付说明-成语小秀才.md` §5）：版号/软著/ICP、实名与防沉迷
   SDK、隐私政策 URL、支付/广告签约、题库 L2/L3 采购、TapTap 后台填写与送审。

试玩：https://maker.taptap.cn/app/8c6c5aec-0fbd-4606-b442-56ed62def573?localDev=1
（**系统浏览器无痕窗口 + `Cmd+Shift+R` 强刷**；内置预览面板缺 WASM/WebGL2）
