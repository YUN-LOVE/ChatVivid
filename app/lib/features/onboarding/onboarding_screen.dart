// ignore_for_file: prefer_const_constructors_in_immutables
import 'package:flutter/material.dart';

import '../../data/app_settings.dart';
import '../../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  OnboardingScreen({
    super.key,
    required this.initial,
    required this.onComplete,
  });

  final AppSettings initial;
  final Future<void> Function(AppSettings settings) onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static final _steps = ['欢迎', '运行方式', '连接', '就绪'];

  final PageController _pages = PageController();
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _fullBase;
  late final TextEditingController _clientBase;
  late final TextEditingController _clientToken;
  late BackendMode _mode;
  late String _provider;
  int _index = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.initial;
    _mode = settings.mode;
    _provider = settings.provider == 'mock' ? 'mock' : 'deepseek';
    _apiKey = TextEditingController(text: settings.apiKey);
    _model = TextEditingController(text: settings.model);
    _fullBase = TextEditingController(text: settings.fullBaseUrl);
    _clientBase = TextEditingController(text: settings.clientBaseUrl);
    _clientToken = TextEditingController(text: settings.clientToken);
  }

  @override
  void dispose() {
    _pages.dispose();
    _apiKey.dispose();
    _model.dispose();
    _fullBase.dispose();
    _clientBase.dispose();
    _clientToken.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _steps.length - 1;

  Future<void> _next() async {
    if (_saving) return;
    if (_isLast) {
      await _finish();
      return;
    }
    await _pages.animateToPage(
      _index + 1,
      duration: Duration(milliseconds: 380),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  Future<void> _back() async {
    if (_index == 0 || _saving) return;
    await _pages.animateToPage(
      _index - 1,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final settings = widget.initial.copyWith(
      mode: _mode,
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
      onboardingComplete: true,
    );
    await widget.onComplete(settings);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.backgroundTop,
              AppColors.backgroundMid,
              AppColors.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Progress(labels: _steps, index: _index),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: _saving
                      ? NeverScrollableScrollPhysics()
                      : null,
                  onPageChanged: (value) => setState(() => _index = value),
                  children: [
                    _WelcomePage(mode: _mode),
                    _ModePage(
                      mode: _mode,
                      onChanged: (value) => setState(() => _mode = value),
                    ),
                    _ConnectionPage(
                      mode: _mode,
                      provider: _provider,
                      onProviderChanged: (value) =>
                          setState(() => _provider = value),
                      apiKey: _apiKey,
                      model: _model,
                      fullBase: _fullBase,
                      clientBase: _clientBase,
                      clientToken: _clientToken,
                    ),
                    _ReadyPage(
                      mode: _mode,
                      provider: _provider,
                      hasApiKey: _apiKey.text.trim().isNotEmpty,
                    ),
                  ],
                ),
              ),
              _BottomBar(
                index: _index,
                saving: _saving,
                isLast: _isLast,
                onBack: _back,
                onNext: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  _Progress({required this.labels, required this.index});

  final List<String> labels;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                labels[index],
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              Spacer(),
              Text(
                '${index + 1} / ${labels.length}',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 260),
                    height: 5,
                    decoration: BoxDecoration(
                      color: i <= index
                          ? AppColors.primary
                          : AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  _WelcomePage({required this.mode});

  final BackendMode mode;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 28, 24, 20),
      children: [
        Center(
          child: Image.asset('assets/mascot/avatar_circle.png', width: 150),
        ),
        SizedBox(height: 18),
        Text(
          '把记忆\n留在自己手里',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: 12),
        Text(
          '单对话、长期记忆，默认只在本机。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted.withValues(alpha: 0.85),
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _ModePage extends StatelessWidget {
  _ModePage({required this.mode, required this.onChanged});

  final BackendMode mode;
  final ValueChanged<BackendMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 20),
      children: [
        Text(
          '选择运行方式',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '可随时切换，共用同一套聊天界面。',
          style: TextStyle(
            color: AppColors.muted.withValues(alpha: 0.8),
            fontSize: 12,
            height: 1.5,
          ),
        ),
        SizedBox(height: 22),
        _ModeCard(
          selected: mode == BackendMode.full,
          icon: Icons.memory_rounded,
          title: 'Full · 内嵌 C++',
          subtitle: '推荐',
          body: 'C++ core 在 App 内，无端口、无回环。',
          onTap: () => onChanged(BackendMode.full),
        ),
        SizedBox(height: 12),
        _ModeCard(
          selected: mode == BackendMode.client,
          icon: Icons.cloud_outlined,
          title: 'Only client',
          subtitle: '远程',
          body: '连接你自己的 chatvvd。',
          onTap: () => onChanged(BackendMode.client),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 180),
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryContainer.withValues(alpha: 0.55)
                : AppColors.surfaceHigh.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: AppColors.muted.withValues(alpha: 0.65),
                            fontSize: 9,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 7),
                    Text(
                      body,
                      style: TextStyle(
                        color: AppColors.muted.withValues(alpha: 0.85),
                        fontSize: 11.5,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionPage extends StatelessWidget {
  _ConnectionPage({
    required this.mode,
    required this.provider,
    required this.onProviderChanged,
    required this.apiKey,
    required this.model,
    required this.fullBase,
    required this.clientBase,
    required this.clientToken,
  });

  final BackendMode mode;
  final String provider;
  final ValueChanged<String> onProviderChanged;
  final TextEditingController apiKey;
  final TextEditingController model;
  final TextEditingController fullBase;
  final TextEditingController clientBase;
  final TextEditingController clientToken;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 20),
      children: [
        Text(
          mode == BackendMode.full ? '连接模型' : '连接服务器',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8),
        SizedBox(height: 18),
        if (mode == BackendMode.full) ...[
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'deepseek', label: Text('DeepSeek')),
              ButtonSegment(value: 'mock', label: Text('Mock')),
            ],
            selected: {provider},
            onSelectionChanged: (value) => onProviderChanged(value.first),
          ),
          SizedBox(height: 16),
          _Field(
            controller: apiKey,
            label: 'API Key',
            hint: 'sk-…（留空先用 mock）',
            obscure: true,
          ),
          SizedBox(height: 12),
          _Field(controller: model, label: '模型', hint: 'deepseek-chat'),
          SizedBox(height: 12),
          _Field(
            controller: fullBase,
            label: 'Base URL',
            hint: 'https://api.deepseek.com',
          ),
        ] else ...[
          _Field(
            controller: clientBase,
            label: '服务器地址',
            hint: 'https://your-server:8080',
          ),
          SizedBox(height: 12),
          _Field(
            controller: clientToken,
            label: 'Server Token（可选）',
            hint: 'chatvvd 的 Bearer token',
            obscure: true,
          ),
        ],
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

class _ReadyPage extends StatelessWidget {
  _ReadyPage({
    required this.mode,
    required this.provider,
    required this.hasApiKey,
  });

  final BackendMode mode;
  final String provider;
  final bool hasApiKey;

  @override
  Widget build(BuildContext context) {
    final effectiveProvider = mode == BackendMode.full && !hasApiKey
        ? 'mock'
        : provider;
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 28, 24, 20),
      children: [
        Center(
          child: Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 54,
          ),
        ),
        SizedBox(height: 18),
        Text(
          '记忆体已就绪',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 10),
        Text(
          '${mode.label}\nProvider: $effectiveProvider',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted.withValues(alpha: 0.8),
            fontSize: 12,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  _BottomBar({
    required this.index,
    required this.saving,
    required this.isLast,
    required this.onBack,
    required this.onNext,
  });

  final int index;
  final bool saving;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          if (index > 0)
            TextButton(
              onPressed: saving ? null : onBack,
              child: Text('上一步'),
            )
          else
            SizedBox(width: 64),
          Spacer(),
          FilledButton.icon(
            onPressed: saving ? null : onNext,
            icon: Icon(
              isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
            ),
            iconAlignment: IconAlignment.end,
            label: Text(
              saving
                  ? '保存中…'
                  : isLast
                      ? '开始使用'
                      : '继续',
            ),
          ),
        ],
      ),
    );
  }
}
