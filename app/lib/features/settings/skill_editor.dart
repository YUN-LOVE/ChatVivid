import 'package:flutter/material.dart';

import '../../data/skill.dart';
import '../../theme/app_theme.dart';

class SkillEditorPage extends StatefulWidget {
  const SkillEditorPage({super.key, this.initial});

  final Skill? initial;

  @override
  State<SkillEditorPage> createState() => _SkillEditorPageState();
}

class _SkillEditorPageState extends State<SkillEditorPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.initial?.description ?? '');
  late final TextEditingController _instructions =
      TextEditingController(text: widget.initial?.instructions ?? '');

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _instructions.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final initial = widget.initial;
    final skill = initial == null
        ? Skill(
            id: 'skill-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            description: _description.text.trim(),
            instructions: _instructions.text.trim(),
            enabled: true,
          )
        : initial.copyWith(
            name: name,
            description: _description.text.trim(),
            instructions: _instructions.text.trim(),
          );
    Navigator.pop(context, skill);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.initial == null ? '新建技能' : '编辑技能'),
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
              hintText: '例如：代码审查',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _description,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: '简介',
              hintText: '这个技能做什么',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _instructions,
            maxLines: 12,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              height: 1.55,
            ),
            decoration: const InputDecoration(
              labelText: '指令 / 工作流',
              hintText: '启用后会被加入系统提示词…',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}
