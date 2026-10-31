import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/settings_store.dart';
import '../features/chat/chat_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../theme/app_theme.dart';

/// Loads settings and storage before showing the chat. This is the equivalent
/// of Kazumi's startup gate: storage failure gets its own screen, first run
/// goes through onboarding, and only then is the chat backend created.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  SettingsStore? _store;
  AppSettings? _settings;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = await SettingsStore.open();
      final settings = await store.load();
      if (!mounted) return;
      setState(() {
        _store = store;
        _settings = settings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _completeOnboarding(AppSettings settings) async {
    await _store?.save(settings);
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _saveSettings(AppSettings settings) async {
    await _store?.save(settings);
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _GateLoading();
    if (_error != null) {
      return _GateError(error: _error!, onRetry: _load);
    }
    final settings = _settings!;
    if (!settings.onboardingComplete) {
      return OnboardingScreen(
        initial: settings,
        onComplete: _completeOnboarding,
      );
    }
    return ChatScreen(
      key: ValueKey(settings.cacheKey),
      settings: settings,
      onSettingsChanged: _saveSettings,
    );
  }
}

class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.backgroundTop,
      body: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
    );
  }
}

class _GateError extends StatelessWidget {
  const _GateError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.coral,
                size: 34,
              ),
              const SizedBox(height: 12),
              const Text(
                '初始化失败',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => onRetry(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
