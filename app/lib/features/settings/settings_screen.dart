// ignore_for_file: prefer_const_constructors_in_immutables
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../../app/build_info.dart';
import '../../data/app_paths.dart';
import 'dart:io';

import '../../data/app_settings.dart';
import '../../data/chat_backend.dart';
import '../../data/skill.dart';
import '../../data/prompt_injection.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../chat/file_upload_service.dart';
import 'injection_editor.dart';
import 'memory_archive_pane.dart';
import 'mcp_pane.dart';
import 'skill_editor.dart';

class SettingsScreen extends StatefulWidget {
  SettingsScreen({
    super.key,
    required this.settings,
    required this.backend,
  });

  final AppSettings settings;
  final ChatBackend backend;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class SettingsCategory {
  SettingsCategory({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}

final _categories = [
  SettingsCategory(
    title: '连接与后端',
    description: 'Full / Only client、模型与 API Key',
    icon: Icons.hub_rounded,
  ),
  SettingsCategory(
    title: '提示词与注入',
    description: '系统提示词、上下文注入',
    icon: Icons.auto_awesome_rounded,
  ),
  SettingsCategory(
    title: '技能',
    description: '可启用的提示词工作流',
    icon: Icons.extension_rounded,
  ),
  SettingsCategory(
    title: 'MCP 与 Agent',
    description: 'MCP 服务器、工具与代理',
    icon: Icons.hub_outlined,
  ),
  SettingsCategory(
    title: '记忆归档',
    description: '长期记忆、旧对话归档',
    icon: Icons.memory_rounded,
  ),
  SettingsCategory(
    title: '角色与舞台',
    description: 'Rive 角色、静态图、外部模型',
    icon: Icons.face_retouching_natural_rounded,
  ),
  SettingsCategory(
    title: '外观',
    description: '主题、玻璃、动效',
    icon: Icons.palette_rounded,
  ),
  SettingsCategory(
    title: '数据与存储',
    description: '记忆库、导出与清理',
    icon: Icons.storage_rounded,
  ),
  SettingsCategory(
    title: '关于',
    description: '版本、许可与角色署名',
    icon: Icons.info_outline_rounded,
  ),
];

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings = widget.settings;
  int _selected = 0;

  void _apply(AppSettings next) {
    setState(() => _settings = next);
  }

  void _close() {
    Navigator.of(context).pop(_settings);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundTop,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.backgroundTop, AppColors.surface],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                return Column(
                  children: [
                    _SettingsBar(onBack: _close),
                    Expanded(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 280,
                                  child: _CategoryRail(
                                    selected: _selected,
                                    onSelect: (index) =>
                                        setState(() => _selected = index),
                                  ),
                                ),
                                Expanded(
                                  child: SettingsDetail(
                                    category: _categories[_selected],
                                    settings: _settings,
                                    backend: widget.backend,
                                    onChanged: _apply,
                                  ),
                                ),
                              ],
                            )
                          : _CategoryList(
                              settings: _settings,
                              onOpen: (index) async {
                                final result = await Navigator.of(context)
                                    .push<AppSettings>(
                                  MaterialPageRoute(
                                    builder: (_) => SettingsDetailPage(
                                      category: _categories[index],
                                      settings: _settings,
                                      backend: widget.backend,
                                    ),
                                  ),
                                );
                                if (result != null) _apply(result);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsBar extends StatelessWidget {
  _SettingsBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_rounded),
          ),
          Text(
            '设置',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  _CategoryRail({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 4, 20),
      children: [
        for (var i = 0; i < _categories.length; i++)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: Material(
              color: selected == i
                  ? AppColors.primaryContainer.withValues(alpha: 0.55)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelect(i),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _categories[i].icon,
                        size: 20,
                        color: selected == i
                            ? AppColors.primary
                            : AppColors.muted,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _categories[i].title,
                          style: TextStyle(
                            color: selected == i
                                ? AppColors.text
                                : AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryList extends StatelessWidget {
  _CategoryList({required this.settings, required this.onOpen});

  final AppSettings settings;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SummaryCard(settings: settings),
        SizedBox(height: 16),
        for (var i = 0; i < _categories.length; i++) ...[
          _CategoryTile(
            category: _categories[i],
            onTap: () => onOpen(i),
          ),
          SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  _SummaryCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final label = settings.mode == BackendMode.full
        ? (settings.apiKey.isEmpty ? 'Full · mock' : 'Full · native')
        : 'Only client';
    return GlassPanel(
      radius: 24,
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Image.asset('assets/mascot/avatar.png', width: 52, height: 52),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '大肥鱼',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '$label · ${settings.model}',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  _CategoryTile({required this.category, required this.onTap});

  final SettingsCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Icon(category.icon, size: 21, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      category.description,
                      style: TextStyle(
                        color: AppColors.muted.withValues(alpha: 0.7),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsDetailPage extends StatefulWidget {
  SettingsDetailPage({
    super.key,
    required this.category,
    required this.settings,
    required this.backend,
  });

  final SettingsCategory category;
  final AppSettings settings;
  final ChatBackend backend;

  @override
  State<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<SettingsDetailPage> {
  late AppSettings _draft = widget.settings;

  void _close() {
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundTop,
        appBar: AppBar(
          title: Text(widget.category.title),
          leading: BackButton(onPressed: _close),
        ),
        body: SettingsDetail(
          category: widget.category,
          settings: widget.settings,
          backend: widget.backend,
          onChanged: (next) => setState(() => _draft = next),
        ),
      ),
    );
  }
}

class SettingsDetail extends StatefulWidget {
  SettingsDetail({
    super.key,
    required this.category,
    required this.settings,
    required this.backend,
    required this.onChanged,
  });

  final SettingsCategory category;
  final AppSettings settings;
  final ChatBackend backend;
  final ValueChanged<AppSettings> onChanged;

  @override
  State<SettingsDetail> createState() => _SettingsDetailState();
}

class _SettingsDetailState extends State<SettingsDetail> {
  late AppSettings _settings = widget.settings;
  late final TextEditingController _apiKey =
      TextEditingController(text: _settings.apiKey);
  late final TextEditingController _model =
      TextEditingController(text: _settings.model);
  late final TextEditingController _fullBase =
      TextEditingController(text: _settings.fullBaseUrl);
  late final TextEditingController _clientBase =
      TextEditingController(text: _settings.clientBaseUrl);
  late final TextEditingController _clientToken =
      TextEditingController(text: _settings.clientToken);
  late final TextEditingController _systemPrompt =
      TextEditingController(text: _settings.systemPrompt);
  late String _provider =
      _settings.provider == 'mock' ? 'mock' : 'deepseek';

  List<TextEditingController> get _controllers => [
        _apiKey,
        _model,
        _fullBase,
        _clientBase,
        _clientToken,
        _systemPrompt,
      ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_emit);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_emit);
      controller.dispose();
    }
    super.dispose();
  }

  void _emit() {
    if (!mounted) return;
    final next = _collect();
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  AppSettings _collect() {
    return _settings.copyWith(
      apiKey: _apiKey.text.trim(),
      provider: _provider,
      model: _model.text.trim().isEmpty ? 'deepseek-flash' : _model.text.trim(),
      fullBaseUrl: _fullBase.text.trim().isEmpty
          ? 'https://api.deepseek.com'
          : _fullBase.text.trim(),
      clientBaseUrl: _clientBase.text.trim().isEmpty
          ? 'http://127.0.0.1:8080'
          : _clientBase.text.trim(),
      clientToken: _clientToken.text.trim(),
      systemPrompt: _systemPrompt.text.trim(),
    );
  }

  void _save() {
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _Header(category: widget.category),
        SizedBox(height: 18),
        if (widget.category.title == '连接与后端') _connection(),
        if (widget.category.title == '提示词与注入') _prompts(),
        if (widget.category.title == '技能') _skills(),
        if (widget.category.title == 'MCP 与 Agent') _mcp(),
        if (widget.category.title == '记忆归档') _memory(),
        if (widget.category.title == '角色与舞台') _character(),
        if (widget.category.title == '外观') _appearance(),
        if (widget.category.title == '数据与存储') _data(),
        if (widget.category.title == '关于') _about(),
        SizedBox(height: 22),
        if (widget.category.title == '连接与后端')
          FilledButton(
            onPressed: _save,
            child: Text('保存连接设置'),
          ),
      ],
    );
  }

  Widget _connection() {
    final full = _settings.mode == BackendMode.full;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<BackendMode>(
          segments: [
            ButtonSegment(
              value: BackendMode.full,
              label: Text('Full'),
              icon: Icon(Icons.memory_rounded),
            ),
            ButtonSegment(
              value: BackendMode.client,
              label: Text('Client'),
              icon: Icon(Icons.cloud_outlined),
            ),
          ],
          selected: {_settings.mode},
          onSelectionChanged: (value) {
            setState(() => _settings = _settings.copyWith(mode: value.first));
            _emit();
          },
        ),
        SizedBox(height: 16),
        if (full) ...[
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'deepseek', label: Text('DeepSeek')),
              ButtonSegment(value: 'mock', label: Text('Mock')),
            ],
            selected: {_provider},
            onSelectionChanged: (value) {
              setState(() => _provider = value.first);
              _emit();
            },
          ),
          SizedBox(height: 14),
          _Field(
            controller: _apiKey,
            label: 'API Key',
            hint: 'sk-…',
            obscure: true,
          ),
          SizedBox(height: 12),
          _Field(controller: _model, label: '模型', hint: 'deepseek-chat'),
          SizedBox(height: 12),
          _Field(
            controller: _fullBase,
            label: 'Base URL',
            hint: 'https://api.deepseek.com',
          ),
        ] else ...[
          _Field(
            controller: _clientBase,
            label: '服务器地址',
            hint: 'https://server:8080',
          ),
          SizedBox(height: 12),
          _Field(
            controller: _clientToken,
            label: 'Server Token',
            hint: '可选',
            obscure: true,
          ),
        ],
        SizedBox(height: 12),
        Text(
          full
              ? 'Full 使用 libchatvv_ffi.so；不需要 127.0.0.1 或 adb reverse。'
              : 'Only client 使用 HTTPS/SSE；服务器需可访问。',
          style: TextStyle(
            color: AppColors.muted.withValues(alpha: 0.6),
            fontSize: 10.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _prompts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _systemPrompt,
          minLines: 5,
          maxLines: 10,
          style: TextStyle(color: AppColors.text, fontSize: 13),
          decoration: InputDecoration(
            labelText: '系统提示词',
            hintText: '留空使用默认人格',
            alignLabelWithHint: true,
            labelStyle: TextStyle(color: AppColors.muted, fontSize: 11),
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
            contentPadding: EdgeInsets.fromLTRB(14, 12, 14, 12),
          ),
        ),
        SizedBox(height: 18),
        Row(
          children: [
            Text(
              '上下文注入',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Spacer(),
            TextButton.icon(
              onPressed: _editInjection,
              icon: Icon(Icons.add_rounded, size: 18),
              label: Text('新建'),
            ),
          ],
        ),
        if (_settings.injections.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '暂无注入。文件附件也会以注入形式进入上下文。',
              style: TextStyle(
                color: AppColors.muted.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
          )
        else
          for (var i = 0; i < _settings.injections.length; i++) ...[
            _InjectionTile(
              injection: _settings.injections[i],
              onEdit: () => _editInjection(_settings.injections[i]),
              onDelete: () => _removeInjection(i),
              onToggle: (enabled) {
                final next = [..._settings.injections];
                next[i] = next[i].copyWith(enabled: enabled);
                setState(
                  () => _settings = _settings.copyWith(injections: next),
                );
                _emit();
              },
            ),
            SizedBox(height: 8),
          ],
      ],
    );
  }

  Future<void> _editInjection([PromptInjection? initial]) async {
    final result = await Navigator.of(context).push<PromptInjection>(
      MaterialPageRoute(
        builder: (_) => InjectionEditorPage(initial: initial),
      ),
    );
    if (!mounted || result == null) return;
    final next = [..._settings.injections];
    final index = next.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.add(result);
    }
    setState(() => _settings = _settings.copyWith(injections: next));
    _emit();
  }

  void _removeInjection(int index) {
    final next = [..._settings.injections]..removeAt(index);
    setState(() => _settings = _settings.copyWith(injections: next));
    _emit();
  }

  Future<void> _editSkill([Skill? initial]) async {
    final result = await Navigator.of(context).push<Skill>(
      MaterialPageRoute(builder: (_) => SkillEditorPage(initial: initial)),
    );
    if (!mounted || result == null) return;
    final next = [..._settings.skills];
    final index = next.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      next[index] = result;
    } else {
      next.add(result);
    }
    setState(() => _settings = _settings.copyWith(skills: next));
    _emit();
  }

  void _removeSkill(int index) {
    final next = [..._settings.skills]..removeAt(index);
    setState(() => _settings = _settings.copyWith(skills: next));
    _emit();
  }

  Widget _skills() {
    return Column(
      children: [
        Row(
          children: [
            Text(
              '已安装技能',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Spacer(),
            TextButton.icon(
              onPressed: () => _editSkill(),
              icon: Icon(Icons.add_rounded, size: 18),
              label: Text('新建'),
            ),
          ],
        ),
        if (_settings.skills.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '暂无技能。技能是启用后自动加入系统提示词的工作流。',
              style: TextStyle(
                color: AppColors.muted.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
          )
        else
          for (var i = 0; i < _settings.skills.length; i++) ...[
            Container(
              padding: EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _settings.skills[i].name,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_settings.skills[i].description.isNotEmpty) ...[
                          SizedBox(height: 3),
                          Text(
                            _settings.skills[i].description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Switch(
                    value: _settings.skills[i].enabled,
                    onChanged: (enabled) {
                      final next = [..._settings.skills];
                      next[i] = next[i].copyWith(enabled: enabled);
                      setState(
                        () => _settings = _settings.copyWith(skills: next),
                      );
                      _emit();
                    },
                  ),
                  IconButton(
                    onPressed: () => _removeSkill(i),
                    icon: Icon(Icons.delete_outline_rounded, size: 18),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
          ],
        SizedBox(height: 12),
        _SettingCard(
          icon: Icons.smart_toy_outlined,
          title: 'Agent 模式',
          subtitle: '系统提示词已预留，MCP 工具循环下一步接入',
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: null,
        ),
      ],
    );
  }

  Widget _mcp() {
    return McpPane(
      settings: _settings,
      onChanged: (next) {
        setState(() => _settings = next);
        _emit();
      },
    );
  }

  Widget _memory() {
    return MemoryArchivePane(backend: widget.backend);
  }

  Future<void> _importRive() async {
    try {
      final picked = await pickRiveFile();
      if (picked == null || !mounted) return;
      final support = await appSupportDirectory();
      final dir = Directory('${support.path}/character');
      await dir.create(recursive: true);
      final lower = picked.name.toLowerCase();
      if (lower.endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(picked.bytes);
        final modelDir = Directory('${dir.path}/live2d_imported');
        if (await modelDir.exists()) {
          await modelDir.delete(recursive: true);
        }
        await modelDir.create(recursive: true);
        String? modelFile;
        for (final entry in archive) {
          if (!entry.isFile) continue;
          final name = entry.name.replaceAll('\\', '/');
          if (name.contains('..') || name.startsWith('/')) continue;
          final target = File('${modelDir.path}/$name');
          await target.parent.create(recursive: true);
          await target.writeAsBytes(entry.content as List<int>, flush: true);
          if (name.endsWith('.model3.json') && modelFile == null) {
            modelFile = name;
          }
        }
        if (modelFile == null) {
          throw FormatException('ZIP 中没有 .model3.json');
        }
        setState(() {
          _settings = _settings.copyWith(
            characterMode: CharacterMode.live2dExternal,
            live2dDir: modelDir.path,
            live2dModel: modelFile,
            characterRivePath: '',
          );
        });
      } else {
        final extension = lower.endsWith('.svg') ? 'svg' : 'riv';
        final file = File('${dir.path}/imported.$extension');
        await file.writeAsBytes(picked.bytes, flush: true);
        setState(() {
          _settings = _settings.copyWith(
            characterRivePath: file.path,
            characterMode: CharacterMode.custom,
          );
        });
      }
      _emit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${picked.name}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$error')),
      );
    }
  }

  void _clearRive() {
    setState(() {
      _settings = _settings.copyWith(
        characterRivePath: '',
        live2dDir: '',
        live2dModel: '',
        characterMode: CharacterMode.rive,
      );
    });
    _emit();
  }

  void _setCharacterMode(CharacterMode mode) {
    setState(() => _settings = _settings.copyWith(characterMode: mode));
    _emit();
  }

  void _setColorMode(AppColorMode mode) {
    setState(() => _settings = _settings.copyWith(colorMode: mode));
    appThemeController.setMode(mode);
    _emit();
  }

  Widget _character() {
    return Column(
      children: [
        _SettingCard(
          icon: Icons.view_in_ar_rounded,
          title: 'Live2D · DS 鲸鱼娘',
          subtitle: '眨眼 · 呼吸 · 口形追踪',
          trailing: _settings.characterMode == CharacterMode.live2d
              ? Icon(Icons.check_rounded, color: AppColors.success)
              : Icon(Icons.chevron_right_rounded),
          onTap: () => _setCharacterMode(CharacterMode.live2d),
        ),
        if (_settings.live2dDir.isNotEmpty) ...[
          SizedBox(height: 10),
          _SettingCard(
            icon: Icons.folder_special_outlined,
            title: 'Live2D · 外部模型',
            subtitle: _settings.live2dModel,
            trailing: _settings.characterMode == CharacterMode.live2dExternal
                ? Icon(Icons.check_rounded, color: AppColors.success)
                : Icon(Icons.chevron_right_rounded),
            onTap: () => _setCharacterMode(CharacterMode.live2dExternal),
          ),
        ],
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.image_rounded,
          title: '立绘 · 女仆装',
          subtitle: '正面全身 · 默认',
          trailing: _settings.characterMode == CharacterMode.staticImage
              ? Icon(Icons.check_rounded, color: AppColors.success)
              : Icon(Icons.chevron_right_rounded),
          onTap: () => _setCharacterMode(CharacterMode.staticImage),
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.image_rounded,
          title: '立绘 · 蓝色女仆',
          subtitle: '替换服装立绘',
          trailing: _settings.characterMode == CharacterMode.altImage
              ? Icon(Icons.check_rounded, color: AppColors.success)
              : Icon(Icons.chevron_right_rounded),
          onTap: () => _setCharacterMode(CharacterMode.altImage),
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.view_in_ar_rounded,
          title: 'Rive 角色',
          subtitle: '内置 walking.riv · 待机动画',
          trailing: _settings.characterMode == CharacterMode.rive
              ? Icon(Icons.check_rounded, color: AppColors.success)
              : Icon(Icons.chevron_right_rounded),
          onTap: () => _setCharacterMode(CharacterMode.rive),
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.download_rounded,
          title: '导入外部模型',
          subtitle: _settings.characterRivePath.isEmpty
              ? '支持 Rive .riv / SVG / Live2D .zip'
              : '当前：${_settings.characterRivePath.split('/').last} · 点击重新导入',
          trailing: _settings.characterMode == CharacterMode.custom
              ? Icon(Icons.check_rounded, color: AppColors.success)
              : Icon(Icons.chevron_right_rounded),
          onTap: _importRive,
        ),
        if (_settings.characterRivePath.isNotEmpty) ...[
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _clearRive,
              icon: Icon(Icons.restore_rounded, size: 16),
              label: Text('恢复内置角色'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _appearance() {
    // Use the live controller as the source of truth. The settings copy can
    // lag behind while the async palette is being generated.
    final selected = appThemeController.mode;
    return Column(
      children: [
        _SettingCard(
          icon: Icons.water_rounded,
          title: '深海玻璃',
          subtitle: '经典配色',
          trailing: selected == AppColorMode.classic
              ? Icon(Icons.check_rounded, color: AppColors.success)
              : Icon(Icons.chevron_right_rounded),
          onTap: () => _setColorMode(AppColorMode.classic),
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.auto_awesome_rounded,
          title: '系统动态颜色',
          subtitle: 'Material You · 跟随系统壁纸',
          trailing: selected == AppColorMode.system
              ? Icon(Icons.check_rounded, color: AppColors.success)
              : Icon(Icons.chevron_right_rounded),
          onTap: () => _setColorMode(AppColorMode.system),
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.colorize_rounded,
          title: '从舞台取色',
          subtitle: '提取 DS 鲸鱼娘立绘主色',
          trailing: selected == AppColorMode.stage
              ? Icon(Icons.check_rounded, color: AppColors.success)
              : Icon(Icons.chevron_right_rounded),
          onTap: () => _setColorMode(AppColorMode.stage),
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.blur_on_rounded,
          title: '玻璃强度',
          subtitle: 'BackdropFilter · 2–3 个表面',
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: null,
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.animation_rounded,
          title: '动效',
          subtitle: '跟随系统 Reduce Motion',
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: null,
        ),
      ],
    );
  }

  Widget _data() {
    return FutureBuilder(
      future: appSupportDirectory(),
      builder: (context, snapshot) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '本地目录',
              style: TextStyle(color: AppColors.muted.withValues(alpha: 0.7), fontSize: 10),
            ),
            SizedBox(height: 6),
            SelectableText(
              snapshot.data?.path ?? '加载中…',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            SizedBox(height: 16),
            _SettingCard(
              icon: Icons.ios_share_rounded,
              title: '导出记忆库',
              subtitle: 'SQLite 导出（下一步）',
              trailing: Icon(Icons.lock_outline, size: 16),
              onTap: null,
            ),
            SizedBox(height: 10),
            _SettingCard(
              icon: Icons.delete_outline_rounded,
              title: '清空对话',
              subtitle: '保留设置，清空 SQLite 消息',
              trailing: Icon(Icons.lock_outline, size: 16),
              onTap: null,
            ),
          ],
        );
      },
    );
  }

  Widget _about() {
    return Column(
      children: [
        _SettingCard(
          icon: Icons.info_outline_rounded,
          title: 'ChatVivid',
          subtitle: '$buildLabel · commit $commitLabel · Flutter 3.44',
          trailing: SizedBox.shrink(),
          onTap: null,
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.article_outlined,
          title: '开源许可',
          subtitle: 'Flutter、Rive、llama.cpp 等第三方许可',
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'ChatVivid',
            applicationVersion: buildLabel,
          ),
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.face_rounded,
          title: '角色与资产署名',
          subtitle: 'Live2D 模型 / 大肥鱼角色 / Rive / BGE',
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('角色与资产署名'),
              content: SingleChildScrollView(
                child: Text(
                  'Live2D「DS 鲸鱼娘」：上善无形 / ZipZipPipe / 氵六青\n'
                  '模型素材 CC BY-NC-SA 4.0（非商业、署名、相同方式共享）\n'
                  'Live2D Cubism Core 版权归 Live2D Inc.，按其 SDK 条款使用\n\n'
                  '默认 Rive 动画：Rive Flutter 示例资产 walking.riv\n'
                  'RAG embedding：BAAI bge-small-zh-v1.5 (MIT)，经 llama.cpp 加载\n\n'
                  'Rive runtime 为 MIT 许可；示例资产请按原仓库许可使用。',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('关闭'),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 10),
        _SettingCard(
          icon: Icons.code_rounded,
          title: '源代码',
          subtitle: 'github.com/YUN-LOVE/ChatVivid',
          trailing: Icon(Icons.copy_rounded, size: 16),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('https://github.com/YUN-LOVE/ChatVivid'),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _InjectionTile extends StatelessWidget {
  _InjectionTile({
    required this.injection,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final PromptInjection injection;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Switch(
            value: injection.enabled,
            onChanged: onToggle,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  injection.name,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '${injection.position} · ${injection.mode} · ${injection.trust}',
                  style: TextStyle(
                    color: AppColors.muted.withValues(alpha: 0.65),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  _Header({required this.category});

  final SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(category.icon, color: AppColors.primary, size: 24),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category.title,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              category.description,
              style: TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: AppColors.text, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.muted, fontSize: 11),
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
        contentPadding: EdgeInsets.fromLTRB(14, 12, 14, 12),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.muted.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
