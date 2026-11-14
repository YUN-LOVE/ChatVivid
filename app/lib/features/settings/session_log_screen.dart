import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_paths.dart';
import '../../data/chat_backend.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_models.dart';

/// Developer-mode diagnostics: the native `chatvv.log` tail plus the current
/// persisted conversation/context history.
class SessionLogScreen extends StatefulWidget {
  const SessionLogScreen({super.key, required this.backend});

  final ChatBackend backend;

  @override
  State<SessionLogScreen> createState() => _SessionLogScreenState();
}

class _SessionLogScreenState extends State<SessionLogScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxLogBytes = 256 * 1024;

  late final TabController _tabs = TabController(length: 2, vsync: this);
  String _log = '';
  bool _loadingLog = true;
  String? _logPath;
  List<ChatMessage> _history = const [];
  bool _loadingHistory = true;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadLog();
    _loadHistory();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadLog() async {
    setState(() => _loadingLog = true);
    try {
      final dir = await appSupportDirectory();
      final file = File('${dir.path}/chatvv.log');
      final exists = await file.exists();
      if (!exists) {
        setState(() {
          _log = '日志文件不存在：${file.path}';
          _logPath = file.path;
          _loadingLog = false;
        });
        return;
      }
      final length = await file.length();
      final start = length > _maxLogBytes ? length - _maxLogBytes : 0;
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(length - start);
        final text = utf8.decode(bytes, allowMalformed: true);
        setState(() {
          _log = text;
          _logPath = file.path;
          _loadingLog = false;
        });
      } finally {
        await raf.close();
      }
    } catch (error) {
      setState(() {
        _log = '读取日志失败：$error';
        _loadingLog = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final messages = await widget.backend.history(limit: 200);
      setState(() {
        _history = messages;
        _historyError = null;
        _loadingHistory = false;
      });
    } catch (error) {
      setState(() {
        _historyError = error.toString();
        _loadingHistory = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadLog(), _loadHistory()]);
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('日志已复制（${_log.length} 字符）')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      appBar: AppBar(
        title: Text('Session log'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: _copyLog,
            tooltip: '复制日志',
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '运行日志'),
            Tab(text: '上下文历史'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_logTab(), _historyTab()],
      ),
    );
  }

  Widget _logTab() {
    if (_loadingLog) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_logPath != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              _logPath!,
              style: TextStyle(
                color: AppColors.muted.withValues(alpha: 0.6),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SelectableText(
              _log,
              style: TextStyle(
                color: AppColors.text.withValues(alpha: 0.88),
                fontSize: 10.5,
                height: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _historyTab() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
    }
    if (_historyError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '读取上下文失败：$_historyError',
            style: TextStyle(color: AppColors.coral, fontSize: 12),
          ),
        ),
      );
    }
    if (_history.isEmpty) {
      return Center(
        child: Text(
          '当前会话还没有上下文记录',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final message = _history[index];
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    message.isUser ? 'USER' : 'ASSISTANT',
                    style: TextStyle(
                      color: message.isUser
                          ? AppColors.primary
                          : AppColors.success,
                      fontSize: 9,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      color: AppColors.muted.withValues(alpha: 0.6),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                message.content,
                style: TextStyle(
                  color: AppColors.text.withValues(alpha: 0.9),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
