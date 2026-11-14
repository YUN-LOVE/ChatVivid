import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_paths.dart';
import '../../data/app_settings.dart';
import '../../data/chat_backend.dart';
import '../../data/memory_entry.dart';
import '../../theme/app_theme.dart';
import '../../theme/haptics.dart';
import '../chat/chat_models.dart';

/// Developer-mode diagnostics.
///
/// * 运行日志 — native `chatvv.log` tail.
/// * 上下文历史 — persisted conversation messages.
/// * 完整上下文 — everything the model actually received: system prompt,
///   injections, memories, persisted `chatvv.context.built` snapshots (full
///   instructions/tools/input) and tool/provider events.
class SessionLogScreen extends StatefulWidget {
  const SessionLogScreen({
    super.key,
    required this.backend,
    required this.settings,
  });

  final ChatBackend backend;
  final AppSettings settings;

  @override
  State<SessionLogScreen> createState() => _SessionLogScreenState();
}

class _SessionLogScreenState extends State<SessionLogScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxLogBytes = 256 * 1024;

  late final TabController _tabs = TabController(length: 3, vsync: this);

  String _log = '';
  bool _loadingLog = true;
  String? _logPath;

  List<ChatMessage> _history = const [];
  bool _loadingHistory = true;
  String? _historyError;

  Map<String, dynamic>? _contextLog;
  List<MemoryEntry> _memories = const [];
  bool _loadingContext = true;
  String? _contextError;

  @override
  void initState() {
    super.initState();
    _loadLog();
    _loadHistory();
    _loadContext();
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

  Future<void> _loadContext() async {
    setState(() => _loadingContext = true);
    try {
      final log = await widget.backend.contextLog(limit: 800);
      List<MemoryEntry> memories = const [];
      try {
        memories = await widget.backend.memories(limit: 100);
      } catch (_) {
        // Memory list is optional in this view.
      }
      setState(() {
        _contextLog = log;
        _memories = memories;
        _contextError = null;
        _loadingContext = false;
      });
    } catch (error) {
      setState(() {
        _contextError = error.toString();
        _loadingContext = false;
      });
    }
  }

  Future<void> _refresh() async {
    AppHaptics.light();
    await Future.wait([_loadLog(), _loadHistory(), _loadContext()]);
  }

  Future<void> _copyLog() async {
    AppHaptics.medium();
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
        title: const Text('Session log'),
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
          isScrollable: true,
          tabs: const [
            Tab(text: '运行日志'),
            Tab(text: '上下文历史'),
            Tab(text: '完整上下文'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_logTab(), _historyTab(), _contextTab()],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 运行日志
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // 上下文历史（消息）
  // ---------------------------------------------------------------------------
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
                    message.role.toUpperCase(),
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

  // ---------------------------------------------------------------------------
  // 完整上下文：system prompt / 注入 / 记忆 / context.built + tool events
  // ---------------------------------------------------------------------------
  Widget _contextTab() {
    if (_loadingContext) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
    }
    if (_contextError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '读取完整上下文失败：$_contextError',
            style: TextStyle(color: AppColors.coral, fontSize: 12),
          ),
        ),
      );
    }
    final log = _contextLog;
    if (log == null) {
      return const SizedBox.shrink();
    }
    if (log['unsupported'] == true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            (log['reason'] ?? '当前模式不提供完整上下文日志').toString(),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
          ),
        ),
      );
    }
    final settings = widget.settings;
    final events = (log['events'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    // Group the persisted events by response.
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final event in events) {
      final id = (event['response_id'] ?? '').toString();
      grouped.putIfAbsent(id, () => []).add(event);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _sectionTitle('系统提示词（实际发送）'),
        _block(
          settings.systemPrompt.trim().isEmpty
              ? '（App 未设置用户 system prompt；上方“实际发送”的完整 instructions 见最近的 context.built 事件，内部还包含默认人格与安全约束。）'
              : settings.systemPrompt,
        ),
        const SizedBox(height: 14),
        _sectionTitle('上下文注入（${settings.injections.length}）'),
        if (settings.injections.isEmpty)
          _block('（无用户注入）')
        else
          for (final injection in settings.injections)
            _block(
              '${injection.enabled ? '●' : '○'} ${injection.name}\n'
              'position=${injection.position} · mode=${injection.mode} · '
              'trust=${injection.trust} · depth=${injection.depth} · '
              'priority=${injection.priority}\n'
              '${injection.content}',
            ),
        const SizedBox(height: 14),
        _sectionTitle('长期记忆库（${_memories.length}）'),
        if (_memories.isEmpty)
          _block('（记忆库为空）')
        else
          for (final memory in _memories)
            _block(
              '${_formatTime(memory.createdAt)} · 使用 ${memory.useCount} 次\n'
              '${memory.text}',
            ),
        const SizedBox(height: 14),
        _sectionTitle('上下文与工具事件（${events.length}）'),
        if (grouped.isEmpty)
          _block('（暂无事件；发送一条消息后这里会出现 chatvv.context.built 与 tool 调用记录）'),
        for (final entry in grouped.entries) ...[
          const SizedBox(height: 8),
          _responseGroup(entry.key, entry.value),
        ],
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.primary.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _block(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          color: AppColors.text.withValues(alpha: 0.88),
          fontSize: 11,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _responseGroup(String responseId, List<Map<String, dynamic>> events) {
    final shortId =
        responseId.length > 10 ? responseId.substring(0, 10) : responseId;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        title: Text(
          'response $shortId',
          style: TextStyle(color: AppColors.text, fontSize: 11.5),
        ),
        subtitle: Text(
          '${events.length} events',
          style: TextStyle(
            color: AppColors.muted.withValues(alpha: 0.65),
            fontSize: 9.5,
          ),
        ),
        children: [
          for (final event in events) ...[
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '${event['type']}  #${event['seq']}',
                style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.85),
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundTop.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    _pretty(event['data']),
                    style: TextStyle(
                      color: AppColors.text.withValues(alpha: 0.85),
                      fontSize: 9.5,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _pretty(Object? value) {
    if (value is Map || value is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(value);
      } catch (_) {
        return value.toString();
      }
    }
    return value?.toString() ?? '';
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
