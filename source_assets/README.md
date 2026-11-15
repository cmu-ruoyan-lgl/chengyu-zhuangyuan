# source_assets — 项目源素材（纳入 git，但不进游戏包）

> 建立于 2026-11-15（S22 仓库版本管理整理）。此前这些文件散落在 `.tmp/`（被
> `.gitignore` 忽略），随时可能被清理且无法从仓库恢复，故迁入本目录归档。

## 为什么单独放这里

`.project/settings.json` 的 `build.asset_dirs` 明确只有 `../assets` 与 `../scripts`，
**平台只打包这两个目录**。本目录位于项目根，因此：

- ✅ 纳入 git，可跨机器/跨会话恢复、可 review、可回滚；
- ✅ **不会进入游戏包**，也就不受 `resources.json` 的 `preload_groups: ["default"]`
  + `default: ["**"]` 全量预载影响，S19 优化后的加载速度不受影响；
- ✅ 不需要配对的 `.meta`（那是打包资源才需要的）。

⚠️ 不要把这些文件移动/复制到 `assets/` 或 `scripts/`，否则会直接把几十 MB 塞进首屏包。

## 目录内容

| 目录 | 内容 | 用途 |
|---|---|---|
| `scholar_frames/` | 96 张 `video_000..095.png`（640×640 白底，25.7 MB） | 主页书童**真翻页动画**的完整循环源帧；S21 起线上图集由它生成 |
| `art_masters/` | 11 张母版/关键帧 | 最早的书童 ImageGen 原图、S10 纸娃娃分件图、S11 三态关键帧、背景原图与中间稿、图标预览 |
| `rig_drafts/` | `scholar_rig.lua` / `scholar_rig2.lua` | S9/S11 两版被否决的骨骼动画草稿（留作历史，不参与构建） |
| `fonts/` | `MiSans-*.ttf` ×2 + `bg_main.png` | S19 包体瘦身前的原始备份，用于回滚对比 |
| `data/` | `xinhua_idiom.json`（9.8 MB） | 成语题库整理的原始词典数据（当前 `assets/data/` 是其加工产物） |

## 复跑书童图集

在项目根执行（依赖 Pillow + numpy）：

```bash
python3 scripts/tools/scholar_spritesheet.py \
  --frames-dir source_assets/scholar_frames \
  --even-frames 32 --kudos-source-frame 72 \
  --frame-max 224 --colors 96 --flip-interval 5 \
  --out assets/sprites/scholar
```

产出 `assets/sprites/scholar/{spritesheet.png, sprite.json}`，并把 SUMMARY 里的
`kudos_local_frame` 回填 `assets/data/config.json` 的 `ui.scholar.sprite.kudos_local_frame`。
当前线上参数：32 帧 / 224px / 96 色 / 582KB / 5000ms / `kudos_local_frame=24`。
参数与取舍依据见 `docs/RISK-成语小秀才.md` 21.0、`scripts/tools/README.md`。

## 仍然不入库的文件（有意为之）

| 类别 | 原因 |
|---|---|
| `tools/`（项目根） | 平台资源入口，**远端 pre-receive 钩子禁止跟踪**，强推会被拒 |
| `.cli/` `.installer/` `urhox-libs/` `examples/` `engine-docs/` `schemas/` `templates/` | ai-dev-kit / 引擎提供，本地环境自带，非项目源码 |
| `.tmp/` 其余内容 | 压缩试验图、验证日志、临时脚本、二维码等一次性产物 |
| `.maker/` `.maker-mcp/` `.agents/` 各类 IDE 配置 | 会话/运行时状态与本地配置 |
| `save.json*` | 引擎 tool_mode 写在项目根的本地存档（真机沙箱不受影响） |
| `*.log` `.DS_Store` `__pycache__/` `*.pyc` | 日志、系统垃圾、Python 缓存 |

`.workbuddy/memory/` 是例外：它是项目知识资产（决策/踩坑留痕），已通过
`.gitignore` 的 `!/.workbuddy/memory/` 例外规则纳入版本管理；其余 `.workbuddy/*`
仍不入库。
