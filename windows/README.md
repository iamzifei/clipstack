# ClipStack for Windows

C# / .NET 8 (WinForms) port of the macOS menu bar app — a system-tray clipboard
history manager.

> ⚠️ **Built cross-platform on macOS and NOT yet tested on a real Windows
> machine.** The code compiles and mirrors the macOS logic 1:1, but treat the
> first run as a smoke test. Please report issues.

## Features (parity with macOS v1.1.x)

| Feature | macOS | Windows |
|---|---|---|
| History: text / image / files | ✅ | ✅ (event-driven, no polling) |
| Dedupe + promote on re-copy | ✅ | ✅ |
| Pin, delete, clear (keep pinned), 300-item cap | ✅ | ✅ |
| Switcher panel: search, ↑/↓, Enter, quick-copy, pin, delete | ⇧⌘V | Ctrl+Shift+V (Ctrl+1–9 / Ctrl+P / Ctrl+Del) |
| Settings (launch at startup, GitHub link) | ⌘. | Ctrl+. (startup via HKCU Run key) |
| Copied toast | ✅ | ✅ |
| 7 languages (en/zh-Hans/zh-Hant/ja/ko/es/fr) | ✅ | ✅ (follows Windows display language) |
| Hotkey rebinding UI | ✅ | ❌ fixed hotkeys in this version |
| Rich text (RTF/HTML) flavors | ✅ | ❌ plain text only in this version |

Data lives in `%APPDATA%\ClipStack\` (`history.json` + `images\*.png`).

## Build

Requires the .NET 8 SDK (any OS — `EnableWindowsTargeting` lets it build on
macOS/Linux too):

```bash
cd windows/ClipStack.Win
dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
# → bin/Release/net8.0-windows/win-x64/publish/ClipStack.exe
```

Copy `ClipStack.exe` (plus `app.ico` in the same folder) to the Windows
machine and run it. Enable "Launch at startup" from Settings (Ctrl+.).
