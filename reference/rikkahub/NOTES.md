# RikkaHub · 交互参考

- 仓库：https://github.com/rikkahub/rikkahub
- 官网：https://rikka-ai.com
- 版本参考：2.1.0（2026-10 查看）
- 许可：**AGPL-3.0**（代码/资源不能直接搬进 chatvv）

## 它是什么

一个 Android 原生 LLM 聊天客户端，功能很全：

- Material 3 Expressive + 深色模式
- 多 provider（OpenAI/Google/Anthropic 兼容）
- 多模态输入、Markdown/代码/LaTeX/Mermaid
- MCP、Skills、Workspace（proot Linux）、媒体生成、搜索
- 助手/Agent 自定义、提示词变量
- Web UI / 多平台

我们只参考它**聊天/助手/设置**的信息架构和视觉节奏，不跟进它的功能广度。

## 截图观察

原图（仅在线参考，不提交）：

- Chat: https://raw.githubusercontent.com/rikkahub/rikkahub/master/docs/img/chat.png
- Assistants: https://raw.githubusercontent.com/rikkahub/rikkahub/master/docs/img/assistants.png
- Models: https://raw.githubusercontent.com/rikkahub/rikkahub/master/docs/img/models.png
- Poster: https://raw.githubusercontent.com/rikkahub/rikkahub/master/docs/img/poster.png

### Chat

- 顶部：左抽屉/筛选图标；中间是对话标题 + 当前模型小字副标题；右侧新对话。
- 助手消息**没有气泡**：头像/来源图标 + 名字 + 正文，下面是低强调动作行（复制/重生成/编辑/选择/分支/导出）。
- 用户消息是右对齐的小圆角胶囊（浅 surface），不抢视觉。
- token 信息用很小的灰字放在消息下方。
- 底部：大胶囊输入框（placeholder 很长）、右侧扫描/相机；下面一排：模型/助手、停止、附件、发送圆钮。
- 整体背景是奶油色/浅 surface，留白很大；没有大阴影/玻璃。

### Assistants

- 大圆角卡片（约 28–32），surfaceContainer 底。
- 标题 + 温度 chip（右上，浅蓝底）。
- Prompt 预览用低对比正文，变量 `{model_name}` 等高亮。
- 底部：删除（低强调）+ 编辑（主色 pill）。
- 顶部仅“助手设置”+ 加号，非常简单。

### Models / Providers

- 列表卡片 + 右侧状态/箭头；模型名、provider、上下文长度。
- 设置页是标准的 Material list + 分组，不花哨。

## 借什么

1. **聊天页的克制**：助手无气泡、用户小胶囊、动作行低强调、token 小字。
2. **顶部模型副标题**：一眼知道当前模型/助手。
3. **输入区结构**：大胶囊 + 工具栏 + 发送圆钮；停止按钮替代发送。
4. **助手卡**：温度 chip、prompt 预览、编辑 pill。
5. **大留白 + 大圆角**，而不是满屏卡片。

## 不借什么

- 多会话列表、Workspace、媒体生成、MCP 市场、Web UI 等广度。
- 具体代码、图标、截图、字体资源（AGPL/版权）。
- 它的浅色平铺风格不是我们的全部；我们额外加 Apple 玻璃和深海蓝。

## 对我们的 IA 的影响

- 主界面仍是**唯一对话**，不做会话列表；RikkaHub 的多会话只是交互参考。
- 助手是“预设/人格”，切换不新开会话。
- 抽屉放：记忆库、助手、设置、关于；不放开源项目里的所有工具入口。
