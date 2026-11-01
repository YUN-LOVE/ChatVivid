import 'package:flutter/material.dart';

import '../../data/app_settings.dart';
import '../../data/mcp_client.dart';
import '../../data/mcp_server.dart';
import '../../theme/app_theme.dart';
import 'mcp_editor.dart';

class McpPane extends StatefulWidget {
  const McpPane({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  @override
  State<McpPane> createState() => _McpPaneState();
}

class _McpPaneState extends State<McpPane> {
  final Map<String, String> _status = {};
  final Set<String> _testing = {};

  Future<void> _edit([McpServer? initial]) async {
    final result = await Navigator.of(context).push<McpServer>(
      MaterialPageRoute(builder: (_) => McpServerEditorPage(initial: initial)),
    );
    if (!mounted || result == null) return;
    final next = [...widget.settings.mcpServers];
    final index = next.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.add(result);
    }
    widget.onChanged(widget.settings.copyWith(mcpServers: next));
  }

  void _remove(int index) {
    final next = [...widget.settings.mcpServers]..removeAt(index);
    widget.onChanged(widget.settings.copyWith(mcpServers: next));
  }

  Future<void> _test(McpServer server) async {
    setState(() {
      _testing.add(server.id);
      _status[server.id] = '连接中…';
    });
    try {
      final tools = await McpClient(server).listTools();
      if (!mounted) return;
      setState(() {
        _status[server.id] = '连接成功 · ${tools.length} 个工具';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status[server.id] = '失败：$error';
      });
    } finally {
      if (mounted) setState(() => _testing.remove(server.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.settings.mcpServers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'MCP 服务器',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加'),
            ),
          ],
        ),
        if (servers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '暂无 MCP 服务器。Agent 模式下这些工具会注入模型工具列表。',
              style: TextStyle(
                color: AppColors.muted.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
          )
        else
          for (var i = 0; i < servers.length; i++) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              servers[i].name,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              servers[i].url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: servers[i].enabled,
                        onChanged: (enabled) {
                          final next = [...servers];
                          next[i] = next[i].copyWith(enabled: enabled);
                          widget.onChanged(
                            widget.settings.copyWith(mcpServers: next),
                          );
                        },
                      ),
                      IconButton(
                        onPressed: () => _remove(i),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _testing.contains(servers[i].id)
                            ? null
                            : () => _test(servers[i]),
                        child: const Text('测试连接'),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => _edit(servers[i]),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                      ),
                      if (_status[servers[i].id] != null)
                        Expanded(
                          child: Text(
                            _status[servers[i].id]!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _status[servers[i].id]!.startsWith('失败')
                                  ? AppColors.coral
                                  : AppColors.muted,
                              fontSize: 9,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agent 模式',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '启用后系统提示词加入工具策略；MCP 工具循环接入中',
                      style: TextStyle(color: AppColors.muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Switch(
                value: widget.settings.agentEnabled,
                onChanged: (enabled) => widget.onChanged(
                  widget.settings.copyWith(agentEnabled: enabled),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
