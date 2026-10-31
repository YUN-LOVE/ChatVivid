import 'package:flutter/material.dart';

import '../../data/app_paths.dart';
import '../../data/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class SettingsCategory {
  const SettingsCategory({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}

const _categories = [
  SettingsCategory(
    title: '连接与后端',
    description: 'Full / Only client、模型与 API Key',
    icon: Icons.hub_rounded,
  ),
  SettingsCategory(
    title: '角色与舞台',
    description: '静态角色、Live2D、外部模型',
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
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      body: DecoratedBox(
        decoration: const BoxDecoration(
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
    );
  }
}

class _SettingsBar extends StatelessWidget {
  const _SettingsBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const Text(
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
  const _CategoryRail({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 20),
      children: [
        for (var i = 0; i < _categories.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Material(
              color: selected == i
                  ? AppColors.primaryContainer.withValues(alpha: 0.55)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelect(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
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
                      const SizedBox(width: 12),
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
  const _CategoryList({required this.settings, required this.onOpen});

  final AppSettings settings;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SummaryCard(settings: settings),
        const SizedBox(height: 16),
        for (var i = 0; i < _categories.length; i++) ...[
          _CategoryTile(
            category: _categories[i],
            onTap: () => onOpen(i),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final label = settings.mode == BackendMode.full
        ? (settings.apiKey.isEmpty ? 'Full · mock' : 'Full · native')
        : 'Only client';
    return GlassPanel(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Image.asset('assets/mascot/avatar.png', width: 52, height: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '水仙女',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$label · ${settings.model}',
                  style: const TextStyle(
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
  const _CategoryTile({required this.category, required this.onTap});

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
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Icon(category.icon, size: 21, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
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
              const Icon(
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

class SettingsDetailPage extends StatelessWidget {
  const SettingsDetailPage({
    super.key,
    required this.category,
    required this.settings,
  });

  final SettingsCategory category;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      appBar: AppBar(
        title: Text(category.title),
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SettingsDetail(
        category: category,
        settings: settings,
        onChanged: (next) => Navigator.of(context).pop(next),
      ),
    );
  }
}

class SettingsDetail extends StatefulWidget {
  const SettingsDetail({
    super.key,
    required this.category,
    required this.settings,
    required this.onChanged,
  });

  final SettingsCategory category;
  final AppSettings settings;
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
  late String _provider =
      _settings.provider == 'mock' ? 'mock' : 'deepseek';

  @override
  void dispose() {
    _apiKey.dispose();
    _model.dispose();
    _fullBase.dispose();
    _clientBase.dispose();
    _clientToken.dispose();
    super.dispose();
  }

  AppSettings _collect() {
    return _settings.copyWith(
      apiKey: _apiKey.text.trim(),
      provider: _provider,
      model: _model.text.trim().isEmpty ? 'deepseek-chat' : _model.text.trim(),
      fullBaseUrl: _fullBase.text.trim().isEmpty
          ? 'https://api.deepseek.com'
          : _fullBase.text.trim(),
      clientBaseUrl: _clientBase.text.trim().isEmpty
          ? 'http://127.0.0.1:8080'
          : _clientBase.text.trim(),
      clientToken: _clientToken.text.trim(),
    );
  }

  void _save() {
    final next = _collect();
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _Header(category: widget.category),
        const SizedBox(height: 18),
        if (widget.category.title == '连接与后端') _connection(),
        if (widget.category.title == '角色与舞台') _character(),
        if (widget.category.title == '外观') _appearance(),
        if (widget.category.title == '数据与存储') _data(),
        if (widget.category.title == '关于') _about(),
        const SizedBox(height: 22),
        if (widget.category.title == '连接与后端')
          FilledButton(
            onPressed: _save,
            child: const Text('保存连接设置'),
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
          segments: const [
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
          },
        ),
        const SizedBox(height: 16),
        if (full) ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'deepseek', label: Text('DeepSeek')),
              ButtonSegment(value: 'mock', label: Text('Mock')),
            ],
            selected: {_provider},
            onSelectionChanged: (value) {
              setState(() => _provider = value.first);
            },
          ),
          const SizedBox(height: 14),
          _Field(
            controller: _apiKey,
            label: 'API Key',
            hint: 'sk-…',
            obscure: true,
          ),
          const SizedBox(height: 12),
          _Field(controller: _model, label: '模型', hint: 'deepseek-chat'),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          _Field(
            controller: _clientToken,
            label: 'Server Token',
            hint: '可选',
            obscure: true,
          ),
        ],
        const SizedBox(height: 12),
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

  Widget _character() {
    return Column(
      children: [
        _SettingCard(
          icon: Icons.image_rounded,
          title: '静态角色',
          subtitle: '当前启用 · 大肥鱼头像/立绘',
          trailing: const Icon(Icons.check_rounded, color: AppColors.success),
          onTap: () {},
        ),
        const SizedBox(height: 10),
        _SettingCard(
          icon: Icons.view_in_ar_rounded,
          title: 'Live2D',
          subtitle: 'adapter 渲染验证中，暂不启用',
          trailing: const Text(
            'EXPERIMENTAL',
            style: TextStyle(color: AppColors.muted, fontSize: 8),
          ),
          onTap: () {},
        ),
        const SizedBox(height: 10),
        _SettingCard(
          icon: Icons.download_rounded,
          title: '导入外部模型',
          subtitle: 'VRM / Live2D 文件夹',
          trailing: const Icon(Icons.lock_outline, size: 16),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _appearance() {
    return Column(
      children: [
        _SettingCard(
          icon: Icons.water_rounded,
          title: 'Deep Sea Glass',
          subtitle: '当前主题',
          trailing: const Icon(Icons.check_rounded, color: AppColors.success),
          onTap: () {},
        ),
        const SizedBox(height: 10),
        const _SettingCard(
          icon: Icons.blur_on_rounded,
          title: '玻璃强度',
          subtitle: 'BackdropFilter · 2–3 个表面',
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: null,
        ),
        const SizedBox(height: 10),
        const _SettingCard(
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
            const SizedBox(height: 6),
            SelectableText(
              snapshot.data?.path ?? '加载中…',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),
            const _SettingCard(
              icon: Icons.ios_share_rounded,
              title: '导出记忆库',
              subtitle: 'SQLite 导出（下一步）',
              trailing: Icon(Icons.lock_outline, size: 16),
              onTap: null,
            ),
            const SizedBox(height: 10),
            const _SettingCard(
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
        const _SettingCard(
          icon: Icons.info_outline_rounded,
          title: 'chatvv',
          subtitle: '0.1.0 · Flutter 3.44 · C++23 core',
          trailing: SizedBox.shrink(),
          onTap: null,
        ),
        const SizedBox(height: 10),
        const _SettingCard(
          icon: Icons.article_outlined,
          title: '开源许可',
          subtitle: '查看第三方许可',
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: null,
        ),
        const SizedBox(height: 10),
        const _SettingCard(
          icon: Icons.face_rounded,
          title: '角色署名',
          subtitle: '上善无形 / ZipZipPipe / 氵六青',
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: null,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.category});

  final SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(category.icon, color: AppColors.primary, size: 24),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category.title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              category.description,
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
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

class _SettingCard extends StatelessWidget {
  const _SettingCard({
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
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
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
