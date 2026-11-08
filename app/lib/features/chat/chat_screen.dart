import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_settings.dart';
import '../../data/backend_factory.dart';
import '../../data/prompt_injection.dart';
import '../settings/settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../character/character_stage.dart';
import 'chat_attachment.dart';
import 'markdown_message.dart';
import 'file_upload_service.dart';
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

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin {
  ChatController? _chat;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final List<ChatAttachment> _attachments = [];
  String? _error;
  bool _loading = true;
  String? _lastId;
  int _lastLength = 0;
  late final AnimationController _drawer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final AnimationController _livePulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _historyOpen = false;
  bool _captionCollapsed = false;
  bool _liveMode = false;
  bool _voiceActive = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
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

  Future<void> _pickFiles() async {
    try {
      final files = await pickTextFiles();
      if (files.isEmpty || !mounted) return;
      setState(() => _attachments.addAll(files));
      final skipped = files.length;
      if (skipped == 0) _showMessage('没有可用的文本文件');
    } catch (error) {
      _showMessage('文件选择失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  void _send() {
    final chat = _chat;
    if (chat == null || chat.busy) return;
    final attachments = List<ChatAttachment>.of(_attachments);
    final text = _input.text.trim();
    if (text.isEmpty && attachments.isEmpty) return;
    final injections = <PromptInjection>[
      for (var i = 0; i < attachments.length; i++)
        PromptInjection(
          id: 'attachment-$i',
          name: attachments[i].name,
          position: 'before_latest',
          trust: 'data',
          description: 'uploaded file',
          priority: 500,
          content: '[文件] ${attachments[i].name}\n\n${attachments[i].content}',
        ),
    ];
    final display = [
      if (text.isNotEmpty) text,
      if (attachments.isNotEmpty)
        '📎 ${attachments.map((item) => item.name).join('、')}',
    ].join('\n');
    _input.clear();
    setState(() => _attachments.clear());
    _focus.requestFocus();
    chat.send(display, injections: injections);
  }

  Future<void> _openSettings() async {
    final chat = _chat;
    if (chat == null) return;
    final updated = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          backend: chat.api,
        ),
      ),
    );
    if (!mounted || updated == null) return;
    await chat.initialize();
    if (updated.cacheKey != widget.settings.cacheKey) {
      await widget.onSettingsChanged(updated);
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_voiceActive) {
        _stopVoice();
        return true;
      }
      if (_liveMode) {
        _setLive(false);
        return true;
      }
      if (_historyOpen) {
        _closeHistory();
        return true;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        event is KeyDownEvent &&
        !_focus.hasFocus &&
        !_liveMode &&
        !_voiceActive) {
      _setLive(true);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.space &&
        event is KeyDownEvent &&
        !_focus.hasFocus &&
        !_liveMode &&
        !_voiceActive) {
      _startVoice();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.space &&
        event is KeyUpEvent &&
        _voiceActive) {
      _stopVoice();
      return true;
    }
    return false;
  }

  void _openHistory() {
    if (_historyOpen) return;
    setState(() => _historyOpen = true);
    _drawer.forward();
  }

  Future<void> _closeHistory() async {
    await _drawer.reverse();
    if (mounted) setState(() => _historyOpen = false);
  }

  void _setLive(bool value) {
    if (_liveMode == value) return;
    setState(() => _liveMode = value);
    if (value) {
      _livePulse.repeat();
    } else {
      _livePulse.stop();
    }
  }

  void _startVoice() {
    if (_voiceActive || _liveMode) return;
    setState(() => _voiceActive = true);
    _showMessage('语音输入已开启：X-ASR / Whisper 模型接入中');
  }

  void _stopVoice() {
    if (!_voiceActive) return;
    setState(() => _voiceActive = false);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _drawer.dispose();
    _livePulse.dispose();
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

  String _latestLine() {
    final chat = _chat;
    if (chat == null) return '';
    for (final message in chat.messages.reversed) {
      if (message.isUser) continue;
      final text = message.content
          .replaceAll(RegExp(r'[*_`#>]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isNotEmpty) return text;
    }
    return '大肥鱼正在等你开口。';
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
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.backgroundTop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ListenableBuilder(
              listenable: chat,
              builder: (context, _) => CharacterStage(
                customRivePath: widget.settings.characterRivePath,
                characterMode: widget.settings.characterMode,
                speaking: chat.busy,
                live2dDir: widget.settings.live2dDir,
                live2dModel: widget.settings.live2dModel,
              ),
            ),
          ),
          if (!_historyOpen)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: _StageTopBar(
                  chat: chat,
                  onSettings: _openSettings,
                  onOpenHistory: _openHistory,
                  onEyeTap: () => _showMessage('YOLO 视觉识别即将接入'),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_historyOpen,
              child: _HistoryDrawer(
                animation: _drawer,
                chat: chat,
                scroll: _scroll,
                onClose: _closeHistory,
              ),
            ),
          ),
          if (!_historyOpen)
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: chat,
                      builder: (context, _) => _DialogueCard(
                        text: _latestLine(),
                        collapsed: _captionCollapsed,
                        onToggle: () => setState(
                          () => _captionCollapsed = !_captionCollapsed,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: chat,
                      builder: (context, _) => _Composer(
                        chat: chat,
                        controller: _input,
                        focus: _focus,
                        attachments: _attachments,
                        live: _liveMode,
                        voice: _voiceActive,
                        pulse: _livePulse,
                        onAttach: _pickFiles,
                        onRemoveAttachment: _removeAttachment,
                        onSend: _send,
                        onStop: chat.stop,
                        onEnterLive: () => _setLive(true),
                        onExitLive: () => _setLive(false),
                        onVoiceStart: _startVoice,
                        onVoiceEnd: _stopVoice,
                        onLongPressSend: () => _setLive(true),
                      ),
                    ),
                  ],
                ),
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

class _StageTopBar extends StatelessWidget {
  const _StageTopBar({
    required this.chat,
    required this.onSettings,
    required this.onOpenHistory,
    required this.onEyeTap,
  });

  final ChatController chat;
  final VoidCallback onSettings;
  final VoidCallback onOpenHistory;
  final VoidCallback onEyeTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        if (details.delta.dy > 2.5) onOpenHistory();
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 66,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.glass.withValues(alpha: 0.78),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
              ),
            ),
            child: ListenableBuilder(
              listenable: chat,
              builder: (context, _) => Row(
                children: [
                  IconButton(
                    onPressed: onEyeTap,
                    tooltip: 'YOLO 视觉（即将接入）',
                    icon: const Icon(Icons.visibility_outlined, size: 21),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        if (details.delta.dy > 2.5) onOpenHistory();
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '大肥鱼',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${chat.backendLabel}  ·  下拉查看记忆',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.muted.withValues(alpha: 0.66),
                              fontSize: 8,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onSettings,
                    tooltip: '设置',
                    icon: const Icon(Icons.tune_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryDrawer extends StatelessWidget {
  const _HistoryDrawer({
    required this.animation,
    required this.chat,
    required this.scroll,
    required this.onClose,
  });

  final Animation<double> animation;
  final ChatController chat;
  final ScrollController scroll;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Opacity(
          opacity: t,
          child: Transform.scale(
            alignment: Alignment.topCenter,
            scaleX: 0.93 + 0.07 * t,
            scaleY: 0.86 + 0.14 * t,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xF2101A30), Color(0xFA070D19)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 10, 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      '历史对话',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onClose,
                      tooltip: '关闭',
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(child: _ChatSurface(chat: chat, scroll: scroll)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  if (details.delta.dy < -3) onClose();
                },
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  color: Colors.black.withValues(alpha: 0.18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swipe_up_rounded,
                        size: 16,
                        color: AppColors.muted.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '上滑关闭',
                        style: TextStyle(
                          color: AppColors.muted.withValues(alpha: 0.65),
                          fontSize: 10,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogueCard extends StatelessWidget {
  const _DialogueCard({
    required this.text,
    required this.collapsed,
    required this.onToggle,
  });

  final String text;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      height: collapsed ? 28 : 82,
      child: GlassPanel(
        radius: 16,
        blur: 18,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 26,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Container(
                      width: 3,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '大肥鱼',
                      style: TextStyle(
                        color: AppColors.primary.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 17,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
            if (!collapsed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onPrimaryContainer,
                        fontSize: 12.5,
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
                      '大肥鱼',
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
                  MarkdownMessage(
                    data: body,
                    streaming: message.streaming,
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
    required this.attachments,
    required this.live,
    required this.voice,
    required this.pulse,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onStop,
    required this.onEnterLive,
    required this.onExitLive,
    required this.onVoiceStart,
    required this.onVoiceEnd,
    required this.onLongPressSend,
  });

  final ChatController chat;
  final TextEditingController controller;
  final FocusNode focus;
  final List<ChatAttachment> attachments;
  final bool live;
  final bool voice;
  final AnimationController pulse;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onEnterLive;
  final VoidCallback onExitLive;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  final VoidCallback onLongPressSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AnimatedBuilder(
          animation: pulse,
          builder: (context, _) {
            return Stack(
              children: [
                GlassPanel(
                  radius: 28,
                  blur: 24,
                  padding: const EdgeInsets.fromLTRB(8, 6, 6, 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!live && attachments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < attachments.length; i++)
                                InputChip(
                                  label: Text(
                                    attachments[i].name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onDeleted: () => onRemoveAttachment(i),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          AnimatedRotation(
                            turns: live ? 0.125 : 0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            child: IconButton(
                              onPressed: live ? onExitLive : onAttach,
                              tooltip: live ? '退出 Live' : '添加文件',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_rounded, size: 20),
                            ),
                          ),
                          Expanded(
                            child: live
                                ? _LiveBody(pulse: pulse)
                                : voice
                                    ? _VoiceBody(pulse: pulse)
                                    : GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onLongPressStart: (_) => onVoiceStart(),
                                        onLongPressEnd: (_) => onVoiceEnd(),
                                        child: TextField(
                                          controller: controller,
                                          focusNode: focus,
                                          minLines: 1,
                                          maxLines: 5,
                                          textInputAction: TextInputAction.send,
                                          onSubmitted: (_) => onLongPressSend(),
                                          style: const TextStyle(
                                            color: AppColors.text,
                                            fontSize: 14.5,
                                            height: 1.45,
                                          ),
                                          decoration: const InputDecoration(
                                            hintText: '说点什么…',
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                          ),
                          const SizedBox(width: 4),
                          if (!live)
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: controller,
                              builder: (context, value, _) {
                                final canSend =
                                    (value.text.trim().isNotEmpty ||
                                            attachments.isNotEmpty) &&
                                        !chat.busy;
                                return GestureDetector(
                                  onLongPress: chat.busy ? null : onLongPressSend,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 160),
                                    child: chat.busy
                                        ? IconButton.filled(
                                            key: const ValueKey('stop'),
                                            onPressed: onStop,
                                            tooltip: '停止',
                                            icon: const Icon(
                                              Icons.stop_rounded,
                                              size: 20,
                                            ),
                                          )
                                        : IconButton.filled(
                                            key: const ValueKey('send'),
                                            onPressed: canSend ? onSend : null,
                                            tooltip: '发送 · 长按 Live',
                                            icon: const Icon(
                                              Icons.arrow_upward_rounded,
                                              size: 20,
                                            ),
                                          ),
                                  ),
                                );
                              },
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                'LIVE',
                                style: TextStyle(
                                  color: AppColors.primary.withValues(alpha: 0.85),
                                  fontSize: 9,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (live)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _LiveBeamPainter(progress: pulse.value),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LiveBody extends StatelessWidget {
  const _LiveBody({required this.pulse});

  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 12),
        _Waveform(pulse: pulse, bars: 13, color: AppColors.primary),
        const SizedBox(width: 10),
        Text(
          '正在听…',
          style: TextStyle(
            color: AppColors.primary.withValues(alpha: 0.8),
            fontSize: 11,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _VoiceBody extends StatelessWidget {
  const _VoiceBody({required this.pulse});

  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 12),
        Icon(Icons.mic_rounded, size: 17, color: AppColors.coral),
        const SizedBox(width: 8),
        _Waveform(pulse: pulse, bars: 11, color: AppColors.coral),
        const SizedBox(width: 10),
        Text(
          '松开发送',
          style: TextStyle(
            color: AppColors.coral.withValues(alpha: 0.85),
            fontSize: 10,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.pulse,
    required this.bars,
    required this.color,
  });

  final AnimationController pulse;
  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: bars * 5.0,
      height: 24,
      child: CustomPaint(
        painter: _WaveformPainter(
          progress: pulse.value,
          bars: bars,
          color: color,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.bars,
    required this.color,
  });

  final double progress;
  final int bars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars; i++) {
      final phase = progress * math.pi * 2 + i * 0.75;
      final normalized = 0.25 + (math.sin(phase).abs() * 0.75);
      final h = size.height * (0.18 + normalized * 0.7);
      final x = i * (size.width / bars) + 2;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _LiveBeamPainter extends CustomPainter {
  const _LiveBeamPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.42, size.height * 0.52);
    final right = Offset(size.width - 30, size.height * 0.50);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0),
          AppColors.primary.withValues(alpha: 0.75),
        ],
      ).createShader(Rect.fromPoints(center, right));
    for (final dy in [-9.0, 9.0]) {
      final path = Path()
        ..moveTo(right.dx, right.dy + dy)
        ..quadraticBezierTo(
          size.width * 0.74,
          size.height * 0.5 + dy * 1.7,
          center.dx,
          center.dy,
        );
      canvas.drawPath(path, paint);
    }
    final ripple = (size.width * 0.68) * ((progress * 1.4) % 1.0);
    final fade = (1 - ripple / (size.width * 0.68)).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      ripple,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.16 * fade),
            AppColors.primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: ripple)),
    );
    canvas.drawCircle(
      center,
      ripple,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.primary.withValues(alpha: 0.45 * fade),
    );
  }

  @override
  bool shouldRepaint(covariant _LiveBeamPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
