# assets/Fonts — 字体目录

## 现状（2026-11-14 更新：加载体积优化，见 RISK 19.0）

| 文件 | 体积 | 用途 |
|---|---|---|
| `NotoSansSC-Regular.ttf` | 2.14 MB | **UI 实际渲染字体**（`theme="default-dark"` 把 `sans` 注册到此路径），7025 字形子集（GB2312 全 6763 字 ∪ 题库 ∪ UI 文案），SIL OFL 1.1 可随包分发 |
| `NotoSansSC-Bold.ttf` | 2.14 MB | 同上字集的真实粗体（`sans-bold`） |
| `MiSans-Regular.ttf` | **14 KB** | 引擎二进制硬编码加载路径的**极小占位**（ASCII + 常用标点 122 字形） |
| `MiSans-Bold.ttf` | **14 KB** | 同上 |

### 为什么 MiSans-* 可以只留 12KB

引擎启动时会硬编码加载 `Fonts/MiSans-Regular.ttf` / `MiSans-Bold.ttf` 作为全局
fallback（UrhoXRuntime 二进制中的字符串），缺文件会刷 `Could not find resource`。
但这两份历史上是 NotoSansSC 的**字节级副本**：字集与主字体完全一致，fallback
永远不可能补出主字体没有的字。因此缩小它们是**零视觉损失**，却能省 4.28 MB 包体。

⚠️ 重跑 `tools/build_verification_font.py` 会把 NotoSansSC 复制回 MiSans（恢复成
2 MB 副本），**必须紧接着执行**：

```bash
python3 scripts/tools/make_font_stub.py           # 重新生成占位
python3 scripts/tools/make_font_stub.py --check   # 校验 ≤64KB
```

`scripts/system/glyphwarm.lua` 的 headless 兜底字体路径也已改指向
`Fonts/NotoSansSC-Regular.ttf`（占位字体没有中文字形，不能用来预热）。

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

### ⚠️ 子集字集教训（2026-10-23，RISK S1-12）

初版按**码点序**截断前 3500 字，把「第/金/马/心」等超高频字切掉（常用字码点分散），
远端满屏豆腐块。现改为 `GB2312 全 6763 字 ∪ assets/data/idioms.json(word 字段) ∪ scripts/**/*.lua 中文字`，
由 `tools/build_verification_font.py` 生成。**新增 UI 文案/题库生僻字后必须重跑该脚本**。
