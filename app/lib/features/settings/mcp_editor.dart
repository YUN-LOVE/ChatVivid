import 'package:flutter/material.dart';

import '../../data/mcp_server.dart';
import '../../theme/app_theme.dart';

class McpServerEditorPage extends StatefulWidget {
  const McpServerEditorPage({super.key, this.initial});

  final McpServer? initial;

  @override
  State<McpServerEditorPage> createState() => _McpServerEditorPageState();
}

class _McpServerEditorPageState extends State<McpServerEditorPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.initial?.url ?? '');
  late final TextEditingController _token =
      TextEditingController(text: widget.initial?.token ?? '');

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    final initial = widget.initial;
    final server = initial == null
        ? McpServer(
            id: 'mcp-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            url: url,
            token: _token.text.trim(),
            enabled: true,
          )
        : initial.copyWith(
            name: name,
            url: url,
            token: _token.text.trim(),
          );
    Navigator.pop(context, server);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.initial == null ? '添加 MCP 服务器' : '编辑 MCP 服务器'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          TextField(
            controller: _name,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如：本地文件系统',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Streamable HTTP URL',
              hintText: 'http://127.0.0.1:3000/mcp',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _token,
            obscureText: true,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Bearer Token（可选）',
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '支持 MCP Streamable HTTP：initialize + tools/list。'
            'SSE 传输和工具调用循环在 Agent 模式中接入。',
            style: TextStyle(
              color: AppColors.muted.withValues(alpha: 0.75),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
