# 项目长期约定（demo-game / 成语小秀才 复刻）

## 项目事实
- 目录：`/Users/ruoyan/WorkBuddy/2026-10-23-16-44-32`；TapTap Maker 项目，App ID `8c6c5aec-0fbd-4606-b442-56ed62def573`。
- 试玩链接：https://maker.taptap.cn/app/8c6c5aec-0fbd-4606-b442-56ed62def573?localDev=1
  **必须用系统浏览器无痕窗口打开 + `Cmd+Shift+R` 强刷**（内置预览面板缺 WASM/WebGL2；普通模式可能加载旧包）。
- 引擎 Lua **5.4**：语法检查 `luac54`，离线运行 `lua54`。
- 运行时调用三要素：`-tool_mode`（必须）、`-graphicsheadless`（**仅 validate 用**，测图集/截图绝不能带）、`-pp` 不能替代。

## 工具链约定
- **一键验证**：`bash tools/verify.sh`（luac54 语法 → lua54 单测 → 关卡校验 → 引擎 validate）。
  红线：0 error / 0 warning / Layout Warning 0 / `luacheck scripts/` 0/0。
- Maker 直连兜底：`node tools/maker_call.mjs list|schema <tool>|call <tool> '<json>'`；构建用 `maker_build_current_directory`。
- 远端运行日志：`node ~/.taptap-maker/mcp-runtime/0.0.38/dist/maker.js logs watch --target-dir <项目> --interval 5s`
- 本机 `grep` 是 toybox（不支持 `\|`，写 `grep -E "a|b"`）；macOS bash 3.2（中文前用 `${VAR}`）。

## 设计决策（已裁决，勿回退）
- 字形图集 P2：`glyph.max_distinct_chars_per_level=80` + 进关预热（`system/glyphwarm.lua`，必须打 UI 真实上下文）。
- 字体：Noto Sans SC（OFL）；同时提供 `NotoSansSC-*.ttf`（主题）与 `MiSans-*.ttf`（引擎硬编码兜底）两份。
- 可解性判定 `core/solver.lua` 双规则（经典锚点 + 已知字模式筛题库）。
- Yoga：Label 不写百分比高度；分区容器 `flexShrink=1`；**格子边长按「宽∩高」双约束算**，不能只靠 `aspectRatio`（窄屏会溢出）。

## 远端/打包踩坑（血泪，勿重蹈）
1. **wasm 端引擎全局绑定是 userdata 不是 table**：`type(_G.cache)=="table"` 恒 false → 整段能力探测被跳过。一律 `_G.x ~= nil` + pcall。
2. **平台只打包 `assets/` 与 `scripts/`**：数据在 `assets/data/`；每个资源必须有配对 `.meta`（`generate_resource_meta` 批量生成）。
3. **本地 PASS ≠ 打包可跑 / 窄屏 ≠ 本地**：以远端 `runtime.log` 为准；本地 validate 是 1080 宽，窄屏(780)布局问题本地看不见。
4. push 断连 → 本仓库已设 `http.postBuffer=524288000` + `http.version=HTTP/1.1`；`tools/` 是平台资源入口**禁止 git 跟踪**。
5. 字体子集**绝不能按码点序截断**（会砍掉「第/金/马/心」等高频字）；字集 = GB2312 全 6763 ∪ 题库 `word` ∪ Lua 中文文案。改 UI 文案后重跑
   `python3 tools/build_verification_font.py --chars 12000` 并 `cp` 覆盖 MiSans 两份副本。
6. DWP：`.json` 是 render-blocking 启动前预载；`cache:Exists` 只查本地不触发下载；沙箱存档别走 `cache:GetFile`（刷 ERROR 红角标）。**包内资源可读性只能用 `fs.readText` 实测，禁止 `fs.exists` 预判**（设备上 FileExists 对 ResourceCache 恒 false，曾致挑战入口静默失效）。
7. 特效层（全屏 Panel）会拦截点击：默认 `visible=false`，活跃粒子计数归零才隐藏。
8. UI 三律：①多行复合按钮用 Panel+onClick（Button 的单行 auto-fit 会弄乱两行 children）；②列容器定宽子项必须 alignItems="center"；③Label 不自动换行，长文案用 `W.wrapLines` 手动断行。
9. 字体子集采集 = GB2312 ∪ 题库全字段 ∪ **Lua/config 全部非 ASCII 字符**（只扫 CJK 会把 ‹ 　 「」￥ 漏成豆腐块）；门禁分级：源字体有却没收=硬失败。
10. 设备真实视口 base=780x1736（scale 0.791），headless 巡检视口 1322x546；长页必须 ScrollView。
11. 设备运行日志在 `.maker/logs/runtime/runtime.log`（构建后 watcher 每 5s 追加），排查真机问题先看它。

## 进度（2026-10-24 02:30，S1–S4 全部跑完）
- M1 + S1–S4 全部完成并 push：9 个 core 模块、**54 单测**、**300 关** + 20 张挑战卷、题库 **829 条**、
  play/府邸/商店/图鉴/登录 5 页 + 挑战 + 广告弹窗 + 合规闸门。
- 交付文档：`docs/交付说明-成语小秀才.md`（T1–T24 验收表 + 待用户处理清单 + 需目视确认项）。
- 数值一律读 `data/config.json`；逻辑层禁 require UI 模块；问题一律留痕到 `docs/RISK-成语小秀才.md`。

## 生成器与题库（S4 新增的硬约束）
- **`util.rng` 已加 `mixSeed()`**：MINSTD 首个输出对相邻 seed 只差 0.0008%，
  任何「seed+i 重试」的写法都会让重试等价失效（曾导致成语数恒为 4、20% 关卡失败）。
- **题库变更 → 必须重跑 `verify_levels`**：`Solver` 规则 B 用全局题库匹配模式，
  扩库会提高歧义率（曾让挑战卷 003 从可解变不可解），挑战池要重新生成。
- 生成器有 `ctx.usage` 去重复：段 3 复用率 1.12，全量 1.76。
- `levelgen` 的 CLI 无值开关（`--dry-run`）必须放参数列表末尾之外也生效（已修）；
  试跑前先确认 `assets/data/levels/*.json` 数量不变。
- 关卡 .meta：`generate_resource_meta` 单次 paths ≤ 100，批量要分批。

## 待用户处理（非代码可解决）
版号与出版审批、TapTap 后台信息填写与送审、实名/防沉迷资质与 SDK、隐私政策 URL 托管、支付签约与内购 SKU 配置。

## 引擎动画三律（S9 血泪，2026-10-24）
- 关键帧可插值属性只有：opacity/scale/rotate/translateX/translateY/borderRadius/borderWidth/shadow*/颜色。
  **没有 scaleX/scaleY/width/height**——传了会被当不可插值属性在段中点硬切。
- **禁止 onComplete 链式循环**：`Widget:BaseUpdate` 完成分支在 onComplete 之后执行
  `self.animation_ = nil`，把回调里刚创建的下一个动画立刻清掉（实测只走两拍）。
  无限循环一律 `loop = true` + `direction = "alternate"`；换页由 SetRoot(root,true)→Destroy() 注销，无泄漏。
- 动画元素定位基准：opacity 动画的元素起始 `opacity = 0`（禁 visible=false）；
  精确对位贴图部位时挂在同尺寸容器（与图集同框）上用百分比，不要挂全宽容器。
- 冒烟入口 `validate_scholar.lua`（420/740 帧）可验证循环动画存活与定时触发。

## 2D 骨骼动画装配流水线（S10，2026-10-24）
- 部件来源：1 张「纸娃娃分件图」（ImageGen，参考图 + 分件提示词）→ 连通域自动切件，
  风格天然统一、无破洞。注意 `background: transparent` 可能无效（拿到的是不透明白底），
  抠底必须用**从边界漫灌**，不能用全局亮度阈值（会抠掉书页白色）。
- 定位装配：**不要用 ZNCC 模板匹配二值轮廓**（小模板被高密度区吸引，全部挤成一堆）。
  用 `scripts/tools/fit_doll_rig.py`：以合成图剪影为真值，坐标下降优化 cx/cy/scale，
  目标 = 覆盖率 − **逐部件**溢出惩罚（并集 IoU 会让部件互相重叠地膨胀）；
  再加解剖先验 + 有界窗口，否则手臂会跑到腿部去躲惩罚。
- 骨的实现：骨 = 与画框同尺寸的透明 Panel + `transformOrigin={x,y}`（分数）→ 绕关节旋转；
  变换沿渲染树递归继承，所以父骨动会带动子部件。**骨必须 position="absolute"**，
  否则多层 100% 高度的骨在列容器里纵向叠加（实测 320→960 溢出告警）。
- 无法看图时的可视化手段：`scripts/tools/ascii_peek.py`（剪影 ASCII）+
  `fit_doll_rig.py --show`（叠加图 # 重合 / o 溢出 / x 空缺），可量化比对。
- 兜底：config `ui.scholar.mode = rig | image`。

## 书童动画的三版失败与最终路线（S9–S12，2026-10-24）
- S9 单张图+假动效 → 否（要骨骼）｜S10 AI 分件图+剪影拟合骨骼 → 否（"不符合常理"）
  ｜S11 程序化绘制部件骨架 → 否（"太丑"）｜**S12 回到整图 scholar.png**（mode=image）。
- 结论：**此引擎做部件拼装式骨骼性价比极低**（关节接缝/风格不统一/比例不可控）。
  真动画应走**序列帧**：引擎原生 `UI.Sprite` + spritesheet（urhox-libs/UI/Widgets/Sprite.lua、
  Sprite/SpriteSheet.lua），支持 Aseprite/TexturePacker JSON Hash、多动画命名、pivot、无限循环。
  素材流水线：VideoGen 短视频 → ffmpeg 抽帧 → 边界漫灌抠底 → 拼 atlas → 写 sprite.json。
- 整图模式两个坑：①定宽画框在列容器里必须包一层满宽居中容器；②翻页编排不能硬依赖
  骨骼专用引用（foreBone），要按引用存在性分派，否则整图模式翻页永不触发。

## 美术现状（下一阶段主战场）
- `assets/Textures/` 只有 bg_main.png(1.4M) 与 scholar.png(241K) 两张贴图；
  图标/按钮/棋盘/道具/徽章**全是代码画的纯色圆角面板** → 观感像原型。
- 配色 token 在 config.json `ui.color`（38 键，薄荷绿+暖金+朱砂，选中/完成/错误三态语义已定）。
- 包体：Fonts 11M（NotoSansSC 实际渲染 + MiSans 引擎硬编码兜底，两套都不可删）、data 2.8M。

## S13–S15 增量约定（2026-10-25）
- 书童动画：`ui.scholar.mode = sprite`（UI.Sprite 图集，`assets/sprites/scholar/`）；回退 `image`。
  图集由 `scripts/tools/scholar_spritesheet.py` 产出（--from-base 烘焙 / --strip 胶片图 / --video 三模式）；
  **换图集后必须把 SUMMARY 的 kudos_local_frame 回填 config**，再跑 760 帧冒烟。
- 图标接入统一走 `W.iconOrDot(key,size,dot)`：PNG 缺失回退色点；替换同名 PNG 即生效（零代码）。
- 长冒烟：`VALIDATE_FRAMES=760 bash tools/verify.sh validate_scholar.lua`（verify.sh 支持环境变量覆盖）。
- 探针坑：Lua `#` 对非连续整数键关键帧表（[0]/[0.38]/[1]）不可作计数——用 duration 等特征识别。
- 生成积分状态：INSUFFICIENT_BALANCE（AI 图片/视频全阻塞）；`create_video_task` 三次返回
  execution_state=unknown（响应流中断，拿不到 task_id；账单待用户后台核对）。
- git push 到 maker 远端频繁 SSL_ERROR_SYSCALL：`git -c http.version=HTTP/1.1 push` + 退避重试即可。
- bg_main 已量化 256 色（597KB）；若目视有色带可从 git 历史回滚原版。

## 字体分工与包体（S19，2026-11-14）——纠正旧认知
- **旧记忆「MiSans 是引擎硬编码兜底，两套字体都不可删」不准确**：
  `main.lua` 传 `theme="default-dark"`，`urhox-libs/UI/Theme/DefaultDark.lua` 把
  `sans`/`sans-bold` **显式注册到 `Fonts/NotoSansSC-*.ttf`** → 这两份才是渲染字体，必须完整打包。
  MiSans 两份只是引擎二进制硬编码的 fallback 加载路径（缺文件刷 resource error），
  历史上是 NotoSansSC 的字节级副本 → 用 `scripts/tools/make_font_stub.py` 生成 14KB 占位即可。
  因为字集与主字体完全相同，fallback 补不出主字体没有的字 → **零视觉损失省 4.28MB**。
- 查字体真实来源的正确顺序：先看 `UI.Init` 实参里的 theme → 再读主题 `fonts` 表，
  **不能只看 UI.lua 的 else 默认分支**（那是没有主题时的路径）。
- 重跑 `tools/build_verification_font.py` 后会 cp 覆盖回 2MB 副本 → 必须紧接着跑
  `python3 scripts/tools/make_font_stub.py`（`--check` 校验 ≤64KB）。
- `glyphwarm.lua` 的 headless 兜底 FONT_PATH 已改指 NotoSansSC-Regular（占位字体无中文字形）。
- 包体基线：6.92MB（不含 .meta）。`.project/resources.json` 的 `preload_groups=["default"]`
  + `default=["**"]` = 全包启动前预下载；`.project/settings.json` 的 `build.asset_ignores`
  可排除「本地要用但运行时无引用」的文件（如 icon_game.png），路径相对 .project/。
- **未做**：324 个 JSON + 301 个 .meta 仍在启动预载组。`.json` 是 render-blocking，
  且 `cache:Exists` 只查本地不触发下载 → 改 preload 分组会让关卡读不到，别贸然动。
  后续可合并关卡成 pack 再排除单文件（见 RISK 19.0 S19-8）。

## S20（2026-11-15）：书童倍率 + Web 预览环境预检
- 书童播放速度的唯一入口是 `assets/data/config.json` 的 `ui.scholar.speed`（当前 1.6）；
  `home.lua` 的 `scholarSpeed()/flipInterval()` 统一缩放：sprite 的 `SetSpeed` **乘**倍率，
  image 回退的周期/时长（翻页间隔、呼吸、页片、知识++）**除**倍率。
  改倍率后 `validate_scholar.lua` 会自动按倍率算期望间隔，无需改探针。
  实测：知识++ 间隔 300 帧(5s) → 187 帧(3.125s)，760 帧冒烟 4 次触发、0 错误。
- 「加载失败 / 该浏览器不支持游戏所需的运行环境」是 **TapTap 平台 Web 播放器的预检**
  （WebGL2 + SharedArrayBuffer / COOP-COEP 跨源隔离），**不是本仓库 Lua 代码问题**。
  CDP 实测全新普通 Chrome 157：`crossOriginIsolated=true / SAB=function / webgl2=true`，
  即普通模式本身支持；差异来自旧构建缓存/SW/扩展/登录态。
- `?localDev=1` 是**绑定 Maker 登录态的开发者本地预览链接**：未登录会跳 `/intro?returnUrl=...`。
  要让别的浏览器/别人能打开，必须走发布面板「更新测试版」后的公开试玩链接（同 RISK S18-1 阻塞点）。
- 排查清单与全部证据见 `docs/RISK-成语小秀才.md` 20.0 / 20.1。
- 远端构建会自动产生 `chore: wake maker build server` 与 sync 提交 → 构建后需 `git fetch + merge` 再收尾。

## S21（2026-11-15）：书童换成 96 帧真翻页动画（当前线上版本）
- 用户提供 `~/Downloads/fa8bbad603aa45a992ac4de43ea32b5b/` = **96 张 640×640 白底抽帧**
  （VideoGen 产物，先前日志以为「未生成成功」，其实帧已下载到 Downloads）；
  与 `scholar.png` 同一水彩画风，96 帧是完整循环（尾帧≈首帧，翻页在源帧 32–72）。
  源帧已纳入 git：`source_assets/scholar_frames/`（不进游戏包，见 S22）。
- 生成命令（可复跑）：
  `python3 scripts/tools/scholar_spritesheet.py --frames-dir source_assets/scholar_frames --even-frames 32 --kudos-source-frame 72 --frame-max 224 --colors 96 --flip-interval 5 --out assets/sprites/scholar`
  → 32 帧 / 224px / 582KB / 5000ms 等时长 / `kudos_local_frame=24`（已回填 config）。
- **`--even-frames` 路径为什么必须独立**：AI 抽帧相邻差分极小（最大 0.00067@128px），
  普通路径 `DEDUP_MSE=0.0012` 会删光帧；tight union bbox 因角色贴上下边界而放大/越界；
  翻页窗口变速会扭曲匀速动作。`edge_clean`（邻近前景色扩散 + 透明区 RGB 清零）去白边并省 2% 体积。
- 压缩结论：64 色虽只有 469KB 但脸颊/书页明显斑驳 → **禁用**；128色/256px=932KB 超预算；
  最终 96色/224px=582KB，目视与 128 色无差异。输出必须 RGBA 真彩（禁 P-mode）。
- 本轮只替换图集 + `sprite.json` + config 的 `kudos_local_frame`（9→24）+ 工具/文档；
  `home.lua`、speed=1.6、flip_interval=5、布局、其它页面**零改动**。`.meta` uuid/路径不变。
- 验证：760 帧冒烟知识++ 4 次 @141/328/516/703，间隔 187 帧（期望 188=3.125s），0 Lua 错误。
  证据与回滚方法见 `docs/RISK-成语小秀才.md` 21.0。

## S22（2026-11-15 下午）：仓库版本管理整理
- 现状：`main == origin/main`；848 文件已跟踪（assets 705 / scripts 104 / docs 27 /
  .project 8 / 根 4），`.git` 45MB；被忽略未跟踪 1213 个约 328MB（绝大多数是平台/临时文件）。
- **修掉一个真 bug**：`.gitignore` 末尾 Maker 自动追加的**裸 `tools/`** 会命中任意层级同名
  目录，连 `scripts/tools/` 下新建文件都忽略（S21 `git add` 报错就是这个）。已改为 `/tools/`
  + 加 `__pycache__/` `*.pyc`。若 Maker 再次自动追加裸 `tools/`，按注释改回。
- 新建 `source_assets/`（46.7MB）纳入 git：`scholar_frames/` 96 张 + `art_masters/` 11 张 +
  `rig_drafts/` 2 个 + `fonts/` 3 个 + `data/xinhua_idiom.json` + `README.md`。
  `.workbuddy/memory/` 也通过 `/.workbuddy/*` + `!/.workbuddy/memory/` 例外入库。
- **平台打包只认 `.project/settings.json` 的 `asset_dirs: ["../assets","../scripts"]`**：
  `source_assets/` 在根 → 不进游戏包、不受 `default:["**"]` 全量预载影响、无需 `.meta`。
  别把这些源素材搬进 assets/，否则 S19 加载优化白做。
- 硬红线：根 `tools/` 远端 pre-receive 钩子禁止跟踪，不能 `git add -f`；`.cli/` `.installer/`
  `urhox-libs/` `examples/` 等是平台自带，也不入库。
- 生成器/文档/记忆里所有 `.tmp/scholar_video_frames` 路径已统一改成 `source_assets/scholar_frames`。
