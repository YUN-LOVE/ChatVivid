import 'package:flutter/material.dart';

import '../../data/prompt_injection.dart';
import '../../theme/app_theme.dart';

class InjectionEditorPage extends StatefulWidget {
  const InjectionEditorPage({super.key, this.initial});

  final PromptInjection? initial;

  @override
  State<InjectionEditorPage> createState() => _InjectionEditorPageState();
}

class _InjectionEditorPageState extends State<InjectionEditorPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.initial?.content ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.initial?.description ?? '');
  late final TextEditingController _depth = TextEditingController(
    text: '${widget.initial?.depth ?? 1}',
  );
  late final TextEditingController _priority = TextEditingController(
    text: '${widget.initial?.priority ?? 100}',
  );
  late String _position = widget.initial?.position ?? 'before_latest';
  late String _mode = widget.initial?.mode ?? 'append';
  late String _trust = widget.initial?.trust ?? 'data';

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    _description.dispose();
    _depth.dispose();
    _priority.dispose();
    super.dispose();
  }

  void _save() {
    final content = _content.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('注入内容不能为空')),
      );
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      PromptInjection(
        id: initial?.id ??
            'injection-${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim().isEmpty ? '未命名注入' : _name.text.trim(),
        position: _position,
        content: content,
        mode: _position == 'system' ? _mode : 'append',
        trust: _trust,
        description: _description.text.trim(),
        depth: _position == 'at_depth'
            ? (int.tryParse(_depth.text) ?? 1).clamp(1, 64)
            : 0,
        priority: int.tryParse(_priority.text) ?? 100,
        enabled: initial?.enabled ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      appBar: AppBar(
        title: Text(widget.initial == null ? '新建注入' : '编辑注入'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _Field(controller: _name, label: '名称', hint: '例如：回答风格'),
          const SizedBox(height: 12),
          _Field(
            controller: _description,
            label: '描述（可选）',
            hint: '给未来的自己看',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _position,
            decoration: _decoration('插入位置'),
            items: [
              for (final value in PromptInjection.positions)
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _position = value);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _trust,
                  decoration: _decoration('信任级别'),
                  items: const [
                    DropdownMenuItem(value: 'data', child: Text('资料')),
                    DropdownMenuItem(
                      value: 'instruction',
                      child: Text('指令'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _trust = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _mode,
                  decoration: _decoration('mode'),
                  items: const [
                    DropdownMenuItem(value: 'append', child: Text('append')),
                    DropdownMenuItem(value: 'replace', child: Text('replace')),
                  ],
                  onChanged: _position == 'system'
                      ? (value) {
                          if (value != null) setState(() => _mode = value);
                        }
                      : null,
                ),
              ),
            ],
          ),
          if (_position == 'at_depth') ...[
            const SizedBox(height: 12),
            _Field(
              controller: _depth,
              label: 'depth',
              hint: '1–64',
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 12),
          _Field(
            controller: _priority,
            label: '优先级',
            hint: '100',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            minLines: 6,
            maxLines: 14,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: _decoration('注入内容').copyWith(
              alignLabelWithHint: true,
              hintText: '会被插入到上下文的内容',
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 11),
      filled: true,
      fillColor: AppColors.surfaceHigh.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.text, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.muted, fontSize: 11),
        hintStyle: TextStyle(
          color: AppColors.muted.withValues(alpha: 0.45),
          fontSize: 12,
        ),
        filled: true,
        fillColor: AppColors.surfaceHigh.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      ),
    );
  }
}
