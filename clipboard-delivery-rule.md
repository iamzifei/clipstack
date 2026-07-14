# Clipboard Delivery — Claude Code 配套规则

> 把这段规则加进你的 `~/.claude/CLAUDE.md`，Claude Code 会把「你下一步要粘贴到别处」的输出自动放进系统剪贴板，原始换行/缩进/排版不受终端渲染影响。配合 ClipStack 的历史面板（⇧⌘V），多段内容可随时切换。

## Clipboard Delivery（复制粘贴型交付物 → 自动进剪贴板）
以下输出是「用户下一步要粘贴到别处」的交付物，**不需要用户说"复制"就默认执行**：
1. 客户/工单回复（Telegram、Discord、WeChat、邮件），含 dunning/退款/询价回复
2. 邮件（主题 + 正文）
3. 环境变量、API key、token、连接串
4. 配置片段（.env / JSON / YAML / TOML / nginx / wrangler / vercel 等）
5. 要在别处执行的命令、脚本、SQL
6. 交接/任务清单（发同事、合伙人、供应商的内容，如 HUMAN QUEUE 列表、即时聊天消息）
7. 社交/营销文案（小红书、公众号、X、LinkedIn 的标题与正文）、提示词、书单等清单类
8. 用户说「给我 / 发我 / 我要贴到… / 我用 telegram(discord) 回复」的任何文本

执行方式（macOS）：
- MUST 三步：① 原始内容**原样**写入文件（真实换行/缩进/Tab，不加代码围栏、不加行号）；② `pbcopy < 文件` 放入剪贴板；③ 汇报「✂ 已复制到剪贴板」+ 文件路径。聊天里可另行渲染预览，但以剪贴板/文件内容为准。
- 一律 `pbcopy < file`，禁止 echo/printf/heredoc 内联管道（转义和末尾换行会污染内容）。
- **聊天软件回复（Telegram/Discord/WeChat）：纯文本，不带 markdown 符号**（无 `*`、`#`、围栏），语气 casual/simple 按用户既有偏好。
- 多段内容（如两份回复）：每段各存一个文件，按「次要 → 主要」顺序依次 `pbcopy < f && sleep 1`（间隔 ≥1s，确保每段都被 ClipStack 抓入历史；最后复制的一段留在当前剪贴板并说明顺序）。
- 需要富文本粘贴（邮件正文带加粗/链接，贴 Gmail/Mail）时：写 HTML 文件后 `textutil -stdin -stdout -format html -convert rtf < f.html | pbcopy -Prefer rtf`。
- 图片交付物：默认给路径；用户要直接粘贴时用 `osascript -e 'set the clipboard to (read (POSIX file "/abs/path.png") as «class PNGf»)'`。
- 密钥类内容照常入剪贴板与文件，但不要在聊天里回显明文。
- 客户邮件仍走既有流程；本规则只负责把最终文本同步进剪贴板，不改变「先审后发」。
- 配套工具：菜单栏 App **ClipStack**（全局 ⇧⌘V 呼出历史面板），连续复制的多段内容都留在其历史里可随时切换。
