# MCP / Agent / Skills

## Skills

设置 → 技能。

技能是带名称、简介和指令的提示词工作流；启用后会被拼进系统提示词，Full 和 Only client 都生效。
当前技能只影响提示词，不执行本地代码。

## MCP

设置 → MCP 与 Agent → 添加服务器。

支持 MCP Streamable HTTP：
- `initialize`
- `notifications/initialized`
- `tools/list`

“测试连接”会显示工具数量。工具列表使用 `Mcp-Session-Id` 维持会话。
当前 MCP 客户端用于发现/诊断工具；把工具接入模型工具循环的 Agent 执行器是下一步。

## Agent

`agent_enabled` 打开后，系统提示词会附加 Agent 工具策略。
真正的 MCP 工具调用循环（model → tool_call → MCP → tool result → model）尚未接入聊天主链路；
当前先保留开关、MCP 配置、工具发现和 Skills 注入，避免在 Full 模式里悄悄绕过 native core。

## 配置存储

MCP URL/token 和技能均写入 `settings.json`，与现有配置一起保存。
Token 目前与 API key 一样是本地明文存储，后续应迁移到安全存储。
