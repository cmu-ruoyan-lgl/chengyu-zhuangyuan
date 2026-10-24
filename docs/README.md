# 文档索引（成语小秀才）

> 最后更新：2026-10-24　代码状态：commit `d07595b`（main，与 origin 同步）
> 全部验证口径：`bash tools/verify.sh`（54 单测 / 300 关 + 20 挑战卷 0 error 0 warning / validate PASS）
> + `bash tools/verify.sh validate_pages.lua`（11 站页面巡检，Layout Warning = 0）

## 一、按用途查文档

| 你想做什么 | 读哪个 |
|---|---|
| **接手下一阶段开发** | `docs/交接-下一阶段开发提示词.md`（书童动画 / 美术升级 / 整理 / 上架，含完整提示词） |
| 上架 TapTap | `docs/上架TapTap-操作手册.md`（资质矩阵、认证、打包、送审、驳回规避） |
| 看完成度与待办 | `docs/交付说明-成语小秀才.md`（T1–T24 + 待用户处理清单） |
| 查已知问题与踩坑 | `docs/RISK-成语小秀才.md`（问题/根因/解法/状态；第 5–12 章是 UI 与动画踩坑） |
| 查工程约定与实现 | `docs/DEV-成语小秀才.md` §0 / §16 / §17 |
| 查数值 | `docs/PRD-成语小秀才.md` §3.5 数值总表；运行时真源是 `assets/data/config.json` |
| 项目长期约定与踩坑速查 | `.workbuddy/memory/MEMORY.md` + 当日日志 `.workbuddy/memory/YYYY-MM-DD.md` |

## 二、代码分层

| 目录 | 职责 |
|---|---|
| `scripts/core/` | 纯逻辑：config / grid / idioms / session / solver / util / validator / fs / json |
| `scripts/system/` | 运行时：game（指令层）/ save / challenge / compliance / daily / time / audio / glyphwarm |
| `scripts/econ/` | 金币、道具、内购、体力、门客、经济 |
| `scripts/progress/` | 图鉴、成就、官职、排行 |
| `scripts/ui/` | theme / widgets / nav / modal / admodal / fx / ticker + `pages/*`（home、play、court、shop、book、login） |
| `scripts/tools/` | 关卡生成、校验、单测入口；图像处理与装配工具（`ascii_peek.py`、`fit_doll_rig.py`、`draw_doll.py` 等） |
| `assets/data/` | config.json（数值与配色真源）、题库、300 关 + 20 挑战卷 |
| `assets/Textures/` | 大图（bg_main.png、scholar.png），均已配 `.meta` |
| `assets/sprites/` | 图标与序列帧图集（当前为空，下一阶段填充） |
| `assets/Fonts/` | NotoSansSC（UI 实际字体）+ MiSans（引擎硬编码兜底副本），共 11 MB |

分层铁律：**逻辑层禁止 require UI 模块**；UI 不许直接改存档，一律走 `system/game.lua` 指令。

## 三、美术素材清单（下一阶段待补齐）

| 文件 | 用途 | 状态 |
|---|---|---|
| `assets/Textures/bg_main.png`（1.4 MB） | 主页背景 | 已有 |
| `assets/Textures/scholar.png`（241 KB） | 书童（整图，当前动画用它） | 已有 |
| 图标一套（府邸/挑战/图鉴/商店/体力/金币/返回/关闭/提示/道具×5/官职徽章） | UI 图标 | **缺** |
| 按钮 normal/pressed、卡片、棋盘底板与格子三态 | 控件材质 | **缺**（现为代码绘制纯色面板） |
| 游戏内背景、弹窗遮罩与装饰 | 场景 | **缺** |
| 书童序列帧图集 | 主线动画 | **缺**（用 scholar.png 顶着） |
| 游戏 icon、启动图、商店截图素材 | 上架用 | **缺** |

## 四、常用命令

```bash
bash tools/verify.sh                       # 全量验证（必跑）
bash tools/verify.sh validate_pages.lua    # 11 站页面巡检
luac54 -p scripts/ui/pages/home.lua        # 单文件语法检查
node tools/maker_call.mjs list             # Maker 工具列表（直连兜底）
node tools/maker_call.mjs call maker_build_current_directory '{}'   # 远端构建
node tools/maker_call.mjs call generate_resource_meta '{"target_dir":"<绝对路径>","paths":["assets/..."]}'
python3 tools/build_verification_font.py --chars 12000   # 字体子集重建（改中文文案后必跑）
node ~/.taptap-maker/mcp-runtime/0.0.38/dist/maker.js logs watch --target-dir <项目绝对路径> --interval 5s
```

试玩：https://maker.taptap.cn/app/8c6c5aec-0fbd-4606-b442-56ed62def573?localDev=1
（**系统浏览器无痕窗口 + `Cmd+Shift+R` 强刷**；内置预览面板缺 WASM/WebGL2）
