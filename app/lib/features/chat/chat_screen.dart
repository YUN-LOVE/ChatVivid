import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/app_settings.dart';
import '../../data/backend_factory.dart';
import '../settings/settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../character/character_stage.dart';
import 'chat_controller.dart';
import 'chat_models.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final Future<void> Function(AppSettings settings) onSettingsChanged;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatController? _chat;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _loading = true;
  String? _lastId;
  int _lastLength = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_loading && _chat != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backend = await createChatBackend(widget.settings);
      final chat = ChatController(api: backend);
      chat.addListener(_onChatChanged);
      await chat.initialize();
      if (!mounted) {
        chat.removeListener(_onChatChanged);
        chat.dispose();
        return;
      }
      setState(() {
        _chat = chat;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _onChatChanged() {
    final chat = _chat;
    if (chat == null || chat.messages.isEmpty || !_scroll.hasClients) return;
    final last = chat.messages.last;
    final changed = last.id != _lastId || last.content.length != _lastLength;
    _lastId = last.id;
    _lastLength = last.content.length;
    if (!changed) return;

    final distance =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (distance < 240 || last.isUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  void _send() {
    final chat = _chat;
    final text = _input.text;
    if (chat == null || text.trim().isEmpty || chat.busy) return;
    _input.clear();
    _focus.requestFocus();
    chat.send(text);
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
    if (!mounted || updated == null) return;
    if (updated.cacheKey != widget.settings.cacheKey) {
      await widget.onSettingsChanged(updated);
    }
  }

  @override
  void dispose() {
    final chat = _chat;
    if (chat != null) {
      chat.removeListener(_onChatChanged);
      chat.dispose();
    }
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    if (chat == null) {
      return _BootstrapScreen(
        loading: _loading,
        error: _error,
        onRetry: _bootstrap,
      );
    }
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom > 0;
    final stageHeight = keyboard
        ? 0.0
        : math.min(320.0, math.max(220.0, media.size.height * 0.30));

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          const _DeepSeaBackground(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(chat: chat, onSettings: _openSettings),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  height: stageHeight,
                  child: stageHeight > 0
                      ? const CharacterStage()
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: _ChatSurface(
                    chat: chat,
                    scroll: _scroll,
                  ),
                ),
                AnimatedBuilder(
                  animation: chat,
                  builder: (context, _) => _Composer(
                    chat: chat,
                    controller: _input,
                    focus: _focus,
                    onSend: _send,
                    onStop: chat.stop,
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

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final Future<void> Function() onRetry;

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
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/mascot/avatar.png',
                  width: 96,
                  height: 96,
                ),
                const SizedBox(height: 20),
                if (loading) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '正在初始化记忆体…',
                    style: TextStyle(
                      color: AppColors.muted.withValues(alpha: 0.75),
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ] else ...[
                  Text(
                    error ?? '初始化失败',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.coral,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => onRetry(),
                    child: const Text('重试'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.chat, required this.onSettings});

  final ChatController chat;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: GlassPanel(
        radius: 24,
        blur: 18,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: ListenableBuilder(
          listenable: chat,
          builder: (context, _) {
            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.surfaceHigh,
                  backgroundImage:
                      const AssetImage('assets/mascot/avatar.png'),
                ),
                const SizedBox(width: 10),
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
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        chat.backendLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.muted.withValues(alpha: 0.72),
                          fontSize: 9,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusDot(online: chat.online),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onSettings,
                  tooltip: '连接设置',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune_rounded, size: 19),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? AppColors.success : AppColors.coral,
            boxShadow: [
              if (online)
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          online ? 'LINKED' : 'OFFLINE',
          style: TextStyle(
            color: AppColors.muted.withValues(alpha: 0.6),
            fontSize: 7,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ChatSurface extends StatelessWidget {
  const _ChatSurface({required this.chat, required this.scroll});

  final ChatController chat;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ListenableBuilder(
              listenable: chat,
              builder: (context, _) {
                final messages = chat.messages;
                if (messages.isEmpty) {
                  return const _EmptyChat();
                }
                return ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _MessageTile(
                    message: messages[index],
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 10,
            left: 16,
            right: 16,
            child: ListenableBuilder(
              listenable: chat,
              builder: (context, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: chat.online
                    ? const SizedBox.shrink()
                    : const _OfflinePill(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          margin: const EdgeInsets.only(bottom: 14, left: 36),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer.withValues(alpha: 0.82),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(6),
            ),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.18),
            ),
          ),
          child: SelectableText(
            message.content,
            style: const TextStyle(
              color: AppColors.onPrimaryContainer,
              fontSize: 14.5,
              height: 1.55,
            ),
          ),
        ),
      );
    }

    final body = message.content.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surfaceHigh,
            backgroundImage: const AssetImage('assets/mascot/avatar.png'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '水仙女',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MEMORY ENTITY',
                      style: TextStyle(
                        color: AppColors.muted.withValues(alpha: 0.48),
                        fontSize: 7,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                if (body.isEmpty && message.streaming)
                  const _ThinkingLine()
                else
                  SelectableText.rich(
                    TextSpan(
                      text: body,
                      children: [
                        if (message.streaming)
                          const TextSpan(
                            text: '  ▍',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      height: 1.58,
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

class _ThinkingLine extends StatelessWidget {
  const _ThinkingLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.3,
            color: AppColors.primary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '思考中…',
          style: TextStyle(
            color: AppColors.muted.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.coral.withValues(alpha: 0.26)),
        ),
        child: const Text(
          'OFFLINE · 检查后端 / adb reverse',
          style: TextStyle(
            color: AppColors.coral,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/mascot/avatar.png', width: 88, height: 88),
          const SizedBox(height: 12),
          Text(
            '记忆体已就绪',
            style: TextStyle(
              color: AppColors.muted.withValues(alpha: 0.72),
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.chat,
    required this.controller,
    required this.focus,
    required this.onSend,
    required this.onStop,
  });

  final ChatController chat;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: SafeArea(
        top: false,
        child: GlassPanel(
          radius: 28,
          blur: 20,
          padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14.5,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    hintText: '说点什么…',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final canSend = value.text.trim().isNotEmpty && !chat.busy;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: chat.busy
                        ? IconButton.filled(
                            key: const ValueKey('stop'),
                            onPressed: onStop,
                            tooltip: '停止',
                            icon: const Icon(Icons.stop_rounded, size: 20),
                          )
                        : IconButton.filled(
                            key: const ValueKey('send'),
                            onPressed: canSend ? onSend : null,
                            tooltip: '发送',
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 20,
                            ),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeepSeaBackground extends StatelessWidget {
  const _DeepSeaBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.backgroundTop,
            AppColors.backgroundMid,
            AppColors.surface,
          ],
          stops: [0, 0.52, 1],
        ),
      ),
    );
  }
}
