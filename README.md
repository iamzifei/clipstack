# ClipStack

macOS 菜单栏剪贴板历史管理器。为配合 Claude Code 的 Clipboard Delivery 规则而写（多段 `pbcopy` 输出全部留在历史里，随时切换），也是一个通用的轻量剪贴板管理器。

> 成熟替代品：开源的 [Maccy](https://maccy.app)。ClipStack 是按本机工作流定制的极简版（无沙盒、无偏好界面、零依赖、约 1000 行 Swift）。

## 功能

- 菜单栏常驻（无 Dock 图标），每 0.25s 监控系统剪贴板；菜单栏为自定义 template 黑白图标，随系统浅色/深色主题自动反色
- 历史支持：纯文本（保留 RTF/HTML 富文本 flavor）、图片（PNG/TIFF）、文件（Finder 复制的文件 URL）
- 全局快捷键 **⇧⌘V** 呼出切换面板：搜索（支持中文输入法）、↑/↓ 选择、**回车 = 复制并关闭**、⌘1–9 快速复制、⌘P 置顶、⌘⌫ 删除、esc 关闭；右侧完整预览（文本等宽显示 / 图片缩放 / 文件路径列表）
- 复制成功后屏幕顶部弹出「已复制」Toast 反馈（含内容摘要，1.3s 自动消失，不抢焦点）
- 全局快捷键 **⌘.** 打开设置面板：开机自启动开关、两个全局快捷键点击录制改键（冲突检测、Esc 取消），存储于 UserDefaults
- 菜单栏下拉：最近 10 条一键复制、设置、暂停监控、清空历史（保留置顶）
- 复制回剪贴板时恢复原始 flavor（富文本贴回仍是富文本，图片贴回仍是图片）
- 多语言：简体中文、繁體中文、English、日本語、한국어、Español、Français（跟随系统语言）
- 隐私：遵循 [nspasteboard.org](http://nspasteboard.org) 约定，密码管理器标记的 Concealed/Transient 内容不入库
- 历史持久化：`~/Library/Application Support/ClipStack/`（history.json + images/*.png），默认上限 300 条（置顶不占淘汰位）

## 构建 & 安装

```bash
./build.sh              # 产出 build/ClipStack.app（默认 ad-hoc 签名，含图标）
./build.sh --install    # 安装到 /Applications 并启动
./make-dmg.sh           # 打包 dist/ClipStack-<版本>.dmg（拖拽安装盘）
swift test              # 运行单元测试

# 正式分发（Developer ID 签名 + 可选公证）：
CODESIGN_IDENTITY="Developer ID Application: <Your Team>" ./build.sh
CODESIGN_IDENTITY="Developer ID Application: <Your Team>" NOTARY_PROFILE=<profile> ./make-dmg.sh
```

无需任何权限（辅助功能/录屏都不需要）——只写剪贴板，不模拟粘贴。

分发提示：已签名但未公证的 DMG，下载后首次打开需右键 → 打开；配置 `notarytool store-credentials` 后传 `NOTARY_PROFILE` 即可自动公证 + staple。

## 图标

macOS Big Sur 规范：1024 网格、824×824 squircle（r≈185）、系统蓝渐变、烘焙软阴影。图形语义：夹着纸的剪贴板 = 当前剪贴板，底部两层阶梯卡片 = 历史堆叠（Clip + Stack）。

- `assets/clipstack-icon.svg` — 彩色主图标（矢量源文件）
- `assets/clipstack-icon-1024.png` — 1024 母版
- `assets/clipstack-icon-mono.svg` — 黑白变体（透明底，可用于文档/水印）
- `Resources/AppIcon.icns` — 全尺寸（16→1024 @1x/@2x）App 图标，由 build.sh 打进 bundle

## 自定义

快捷键与开机自启动在设置面板（⌘. 或菜单栏 → 设置…）里改。其余用 `defaults` 配置（重启 App 生效）：

```bash
# 历史上限
defaults write com.james.ClipStack MaxItems -int 500

# 快捷键也可以直接写 defaults（Carbon keycode + modifier；⌘=256 ⇧=512 ⌥=2048 ⌃=4096）
defaults write com.james.ClipStack HotKeyKeyCode -int 9            # 面板，默认 ⇧⌘V
defaults write com.james.ClipStack HotKeyModifiers -int 768
defaults write com.james.ClipStack SettingsHotKeyKeyCode -int 47   # 设置，默认 ⌘.
defaults write com.james.ClipStack SettingsHotKeyModifiers -int 256
```

## 与 Claude Code 的配合

全局 `~/.claude/CLAUDE.md` 的 **Clipboard Delivery** 规则会让 Claude 在产出「复制粘贴型交付物」（客户回复、邮件、env、配置、命令、文案等）时自动 `pbcopy < file`。多段内容会以 ≥1s 间隔依次复制——每段都被 ClipStack 抓进历史，⇧⌘V 即可在几段之间切换粘贴。

规则全文见 [clipboard-delivery-rule.md](./clipboard-delivery-rule.md)，复制进你自己的 `~/.claude/CLAUDE.md` 即可使用。

## 项目结构

```
Sources/ClipStackCore/   # 纯 Foundation：模型 + 持久化存储（可单测）
Sources/ClipStack/       # AppKit/SwiftUI：监控、热键、面板、菜单
Tests/ClipStackTests/    # 全部单元测试
```
