# 项目长期约定（成语小状元 / 原成语小秀才，TapTap Maker + UrhoX Lua）

## 项目事实与双远端
- 目录 `/Users/ruoyan/WorkBuddy/2026-10-23-16-44-32`；App ID `8c6c5aec-0fbd-4606-b442-56ed62def573`；
  `.project/project.json` 里 `project_id=m_x7qf`、`app_id=996762`、`miniapp_id=tapmc2hfuqyeejniq6`、`developer_id=504802`。
- 试玩链接 https://maker.taptap.cn/app/8c6c5aec-0fbd-4606-b442-56ed62def573?localDev=1
  **必须用系统浏览器无痕窗口 + `Cmd+Shift+R`**（内置预览缺 WASM/WebGL2；普通模式可能读旧缓存）。
  `localDev=1` 绑定 Maker 登录态，未登录跳 `/intro` → 别人要看得走发布面板「更新测试版」后的公开链接。
- **双远端（S23）**：`origin` = Maker（构建/自动同步靠它），`github` = `git@github.com:cmu-ruoyan-lgl/chengyu-zhuangyuan.git`
  （公开仓库，SSH 免密）。推 GitHub 用 `git push github main`，**不要 `-u`**；main 必须继续追踪 origin/main。
- 引擎 Lua **5.4**：`luac54` 语法 / `lua54` 单测。运行时三要素：`-tool_mode`（必须）、`-graphicsheadless`
  （**仅 validate**，测图集/截图绝不能带）、`-pp` 不能替代。

## 工具链
- 一键验证 `bash tools/verify.sh`（语法→54 单测→300 关→引擎 validate）；红线 0 error / 0 warning /
  Layout Warning 0 / `luacheck scripts/` 0-0。长冒烟 `VALIDATE_FRAMES=760 bash tools/verify.sh validate_scholar.lua`。
- Maker 直连 `node tools/maker_call.mjs list|schema <tool>|call <tool> '<json>'`；构建 `maker_build_current_directory`
  （**只出网页预览包，不发布真机测试通道**）。远端日志 `node ~/.taptap-maker/mcp-runtime/0.0.38/dist/maker.js logs watch --target-dir <项目> --interval 5s`；
  设备运行日志在 `.maker/logs/runtime/runtime.log`。
- 官方 CLI：`npx -y @taptap/cli`（本机在 `~/.npm/_npx/*/node_modules/.bin/taptap-cli`），`auth status` 常为未配置；
  `auth login --no-wait --json` 出设备码（5 分钟），需用户在浏览器点确认，再 `--device-code ... --expires-at-unix ...` 轮询。
- 本机 `grep` 是 toybox（不支持 `\|`，用 `grep -E "a|b"`）；macOS bash 3.2；`timeout` 命令不存在；
  解二维码用 macOS Vision（swift `VNDetectBarcodesRequest`），cv2/pyzbar 都没装。
- 远端构建会自动产生 `chore: wake maker build server` 与 sync 提交 → 构建后须 `git fetch + merge` 再收尾。

## 硬红线（血泪，勿重蹈）
1. **wasm 端引擎全局是 userdata 不是 table**：`type(_G.cache)=="table"` 恒 false。一律 `_G.x ~= nil` + pcall。
2. **平台只打包 `assets/` 与 `scripts/`**（`.project/settings.json` 的 asset_dirs），数据在 `assets/data/`，
   每个资源必须有配对 `.meta`（`generate_resource_meta` 单次 paths ≤100，批量分批）。
   根目录 `source_assets/` 不进包、不受预载影响、无需 .meta —— **别把源素材搬进 assets/**。
3. **本地 PASS ≠ 打包可跑 / 窄屏 ≠ 本地**：以远端 runtime.log 为准；本地 validate 1080 宽，
   设备真实视口 base=780x1736（scale .791），headless 巡检 1322x546，长页必须 ScrollView。
4. push 频繁 SSL_ERROR_SYSCALL → `git -c http.version=HTTP/1.1 push` + 退避重试；已设 postBuffer=524288000。
   根 `tools/` 是平台资源入口，远端 pre-receive 钩子**禁止跟踪**；`.gitignore` 里 Maker 会自动追加**裸 `tools/`**
   （会连 `scripts/tools/` 一起忽略），已改 `/tools/` + `__pycache__/` `*.pyc`，若被覆盖按注释改回。
5. **字体子集**：字集 = GB2312 全 6763 ∪ 题库全字段 ∪ **Lua/config 全部非 ASCII 字符**（只扫 CJK 会漏
   `‹ 　 「」￥–％℃×` 成豆腐块）；**绝不能按码点序截断**（会砍掉「第/金/马/心」）。改 UI 文案后
   重跑 `python3 tools/build_verification_font.py --chars 12000`，**必须紧接着**跑
   `python3 scripts/tools/make_font_stub.py`（否则 cp 会把 MiSans 覆盖回 2MB）；门禁「源字体有却没收」=硬失败。
6. **包内资源可读性只能用 `fs.readText` 实测，禁止 `fs.exists` 预判**（设备上 FileExists 对
   ResourceCache 恒 false，曾致挑战入口静默失效）。`.json` 是 render-blocking 预载；
   `cache:Exists` 只查本地不触发下载 → 别贸然改 preload 分组；沙箱存档别走 `cache:GetFile`。
7. 特效层（全屏 Panel）会拦截点击：默认 `visible=false`，活跃粒子计数归零才隐藏。
8. **UI 三律**：①多行复合按钮用 Panel+onClick（Button 单行 auto-fit 会弄乱 children）；
   ②列容器定宽子项必须 `alignItems="center"`；③Label 不自动换行，长文案用 `W.wrapLines` 手动断行。
   Yoga：Label 不写百分比高度；分区容器 `flexShrink=1`；**格子边长按「宽∩高」双约束算**，不能只靠 aspectRatio。
9. 设计裁决：字形图集 `max_distinct_chars_per_level=80` + 进关预热（`system/glyphwarm.lua`，须打 UI 真实上下文）；
   可解性 `core/solver.lua` 双规则；**数值一律读 `data/config.json`，逻辑层禁 require UI，问题留痕 RISK**。
10. **引擎动画三律**：可插值属性只有 opacity/scale/rotate/translateX/translateY/borderRadius/borderWidth/shadow*/颜色
    （**没有 scaleX/scaleY/width/height**）；**禁止 onComplete 链式循环**（`BaseUpdate` 完成分支在回调后
    `self.animation_=nil`，实测只走两拍），无限循环一律 `loop=true` + `direction="alternate"`；
    opacity 动画元素起始 `opacity=0`（禁 `visible=false`）。探针坑：Lua `#` 对非连续整数键关键帧表不可计数。
11. **部件拼装式骨骼动画已彻底否决**（S9–S11 三版：假动效 / AI 分件剪影拟合 / 程序化骨架，用户依次否
    「要骨骼」「不符合常理」「太丑」），**勿重试**。真动画走序列帧 `UI.Sprite` + spritesheet
    （支持 Aseprite/TexturePacker JSON Hash、pivot、无限循环）。抠底必须**从边界漫灌**，
    不能用全局亮度阈值（会抠掉书页白色）；输出必须 **RGBA 真彩，禁 P-mode**（P-mode 卡死加载 51%）。
12. **字体分工（S19 定论，纠正旧认知）**：`main.lua` 传 `theme="default-dark"`，`UI/Theme/DefaultDark.lua`
    把 sans/sans-bold 显式注册到 `Fonts/NotoSansSC-*.ttf` → **这两份才是渲染字体，必须完整打包**。
    MiSans 两份只是引擎二进制硬编码的 fallback 路径（缺文件刷 resource error），历史上是字节级副本 →
    `make_font_stub.py` 生成 14KB 占位即可，字集完全相同 = 零视觉损失省 4.28MB。
    查字体真实来源：先看 `UI.Init` 实参的 theme → 再读主题 `fonts` 表，**不能只看 UI.lua 的 else 默认分支**。
13. 生成器：`util.rng` 有 `mixSeed()`（MINSTD 首输出对相邻 seed 只差 .0008%，「seed+i 重试」会等价失效）；
    **题库变更必须重跑 `verify_levels`**（Solver 规则 B 用全局题库匹配，扩库会提高歧义率）；
    `levelgen` 无值开关 `--dry-run` 已修；试跑前确认 `assets/data/levels/*.json` 数量不变。

## 书童动画（当前线上 = S21）
- `config.json → ui.scholar.mode="sprite"`（回退 `image`）；`ui.scholar.speed=1.6` 是**播放倍率唯一入口**，
  `home.lua` 的 `scholarSpeed()/flipInterval()`：sprite 的 `SetSpeed` **乘**倍率，image 回退的周期/时长**除**倍率。
  改倍率后 `validate_scholar.lua` 自动算期望间隔。实测知识++ 间隔 187 帧（3.125s）。
- 素材：用户给的 96 张 640×640 白底抽帧（`~/Downloads/fa8bbad603aa45a992ac4de43ea32b5b/`），
  已入 git `source_assets/scholar_frames/`。96 帧是完整循环（尾≈首），翻页在源帧 32–72。
  复跑命令：`python3 scripts/tools/scholar_spritesheet.py --frames-dir source_assets/scholar_frames --even-frames 32 --kudos-source-frame 72 --frame-max 224 --colors 96 --flip-interval 5 --out assets/sprites/scholar`
  → 32 帧 / 224px / 582KB / 5000ms 等时长 / `kudos_local_frame=24`（**换图集必须回填 config 再跑 760 帧冒烟**）。
- `--even-frames` 必须独立路径：AI 抽帧相邻差分极小（最大 .00067@128px），普通 `DEDUP_MSE=.0012` 会删光帧；
  tight union bbox 会越界；翻页窗口变速会扭曲匀速动作。`edge_clean` 去白边并省 2% 体积。
  压缩结论：**64 色禁用**（脸颊/书页斑驳）、128色/256px=932KB 超预算，96色/224px 最优。
- 图标接入统一 `W.iconOrDot(key,size,dot)`：PNG 缺失回退色点，替换同名 PNG 即生效。

## 进度与交付
- M1 + S1–S24 已完成：9 个 core 模块、54 单测、300 关 + 20 挑战卷、题库 829 条、
  play/府邸/商店/图鉴/登录 5 页 + 挑战 + 广告弹窗 + 合规闸门；网页试玩可跑（仅 Chrome 无痕，S20 已证是平台
  Web 播放器预检 + 登录态/缓存，非本项目代码）。
- `source_assets/`（46.7MB）已入 git：96 帧源动画、11 张美术母版、骨骼草稿、字体/背景原备份、题库源数据；
  `.workbuddy/memory/` 也已入库。967+ 文件已跟踪。
- 文档：`docs/交付说明-成语小秀才.md`（T1–T24 验收表）、`docs/RISK-成语小秀才.md`（各轮证据）、
  `docs/上架TapTap-操作手册.md`、`docs/上线差距清单-2026-11-15.md`、`docs/美术素材清单.md`、
  `source_assets/README.md`、`scripts/tools/README.md`。

## 上线 / 真机状态（S23–S25，均未解决）
- 官方六步顺序不可调：建游戏→传包体→**先自测**→**再补资料**→开测试→提审上线。
  新硬门槛：关卡/制造游戏提审前须签《创意工坊内容授权协议》（`SCE_AGREEMENT_REQUIRED`），签署是法律行为须用户明确同意。
  资质（小游戏备案/ICP、独立隐私审核、适龄分级）是独立流程，`qualification get-assessment` 为权威入口。
- **真机扫码「滴一下但啥也不弹」= 24.0 已定性**：二维码 `game_url` 指向
  `https://tapcode-sce.spark.xd.com/src/m_x7qf/`，该目录只有 `project.json`(200)，
  `game.json`/`index.html`/`assets`/`scripts` **全 404 NoSuchKey** → 面板「更新测试版/真机自测」上传从未成功，
  容器拿不到包静默退出。`generate_test_qrcode` **只重画二维码、不传包**（重新出码无效）；
  `add_test_whitelist` 需真实 TapTap user_id（project author.id 会报 400「用户 id 异常」）。
  判定修复：浏览器访问 `.../src/m_x7qf/game.json` 变 200。
- **S26（11-16）【重大修正，推翻 24.0/25.0 的「包体从未上传」归因】**：CLI 授权成功后拿到后台权威状态 ——
  `get-available-package-types` = `["spark"]`；`list-spark-versions --page-all` = **16 个版本**，最新
  `version_code=16` / 6.7MB / 00:18:30，`app list-packages` 全部 `ready`。**包体一直上传成功**，
  每次点「更新」都新增版本号（14→15→16）；404 只是 `src/m_x7qf/` 这条 **debug 实时调试目录**为空。
  `version`(1.0.15，Maker 元数据) 与后台 `version_code`(16) 是两套编号。
  **真机根因 = 用错二维码通道**：面板 `generate_test_qrcode` 出的是 `type=debug` + `game_url=src/m_x7qf/`，
  正确码是 `package-management get-test-qr-code --data '{"version_code":"16"}'` → `type=develop` +
  `version_id=490150`（无 game_url），已出 512px PNG `artifacts/test-qr-spark-16.png`。
  **别再点「更新/重新出码」、别去找官方修上传管线**。
- CLI 授权已落地：`~/.taptap-cli/taptap.json`（Bearer 有效，过期 1802536050），后续查询免重登。
  官方口径：「TapTap 制造包体全部由 Maker 传入，CLI 不提供 Spark 包体上传/更新能力」；MCP 19 工具也无上传接口
  （`confirm_remote_build_without_submit` 指 git 提交，不是上传包）。自测码必须先 `list-spark-versions` 取 `version_code`。
- `app analyze-status` 权威阻断项：3 个必填（`promotion_material_type`/`banner_4`/`screenshots`）、
  `MISSING_PACKAGE` 未选主包体（`current_bindings: []`）；warnings 资质事实未确认 + 适龄分级待补齐；
  **本次未返回 `SCE_AGREEMENT_REQUIRED`**。可选 `app +bind-spark-version --data '{"version_code":"16"}'`
  绑主包体走开放试玩（**写操作须用户明确确认**，未执行）。
- 本地提审阻断项（未改，属写操作）：`project.json` 的 icon/screenshots/promotional_image 全空、
  无实机 9:16 截图；`config.json` 的 iap.products(4)/ad.placements(4) 仍开、`privacy_url=""`、实名占位；真机三局自测从未跑通。
- 需用户处理（非代码）：版号与出版审批、后台信息填写与送审、实名/防沉迷资质与 SDK、
  隐私政策 URL 托管、支付签约与内购 SKU、面板上传测试版、GitHub 公开仓库是否改私有（含题库源数据与 App ID）。
