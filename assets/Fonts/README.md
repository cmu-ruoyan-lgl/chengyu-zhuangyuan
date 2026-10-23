# assets/Fonts — 字体目录

## 现状（2026-10-23 更新：授权问题已根治）

| 文件 | 内容 | 许可 | 用途 |
|---|---|---|---|
| `NotoSansSC-Regular.ttf` | Noto Sans SC Regular，3500 汉字子集 | **SIL OFL 1.1** | 项目主字体，可随包分发 |
| `NotoSansSC-Bold.ttf` | Noto Sans SC Bold，3500 汉字子集 | **SIL OFL 1.1** | 真实粗体（可随包分发） |
| `MiSans-Regular.ttf` | **上两个文件的副本** | 同上 | 引擎硬编码的全局兜底路径 |
| `MiSans-Bold.ttf` | **上两个文件的副本** | 同上 | 引擎硬编码的全局兜底粗体路径 |

### 为什么还有 MiSans-* 这两个文件

引擎在启动时**硬编码**去加载 `Fonts/MiSans-Regular.ttf` 与 `Fonts/MiSans-Bold.ttf` 作为
全局兜底字体（见 UrhoXRuntime 二进制中的字符串），且**没有暴露给 Lua 的配置接口**
（只有 `nvgAddFallbackFont` 这种"按字体挂兜底"的 API，没有 `SetGlobalFallbackFonts`）。

缺这两个文件时，`validate` 会报 `Could not find resource Fonts/MiSans-Regular.ttf`，
属于真实的 resource error，会污染验证信号。

**因此**：这两个文件只是为了满足引擎的加载路径，内容仍然是 OFL 的 Noto Sans SC。
如果平台构建（TapTap Maker 远端构建）自带真正的 MiSans，直接删除这两个文件即可，
没有任何代码依赖它们的文件名。

## 授权说明

- Noto Sans SC 使用 **SIL Open Font License 1.1**，允许自由使用、修改、再分发，
  包括在商业产品中嵌入；唯一限制是**不得单独出售字体文件本身**，且衍生字体需改名。
- 许可全文已保存至 `~/.cache/maker-fonts/OFL-NotoSansSC.txt`。
- ⚠️ **不要再使用 macOS 系统字体派生**（PingFang / Arial Unicode / Hiragino / Songti），
  它们受 macOS 软件许可协议约束，**禁止随包分发**。2026-10-23 之前生成的
  `MiSans-Regular.ttf`（由 Arial Unicode 子集化而来）已删除。

## 重建命令

```bash
bash tools/fetch_ofl_font.sh                 # 下载/确认 OFL 字体源（缓存到 ~/.cache/maker-fonts）
python3 tools/build_verification_font.py --chars 3500   # 生成 Regular + Bold 子集
cp assets/Fonts/NotoSansSC-Regular.ttf assets/Fonts/MiSans-Regular.ttf
cp assets/Fonts/NotoSansSC-Bold.ttf    assets/Fonts/MiSans-Bold.ttf
```

出包前应按**题库实际用到的汉字**重新子集化（用 `--chars` 或后续提供的字表参数），
3500 字 / 0.99MB 是本地验证用的宽口径。

## 技术约束（踩过的坑）

1. **必须是 glyf 轮廓的 TTF**。NanoVG 底层是 `stb_truetype`，不认 CFF/OTF
   （思源系列的 `.otf`、Noto Sans CJK 的 `.otf` 都加载不了）。Noto Sans SC 的
   Google Fonts 版本是 glyf TTF，可用。
2. **GitHub raw 在本机不可达**，字体源走 npm registry（`@expo-google-fonts/noto-sans-sc`，
   内含原始 TTF 与 OFL 许可文本）。
3. 字重是**真实存在**的（包内 100–900 共 9 个字重）。但引擎库
   `urhox-libs/UI/Core/UI.lua:475` 曾把 `sans-bold` 写成指向 Regular 的 Placeholder，
   所以**设计上仍不依赖字重区分层级**（用字号/字色/底色块/描边）。
