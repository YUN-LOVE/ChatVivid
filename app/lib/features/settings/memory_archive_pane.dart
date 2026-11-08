// ignore_for_file: prefer_const_constructors_in_immutables
import 'package:flutter/material.dart';

import '../../data/chat_backend.dart';
import '../../data/memory_entry.dart';
import '../../theme/app_theme.dart';

class MemoryArchivePane extends StatefulWidget {
  MemoryArchivePane({super.key, required this.backend});

  final ChatBackend backend;

  @override
  State<MemoryArchivePane> createState() => _MemoryArchivePaneState();
}

class _MemoryArchivePaneState extends State<MemoryArchivePane> {
  final TextEditingController _query = TextEditingController();
  List<MemoryEntry> _memories = [];
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

  Future<void> _clearContext() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清除上下文？'),
        content: Text('当前对话消息会被删除，已归档的记忆会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('清除'),
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
        SnackBar(content: Text('上下文已清除，记忆库保留')),
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
          margin: EdgeInsets.all(12),
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: ListView(
            controller: controller,
            children: [
              Text(
                _date(memory.createdAt),
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
              SizedBox(height: 10),
              SelectableText(
                memory.text,
                style: TextStyle(
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
          style: TextStyle(color: AppColors.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: '搜索归档记忆…',
            prefixIcon: Icon(Icons.search_rounded, size: 19),
            suffixIcon: IconButton(
              onPressed: _load,
              icon: Icon(Icons.arrow_forward_rounded, size: 18),
            ),
            filled: true,
            fillColor: AppColors.surfaceHigh.withValues(alpha: 0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Text(
              '${_memories.length} 条记忆',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            Spacer(),
            Text(
              '每轮自动保存 · 只读',
              style: TextStyle(
                color: AppColors.primary.withValues(alpha: 0.75),
                fontSize: 10,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _clearContext,
          icon: Icon(Icons.delete_sweep_outlined, size: 17),
          label: Text('清除上下文'),
        ),
        SizedBox(height: 12),
        if (_loading)
          Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          )
        else if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: AppColors.coral, fontSize: 11),
          )
        else if (_memories.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
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
                  padding: EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.memory_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memory.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            SizedBox(height: 5),
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
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 8),
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
