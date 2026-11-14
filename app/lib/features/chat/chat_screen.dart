// ignore_for_file: prefer_const_constructors_in_immutables
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
import '../../theme/haptics.dart';
import '../character/character_stage.dart';
import 'chat_attachment.dart';
import 'markdown_message.dart';
import 'file_upload_service.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'tts_service.dart';

class ChatScreen extends StatefulWidget {
  ChatScreen({
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
    duration: Duration(milliseconds: 460),
  );
  late final AnimationController _livePulse = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 1500),
  );
  bool _historyOpen = false;
  bool _captionCollapsed = false;
  bool _liveMode = false;
  bool _voiceActive = false;
  String? _lastSpokenId;
  bool _editMode = false;
  double _editScale = 1.0;
  Offset _editOffset = Offset.zero;
  double _editStartScale = 1.0;
  Offset _editStartOffset = Offset.zero;
  Offset _editStartFocal = Offset.zero;
  final TtsService _tts = TtsService();
  // Normalized (-1..1) pointer target used to drive the Live2D gaze. The
  // platform view does not get reliable Flutter pointer events on Android, so
  // a transparent Listener above the stage captures touches instead.
  final ValueNotifier<Offset?> _gazeTarget = ValueNotifier<Offset?>(null);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _tts.applySettings(widget.settings);
    _editScale = widget.settings.characterScale;
    _editOffset = Offset(
      widget.settings.characterOffsetX,
      widget.settings.characterOffsetY,
    );
    _tts.speaking.addListener(_onTtsChanged);
    unawaited(_tts.init());
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // TTS settings are UI-only (excluded from cacheKey), so the same
    // ChatScreen state survives a settings change; re-apply them here.
    _tts.applySettings(widget.settings);
    if (!_editMode) {
      _editScale = widget.settings.characterScale;
      _editOffset = Offset(
        widget.settings.characterOffsetX,
        widget.settings.characterOffsetY,
      );
    }
  }

  void _setEditMode(bool value) {
    AppHaptics.selection();
    setState(() {
      _editMode = value;
      if (value) {
        _editStartScale = _editScale;
        _editStartOffset = _editOffset;
      }
    });
  }

  void _onCharacterScaleStart(ScaleStartDetails details) {
    _editStartScale = _editScale;
    _editStartOffset = _editOffset;
    _editStartFocal = details.focalPoint;
  }

  void _onCharacterScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _editScale = (_editStartScale * details.scale).clamp(0.5, 2.5);
      _editOffset = _editStartOffset + (details.focalPoint - _editStartFocal);
    });
  }

  Future<void> _onCharacterScaleEnd(ScaleEndDetails details) async {
    AppHaptics.light();
    await widget.onSettingsChanged(
      widget.settings.copyWith(
        characterScale: _editScale,
        characterOffsetX: _editOffset.dx,
        characterOffsetY: _editOffset.dy,
      ),
    );
  }

  Future<void> _resetCharacterLayout() async {
    setState(() {
      _editScale = 1.0;
      _editOffset = Offset.zero;
    });
    await widget.onSettingsChanged(
      widget.settings.copyWith(
        characterScale: 1.0,
        characterOffsetX: 0.0,
        characterOffsetY: 0.0,
      ),
    );
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

    if (widget.settings.ttsAutoSpeak &&
        !chat.busy &&
        !last.isUser &&
        last.content.trim().isNotEmpty &&
        last.id != _lastSpokenId &&
        !_tts.speaking.value) {
      _lastSpokenId = last.id;
      unawaited(_tts.speak(last.content));
    }

    final distance =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (distance < 240 || last.isUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: Duration(milliseconds: 180),
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
    AppHaptics.selection();
    setState(() => _attachments.removeAt(index));
  }

  void _send() {
    final chat = _chat;
    if (chat == null || chat.busy) return;
    final attachments = List<ChatAttachment>.of(_attachments);
    final text = _input.text.trim();
    if (text.isEmpty && attachments.isEmpty) return;
    AppHaptics.light();
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
    AppHaptics.light();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          backend: chat.api,
          // Live persistence: TTS / layout fields are excluded from cacheKey
          // (they must not recreate the chat) so they need this callback.
          onChanged: (updated) {
            unawaited(widget.onSettingsChanged(updated));
          },
        ),
      ),
    );
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

  Future<void> _closeHistory() async {
    if (!_historyOpen) {
      if (_drawer.value > 0) {
        await _drawer.animateTo(
          0,
          duration: Duration(milliseconds: (80 + 380 * _drawer.value).round()),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    await _settleDrawer(open: false);
  }

  Future<void> _settleDrawer({required bool open}) async {
    final target = open ? 1.0 : 0.0;
    final remaining = (target - _drawer.value).abs();
    if (open) setState(() => _historyOpen = true);
    if (remaining <= 0.001) {
      _drawer.value = target;
    } else {
      await _drawer.animateTo(
        target,
        duration: Duration(milliseconds: (80 + 380 * remaining).round()),
        curve: Curves.easeOutCubic,
      );
    }
    if (!open && mounted) setState(() => _historyOpen = false);
  }

  void _onHistoryDragUpdate(double dy) {
    if (_historyOpen) return;
    _drawer.value = (_drawer.value + dy / 340).clamp(0.0, 1.0);
  }

  void _onHistoryDragEnd() {
    if (_historyOpen) return;
    if (_drawer.value >= 0.22) AppHaptics.selection();
    _settleDrawer(open: _drawer.value >= 0.22);
  }

  void _onHistoryCloseDragUpdate(double dy) {
    if (!_historyOpen) return;
    _drawer.value = (_drawer.value + dy / 340).clamp(0.0, 1.0);
  }

  void _onHistoryCloseDragEnd() {
    if (!_historyOpen) return;
    if (_drawer.value <= 0.72) AppHaptics.selection();
    _settleDrawer(open: _drawer.value > 0.72);
  }

  void _setLive(bool value) {
    if (_liveMode == value) return;
    AppHaptics.medium();
    setState(() => _liveMode = value);
    if (value) {
      _livePulse.repeat();
    } else {
      _livePulse.stop();
    }
  }

  void _startVoice() {
    if (_voiceActive || _liveMode) return;
    AppHaptics.light();
    setState(() => _voiceActive = true);
    _showMessage('语音输入已开启：X-ASR / Whisper 模型接入中');
  }

  void _stopVoice() {
    if (!_voiceActive) return;
    AppHaptics.selection();
    setState(() => _voiceActive = false);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _tts.speaking.removeListener(_onTtsChanged);
    _drawer.dispose();
    _livePulse.dispose();
    _gazeTarget.dispose();
    unawaited(_tts.dispose());
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

  void _onTtsChanged() {
    if (mounted) setState(() {});
  }

  String _latestRaw() {
    final chat = _chat;
    if (chat == null) return '';
    for (final message in chat.messages.reversed) {
      if (message.isUser) continue;
      if (message.content.trim().isNotEmpty) return message.content.trim();
    }
    return '';
  }

  Future<void> _toggleSpeech() async {
    AppHaptics.light();
    if (_tts.speaking.value) {
      await _tts.stop();
    } else {
      await _tts.speak(_latestRaw());
    }
    if (mounted) setState(() {});
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
    final overlayOpen =
        _historyOpen || _editMode || _liveMode || _voiceActive;
    return PopScope(
      canPop: !overlayOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_historyOpen) {
          AppHaptics.selection();
          unawaited(_closeHistory());
        } else if (_editMode) {
          _setEditMode(false);
        } else if (_liveMode) {
          _setLive(false);
        } else if (_voiceActive) {
          _stopVoice();
        }
      },
      child: Scaffold(
      // The stage must not resize when the soft keyboard opens. The composer
      // is lifted manually below using MediaQuery.viewInsets.
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.backgroundTop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ListenableBuilder(
              listenable: chat,
              builder: (context, _) => Transform.translate(
                offset: _editOffset,
                child: Transform.scale(
                  scale: _editScale,
                  alignment: Alignment.bottomCenter,
                  child: CharacterStage(
                    customRivePath: widget.settings.characterRivePath,
                    characterMode: widget.settings.characterMode,
                    speaking: chat.busy || _tts.speaking.value,
                    live2dDir: widget.settings.live2dDir,
                    live2dModel: widget.settings.live2dModel,
                    gazeNotifier: _gazeTarget,
                  ),
                ),
              ),
            ),
          ),
          // Touch overlay for Live2D gaze: sits above the native platform view
          // (which swallows pointer events) but below the top bar, history
          // drawer and composer, so those keep their own gestures.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                Offset? normalize(Offset local) {
                  final size = constraints.biggest;
                  if (size.width <= 0 || size.height <= 0) return null;
                  return Offset(
                    (local.dx / size.width) * 2 - 1,
                    (local.dy / size.height) * 2 - 1,
                  );
                }

                void update(PointerEvent event) {
                  final value = normalize(event.localPosition);
                  if (value != null) _gazeTarget.value = value;
                }

                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: update,
                  onPointerMove: update,
                  onPointerHover: update,
                );
              },
            ),
          ),
          if (_editMode)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _historyOpen,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onScaleStart: _onCharacterScaleStart,
                  onScaleUpdate: _onCharacterScaleUpdate,
                  onScaleEnd: _onCharacterScaleEnd,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                      color: AppColors.primary.withValues(alpha: 0.04),
                    ),
                  ),
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
                  onDragUpdate: _onHistoryDragUpdate,
                  onDragEnd: _onHistoryDragEnd,
                  onEyeTap: () => _showMessage('YOLO 视觉识别即将接入'),
                  editing: _editMode,
                  onToggleEdit: () => _setEditMode(!_editMode),
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
                onCloseDragUpdate: _onHistoryCloseDragUpdate,
                onCloseDragEnd: _onHistoryCloseDragEnd,
              ),
            ),
          ),
          if (!_historyOpen)
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_editMode) ...[
                      _EditModeBar(
                        onReset: _resetCharacterLayout,
                        onDone: () => _setEditMode(false),
                      ),
                      SizedBox(height: 8),
                    ],
                    AnimatedBuilder(
                      animation: chat,
                      builder: (context, _) => _DialogueCard(
                        text: _latestLine(),
                        collapsed: _captionCollapsed,
                        speaking: _tts.speaking.value,
                        typewriterSpeed: widget.settings.typewriterSpeed,
                        onSpeak: _toggleSpeech,
                        onToggle: () => setState(
                          () => _captionCollapsed = !_captionCollapsed,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
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
      ),
    );
  }
}

class _BootstrapScreen extends StatelessWidget {
  _BootstrapScreen({
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundTop, AppColors.surface],
          ),
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/mascot/avatar_circle.png',
                  width: 96,
                  height: 96,
                ),
                SizedBox(height: 20),
                if (loading) ...[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  SizedBox(height: 14),
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
                    style: TextStyle(
                      color: AppColors.coral,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => onRetry(),
                    child: Text('重试'),
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
  _StageTopBar({
    required this.chat,
    required this.onSettings,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onEyeTap,
    required this.editing,
    required this.onToggleEdit,
  });

  final ChatController chat;
  final VoidCallback onSettings;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onEyeTap;
  final bool editing;
  final VoidCallback onToggleEdit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        if (details.delta.dy > 0) onDragUpdate(details.delta.dy);
      },
      onVerticalDragEnd: (_) => onDragEnd(),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 66,
            padding: EdgeInsets.fromLTRB(8, 6, 8, 8),
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
                    icon: Icon(Icons.visibility_outlined, size: 21),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        if (details.delta.dy > 0) onDragUpdate(details.delta.dy);
                      },
                      onVerticalDragEnd: (_) => onDragEnd(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '大肥鱼',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(height: 2),
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
                    onPressed: onToggleEdit,
                    tooltip: editing ? '完成编辑' : '编辑角色位置',
                    icon: Icon(
                      editing ? Icons.check_rounded : Icons.open_with_rounded,
                      size: 20,
                      color: editing ? AppColors.primary : null,
                    ),
                  ),
                  IconButton(
                    onPressed: onSettings,
                    tooltip: '设置',
                    icon: Icon(Icons.tune_rounded, size: 20),
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
  _HistoryDrawer({
    required this.animation,
    required this.chat,
    required this.scroll,
    required this.onClose,
    required this.onCloseDragUpdate,
    required this.onCloseDragEnd,
  });

  final Animation<double> animation;
  final ChatController chat;
  final ScrollController scroll;
  final Future<void> Function() onClose;
  final ValueChanged<double> onCloseDragUpdate;
  final VoidCallback onCloseDragEnd;

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
        decoration: BoxDecoration(
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
                padding: EdgeInsets.fromLTRB(18, 10, 10, 8),
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
                    SizedBox(width: 14),
                    Text(
                      '历史对话',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      onPressed: onClose,
                      tooltip: '关闭',
                      icon: Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(child: _ChatSurface(chat: chat, scroll: scroll)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  if (details.delta.dy < 0) {
                    onCloseDragUpdate(details.delta.dy);
                  }
                },
                onVerticalDragEnd: (_) => onCloseDragEnd(),
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
                      SizedBox(width: 8),
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

class _EditModeBar extends StatelessWidget {
  _EditModeBar({required this.onReset, required this.onDone});

  final Future<void> Function() onReset;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 16,
      blur: 16,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.open_with_rounded,
            size: 16,
            color: AppColors.primary,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '编辑模式 · 拖动移动，双指缩放角色/立绘',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10.5,
              ),
            ),
          ),
          TextButton(
            onPressed: onReset,
            child: Text('重置', style: TextStyle(fontSize: 11)),
          ),
          FilledButton.tonal(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text('完成', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

/// Bottom-of-stage chat output card.
///
/// The reply is revealed with a layered gaussian-blur "ink bleed": instead of
/// popping character by character, the newly arrived text appears through two
/// blurred copies that fade while the sharp layer settles in. The panel uses
/// the premium (HyperOS-like) glass material.
class _DialogueCard extends StatefulWidget {
  _DialogueCard({
    required this.text,
    required this.collapsed,
    required this.speaking,
    required this.typewriterSpeed,
    required this.onSpeak,
    required this.onToggle,
  });

  final String text;
  final bool collapsed;
  final bool speaking;

  /// Reused as the ink-reveal speed multiplier (0.5 = slower bloom).
  final double typewriterSpeed;
  final VoidCallback onSpeak;
  final VoidCallback onToggle;

  @override
  State<_DialogueCard> createState() => _DialogueCardState();
}

class _DialogueCardState extends State<_DialogueCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    value: 1.0,
  );

  @override
  void initState() {
    super.initState();
    _ink.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _DialogueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == oldWidget.text) return;
    if (widget.text.isEmpty) {
      _ink.value = 1.0;
      return;
    }
    final duration = Duration(
      milliseconds: (460 / widget.typewriterSpeed.clamp(0.2, 4.0)).round(),
    );
    _ink.duration = duration;
    // Keep a residual bloom while tokens keep streaming in; the last chunk
    // settles to sharp over the full duration.
    _ink.forward(from: _ink.value > 0.18 ? 0.18 : 0.0);
  }

  @override
  void dispose() {
    _ink.dispose();
    super.dispose();
  }

  TextStyle _textStyle() => TextStyle(
        color: widget.speaking
            ? AppColors.primary
            : AppColors.onPrimaryContainer,
        fontSize: 12.5,
        height: 1.55,
      );

  Widget _blurLayer({
    required String text,
    required double sigma,
    required double opacity,
  }) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: _textStyle(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: GlassPanel(
        radius: 16,
        blur: 18,
        premium: true,
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.collapsed ? 28 : 156),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 28,
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
                    IconButton(
                      onPressed: widget.onSpeak,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints.tightFor(
                        width: 34,
                        height: 26,
                      ),
                      icon: Icon(
                        widget.speaking
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_rounded,
                        size: 17,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: widget.onToggle,
                      child: Icon(
                        widget.collapsed
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 17,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
              if (!widget.collapsed)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Align(
                      alignment: Alignment.topLeft,
                      heightFactor: 1,
                      child: AnimatedBuilder(
                        animation: _ink,
                        builder: (context, _) {
                          final t = Curves.easeOutCubic.transform(_ink.value);
                          final bloom = 1.0 - t;
                          return Stack(
                            alignment: Alignment.topLeft,
                            children: [
                              Text(
                                widget.text,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: _textStyle().copyWith(
                                  color: (_textStyle().color ??
                                          AppColors.onPrimaryContainer)
                                      .withValues(alpha: 0.62 + 0.38 * t),
                                ),
                              ),
                              if (bloom > 0.02) ...[
                                _blurLayer(
                                  text: widget.text,
                                  sigma: 6.5 * bloom + 0.8,
                                  opacity: 0.34 * bloom,
                                ),
                                _blurLayer(
                                  text: widget.text,
                                  sigma: 2.4 * bloom + 0.4,
                                  opacity: 0.5 * bloom,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
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

class _ChatSurface extends StatelessWidget {
  _ChatSurface({required this.chat, required this.scroll});

  final ChatController chat;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: Offset(0, -8),
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
                  return _EmptyChat();
                }
                return ListView.builder(
                  controller: scroll,
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 18),
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
                duration: Duration(milliseconds: 220),
                child: chat.online
                    ? SizedBox.shrink()
                    : _OfflinePill(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  _MessageTile({required this.message});

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
          margin: EdgeInsets.only(bottom: 14, left: 36),
          padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer.withValues(alpha: 0.82),
            borderRadius: BorderRadius.only(
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
            style: TextStyle(
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
      padding: EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surfaceHigh,
            backgroundImage: AssetImage('assets/mascot/avatar_circle.png'),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '大肥鱼',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    SizedBox(width: 8),
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
                SizedBox(height: 5),
                if (body.isEmpty && message.streaming)
                  _ThinkingLine()
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
  _ThinkingLine();

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
        SizedBox(width: 8),
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
  _OfflinePill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.coral.withValues(alpha: 0.26)),
        ),
        child: Text(
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

/// Thumbnail preview for image attachments (stickers/emoji MCP or pasted
/// images): the composer renders the picture instead of a file-name chip.
class _ImageAttachmentChip extends StatelessWidget {
  _ImageAttachmentChip({required this.attachment, required this.onRemove});

  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            attachment.imageBytes!,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              color: AppColors.surfaceHigh,
              child: Icon(
                Icons.broken_image_outlined,
                size: 18,
                color: AppColors.muted,
              ),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundTop,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cancel_rounded,
                size: 18,
                color: AppColors.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyChat extends StatelessWidget {
  _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/mascot/avatar_circle.png', width: 88, height: 88),
          SizedBox(height: 12),
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
  _Composer({
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
    return AnimatedSize(
      duration: Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 0, 0, 2),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AnimatedBuilder(
          animation: pulse,
          builder: (context, _) {
            return Stack(
              children: [
                GlassPanel(
                  radius: 28,
                  blur: 26,
                  premium: true,
                  padding: EdgeInsets.fromLTRB(8, 6, 6, 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!live && attachments.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < attachments.length; i++)
                                if (attachments[i].isImage)
                                  _ImageAttachmentChip(
                                    attachment: attachments[i],
                                    onRemove: () => onRemoveAttachment(i),
                                  )
                                else
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
                            duration: Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            child: IconButton(
                              onPressed: live ? onExitLive : onAttach,
                              tooltip: live ? '退出 Live' : '添加文件',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.add_rounded, size: 20),
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
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: 168,
                                          ),
                                          child: TextField(
                                          controller: controller,
                                          focusNode: focus,
                                          minLines: 1,
                                          maxLines: null,
                                          keyboardType: TextInputType.multiline,
                                          textInputAction: TextInputAction.send,
                                          onSubmitted: (_) => onLongPressSend(),
                                          style: TextStyle(
                                            color: AppColors.text,
                                            fontSize: 14.5,
                                            height: 1.45,
                                          ),
                                          decoration: InputDecoration(
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
                          ),
                          SizedBox(width: 4),
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
                                    duration: Duration(milliseconds: 160),
                                    child: chat.busy
                                        ? IconButton.filled(
                                            key: ValueKey('stop'),
                                            onPressed: onStop,
                                            tooltip: '停止',
                                            icon: Icon(
                                              Icons.stop_rounded,
                                              size: 20,
                                            ),
                                          )
                                        : IconButton.filled(
                                            key: ValueKey('send'),
                                            onPressed: canSend ? onSend : null,
                                            tooltip: '发送 · 长按 Live',
                                            icon: Icon(
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
                              padding: EdgeInsets.only(right: 10),
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
      ),
    );
  }
}

class _LiveBody extends StatelessWidget {
  _LiveBody({required this.pulse});

  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 12),
        _Waveform(pulse: pulse, bars: 13, color: AppColors.primary),
        SizedBox(width: 10),
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
  _VoiceBody({required this.pulse});

  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 12),
        Icon(Icons.mic_rounded, size: 17, color: AppColors.coral),
        SizedBox(width: 8),
        _Waveform(pulse: pulse, bars: 11, color: AppColors.coral),
        SizedBox(width: 10),
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
  _Waveform({
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
  _WaveformPainter({
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
  _LiveBeamPainter({required this.progress});

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
