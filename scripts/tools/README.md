# scripts/tools — 开发与素材流水线

> 关卡/校验/单测入口是 Lua；素材处理是 Python（依赖 Pillow + numpy；ffmpeg 在 /opt/homebrew/bin）。
> 注意：`tools/`（项目根）是平台保留目录**不入 git**，自建脚本一律放本目录。

## 1. 书童序列帧图集（scholar_spritesheet.py）

三种输入模式，产出 `assets/sprites/scholar/{spritesheet.png, sprite.json}` 并打印
SUMMARY JSON（`kudos_local_frame` 需回填 `config.json` 的 `ui.scholar.sprite.kudos_local_frame`）：

```bash
# A. 零积分烘焙（当前线上版本的来源）：scholar.png + 翻页/呼吸/轻摇编排直接渲染帧
python3 scripts/tools/scholar_spritesheet.py --from-base --frames 24 --frame-max 320 --flip-interval 5

# B. AI 胶片图切分（充值后推荐）：ImageGen 出 4×3 网格连续动作图 → 逐格中心对齐
#    胶片图提示词要点：角色与 scholar.png 完全一致；从左到右从上到下为时间顺序；
#    每格构图一致镜头固定；纯色浅薄荷绿背景；无文字无水印。
python3 scripts/tools/scholar_spritesheet.py --strip <胶片图.png> --grid 4x3 --frame-max 320 --flip-interval 5

# C. 视频抽帧（若视频生成恢复可用）：固定机位 → union bbox 共享裁窗对齐
python3 scripts/tools/scholar_spritesheet.py --video <anim.mp4> --fps 12 --frame-max 320 --flip-interval 5
```

通用步骤：边界漫灌抠底（**禁止全局亮度阈值**，会抠掉书页白色，见 RISK S10-6）→
只留最大连通分量（顺带清水印碎片）→ 对齐 → 循环缝修剪 → 去重 → 翻页检测 →
时长编排（总时长 = flip_interval）→ POT 装箱（>600KB 自动量化）。

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
cp assets/Fonts/NotoSansSC-Regular.ttf assets/Fonts/MiSans-Regular.ttf
cp assets/Fonts/NotoSansSC-Bold.ttf    assets/Fonts/MiSans-Bold.ttf
```

字集 = GB2312 全 6763 ∪ 题库全字段 ∪ **Lua/config 全部非 ASCII**（只扫 CJK 会把
‹ 　「」￥– 漏成豆腐块）。MiSans 两份是引擎硬编码兜底路径的副本，不可省。
门禁：源字体有却没收 = 硬失败；✅❌ 等 emoji 源字体没有 = 仅告警（引擎有 Emoji fallback）。

## 4. 其他常用

```bash
lua54 scripts/tools/run_tests.lua          # 54 项离线单测
lua54 scripts/tools/verify_levels.lua --all # 300 关 + 20 卷校验 + 平衡对账
lua54 scripts/tools/levelgen.lua --seg 3 --from 301 --to 320 --seed X  # 扩关（先读 DEV §5）
python3 scripts/tools/ascii_peek.py <图片>  # 无 GUI 环境把图片转 ASCII 剪影核对
```
