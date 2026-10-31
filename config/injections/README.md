# 注入槽位（默认模板）

一个 `.md` 文件 = 一个注入槽位。开头的 YAML frontmatter 决定插到哪里，正文就是注入内容。

- 默认全部 `enabled: false`，填好内容后改成 `true`。
- 正文为空（或只剩 HTML 注释）会被跳过。
- `<!-- … -->` 不会进入提示词，可以放心写备注。
- 改完后：头部槽位在下次"缓存纪元"（凌晨巩固）或手动应用时生效；尾部槽位下一轮生效。

| 文件 | position | 位置 | 缓存代价 |
|---|---|---|---|
| `00-before-system.md` | `before_system` | 系统消息最前 | 全量 |
| `10-system.md` | `system` | 系统消息内锚点 | 全量 |
| `20-after-system.md` | `after_system` | 系统消息末尾 | 全量 |
| `30-chat-start.md` | `chat_start` | 第一条消息之前 | ≈全量 |
| `40-after-first-message.md` | `after_first_message` | 第一条消息之后 | ≈全量 |
| `50-before-latest.md` | `before_latest` | 最新用户消息内 | ≈0 |
| `60-at-depth.md` | `at_depth` | 倒数第 N 条之前 | 后 N 条 |

完整规则见 [docs/injections.md](../../docs/injections.md)。

运行时以 `[injections].dir` 为准，默认就是本目录；改文件后需重启（热重载待实现）。
