# scripts/tools — 开发与素材流水线

> 关卡/校验/单测入口是 Lua；素材处理是 Python（依赖 Pillow + numpy；ffmpeg 在 /opt/homebrew/bin）。
> 注意：`tools/`（项目根）是平台保留目录**不入 git**，自建脚本一律放本目录。

## 1. 书童序列帧图集（scholar_spritesheet.py）

输入模式产出 `assets/sprites/scholar/{spritesheet.png, sprite.json}` 并打印
SUMMARY JSON（`kudos_local_frame` 需回填 `config.json` 的 `ui.scholar.sprite.kudos_local_frame`）：

```bash
# D. 完整循环帧目录（★ S21 起为线上版本来源）：96 帧白底抽帧 → 32 帧真翻页动画
#    源帧副本 .tmp/scholar_video_frames/（不入 git），尾帧≈首帧，固定机位
python3 scripts/tools/scholar_spritesheet.py --frames-dir .tmp/scholar_video_frames \
    --even-frames 32 --kudos-source-frame 72 --frame-max 224 --colors 96 --flip-interval 5

# A. 零积分烘焙（S13–S20 的旧来源，现仅作回退）：scholar.png + 翻页/呼吸/轻摇编排直接渲染帧
python3 scripts/tools/scholar_spritesheet.py --from-base --frames 24 --frame-max 320 --flip-interval 5

# B. AI 胶片图切分（充值后推荐）：ImageGen 出 4×3 网格连续动作图 → 逐格中心对齐
#    胶片图提示词要点：角色与 scholar.png 完全一致；从左到右从上到下为时间顺序；
#    每格构图一致镜头固定；纯色浅薄荷绿背景；无文字无水印。
python3 scripts/tools/scholar_spritesheet.py --strip <胶片图.png> --grid 4x3 --frame-max 320 --flip-interval 5

# C. 视频抽帧 / 普通帧目录（若视频生成恢复可用）：固定机位 → union bbox 共享裁窗对齐
python3 scripts/tools/scholar_spritesheet.py --video <anim.mp4> --fps 12 --frame-max 320 --flip-interval 5
```

通用步骤：边界漫灌抠底（**禁止全局亮度阈值**，会抠掉书页白色，见 RISK S10-6）→
只留最大连通分量（顺带清水印碎片）→ 对齐 → 循环缝修剪 → 去重 → 翻页检测 →
时长编排（总时长 = flip_interval）→ POT 装箱（>600KB 自动量化）。

**D 模式的差异**（`--even-frames`）：AI 抽帧相邻帧差异极小，普通路径的
`DEDUP_MSE` 会把帧几乎删光、翻页窗口变速还会扭曲匀速动作，因此 D 模式改为
等步长抽稀 + 等时长 + 保留原正方形画布，并额外做 `edge_clean` 去白边。
`--kudos-source-frame` 填源序列里「翻页完成」的帧号，脚本自动换算成本地帧号。
产物必须是 **RGBA 真彩**（P-mode PNG 会卡死资源加载，见 RISK S17-1）。

产出后：
```bash
node tools/maker_call.mjs call generate_resource_meta '{"target_dir":"<项目绝对路径>","paths":["assets/sprites/scholar/spritesheet.png","assets/sprites/scholar/sprite.json"]}'
```

## 2. 图标生成（make_icons.py）

```bash
python3 scripts/tools/make_icons.py                  # 全部 14 枚 → assets/sprites/icons/
python3 scripts/tools/make_icons.py --only gold,home # 只重生成指定键
```

配色读 config `ui.color`（浅圆角底 = 主色向白混合 0.8，图形 = deep/dark 色）。
**AI 精修时同名替换 PNG 即可**（尺寸不变 128×128），UI 代码经 `W.iconOrDot` 自动生效。

## 3. 字体子集重建（tools/build_verification_font.py，改中文文案后必跑）

```bash
python3 tools/build_verification_font.py --chars 12000
python3 scripts/tools/make_font_stub.py           # 重建占位（否则 MiSans 又变回 2MB 副本）
python3 scripts/tools/make_font_stub.py --check
```

字集 = GB2312 全 6763 ∪ 题库全字段 ∪ **Lua/config 全部非 ASCII**（只扫 CJK 会把
‹ 　「」￥– 漏成豆腐块）。
门禁：源字体有却没收 = 硬失败；✅❌ 等 emoji 源字体没有 = 仅告警（引擎有 Emoji fallback）。

**字体分工（S19 后）**：`theme="default-dark"` 把 `sans` / `sans-bold` 注册到
`Fonts/NotoSansSC-*.ttf` —— 这两份是**必须完整打包的渲染字体**；
`MiSans-*.ttf` 只是引擎二进制硬编码 fallback 的加载路径，用
`make_font_stub.py` 生成 14KB 占位即可（省 4.28MB）。理由与回滚方法见
`assets/Fonts/README.md`。

## 4. 其他常用

```bash
lua54 scripts/tools/run_tests.lua          # 54 项离线单测
lua54 scripts/tools/verify_levels.lua --all # 300 关 + 20 卷校验 + 平衡对账
lua54 scripts/tools/levelgen.lua --seg 3 --from 301 --to 320 --seed X  # 扩关（先读 DEV §5）
python3 scripts/tools/ascii_peek.py <图片>  # 无 GUI 环境把图片转 ASCII 剪影核对
```
