import 'package:flutter/material.dart';

import '../../data/chat_backend.dart';
import '../../data/memory_entry.dart';
import '../../theme/app_theme.dart';

class MemoryArchivePane extends StatefulWidget {
  const MemoryArchivePane({super.key, required this.backend});

  final ChatBackend backend;

  @override
  State<MemoryArchivePane> createState() => _MemoryArchivePaneState();
}

class _MemoryArchivePaneState extends State<MemoryArchivePane> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _keepRecent = TextEditingController(text: '20');
  List<MemoryEntry> _memories = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _keepRecent.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final memories = await widget.backend.memories(
        limit: 80,
        query: _query.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _archive() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final keep = int.tryParse(_keepRecent.text) ?? 20;
      final result = await widget.backend.archive(keepRecent: keep);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.archivedMessages > 0
                ? '已归档 ${result.archivedMessages} 条旧消息'
                : '没有可归档的旧消息',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('归档失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveContext() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.backend.saveContext();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.archivedMessages > 0
                ? '上下文已存入记忆库（${result.archivedMessages} 条），并已清空'
                : '上下文已清空',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存上下文失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearContext() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除上下文？'),
        content: const Text('当前对话消息会被删除，已归档的记忆会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.backend.clearContext();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上下文已清除，记忆库保留')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清除失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(MemoryEntry memory) async {
    try {
      await widget.backend.deleteMemory(memory.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  void _show(MemoryEntry memory) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (context, controller) => Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: ListView(
            controller: controller,
            children: [
              Text(
                _date(memory.createdAt),
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
              const SizedBox(height: 10),
              SelectableText(
                memory.text,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          style: const TextStyle(color: AppColors.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: '搜索归档记忆…',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            suffixIcon: IconButton(
              onPressed: _load,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            ),
            filled: true,
            fillColor: AppColors.surfaceHigh.withValues(alpha: 0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 82,
              child: TextField(
                controller: _keepRecent,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.text, fontSize: 12),
                decoration: InputDecoration(
                  labelText: '保留',
                  labelStyle: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceHigh.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_memories.length} 条记忆',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _archive,
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: Text(_busy ? '归档中…' : '归档'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _saveContext,
              icon: const Icon(Icons.move_to_inbox_outlined, size: 17),
              label: const Text('存入记忆并清空'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _clearContext,
              icon: const Icon(Icons.delete_sweep_outlined, size: 17),
              label: const Text('清除上下文'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          )
        else if (_error != null)
          Text(
            _error!,
            style: const TextStyle(color: AppColors.coral, fontSize: 11),
          )
        else if (_memories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '暂无归档。归档后旧消息会压缩成长期记忆，并从后续上下文中移除。',
              style: TextStyle(
                color: AppColors.muted.withValues(alpha: 0.7),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          )
        else
          for (final memory in _memories) ...[
            Material(
              color: AppColors.surfaceHigh.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _show(memory),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.memory_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memory.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${_date(memory.createdAt)} · 使用 ${memory.useCount} 次',
                              style: TextStyle(
                                color: AppColors.muted.withValues(alpha: 0.6),
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _delete(memory),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
