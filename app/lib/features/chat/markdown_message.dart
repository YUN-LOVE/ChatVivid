// ignore_for_file: prefer_const_constructors_in_immutables
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../theme/app_theme.dart';

/// Renders Markdown and, while [streaming] is true, reveals the incoming text
/// with a configurable typewriter effect ([typewriterSpeed], 1.0 = normal).
class MarkdownMessage extends StatefulWidget {
  MarkdownMessage({
    super.key,
    required this.data,
    required this.streaming,
    this.typewriterSpeed = 1.0,
  });

  final String data;
  final bool streaming;
  final double typewriterSpeed;

  @override
  State<MarkdownMessage> createState() => _MarkdownMessageState();
}

class _MarkdownMessageState extends State<MarkdownMessage> {
  Timer? _timer;
  String _visible = '';

  @override
  void initState() {
    super.initState();
    _visible = widget.streaming ? '' : widget.data;
    _syncTimer();
  }

  @override
  void didUpdateWidget(MarkdownMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.streaming) {
      _timer?.cancel();
      _timer = null;
      if (_visible != widget.data) {
        // Final text arrives in one piece: drop the cursor and show it whole.
        setState(() => _visible = widget.data);
      }
      return;
    }
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double get _speed => widget.typewriterSpeed.clamp(0.2, 4.0);

  void _syncTimer() {
    if (!widget.streaming) return;
    if (_timer != null) return;
    // 45 chars/second at 1.0x. A periodic timer (instead of per-char futures)
    // keeps the reveal rate independent of frame drops/large deltas.
    final intervalMs = (1000.0 / (45.0 * _speed)).round().clamp(8, 160);
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        _timer = null;
        return;
      }
      final target = widget.data;
      if (_visible.length >= target.length) {
        if (!widget.streaming) {
          timer.cancel();
          _timer = null;
        }
        return;
      }
      final step = _speed >= 2.0 ? 2 : 1;
      var nextLen = math.min(target.length, _visible.length + step);
      // Never split a surrogate pair (emoji) in half.
      if (nextLen < target.length &&
          nextLen > 0 &&
          _isHighSurrogate(target.codeUnitAt(nextLen - 1))) {
        nextLen = math.min(target.length, nextLen + 1);
      }
      setState(() => _visible = target.substring(0, nextLen));
    });
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  @override
  Widget build(BuildContext context) {
    final data = _visible;
    final streaming = widget.streaming || _visible.length < widget.data.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: data,
          selectable: true,
          softLineBreak: true,
          onTapLink: (text, href, title) {
            if (href == null) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: SelectableText(href),
                duration: Duration(seconds: 4),
              ),
            );
          },
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              height: 1.6,
            ),
            h1: TextStyle(
              color: AppColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
            h2: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
            h3: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            em: TextStyle(
              color: AppColors.text,
              fontStyle: FontStyle.italic,
            ),
            strong: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            a: TextStyle(
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
            code: TextStyle(
              color: Color(0xFFDDE1FF),
              backgroundColor: AppColors.surfaceHigh.withValues(alpha: 0.85),
              fontFamily: 'monospace',
              fontSize: 12.5,
            ),
            codeblockDecoration: BoxDecoration(
              color: AppColors.surfaceHigh.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            codeblockPadding: EdgeInsets.all(14),
            blockquote: TextStyle(
              color: AppColors.muted,
              fontSize: 14,
              height: 1.55,
            ),
            blockquoteDecoration: BoxDecoration(
              color: AppColors.surfaceHigh.withValues(alpha: 0.45),
              border: Border(
                left: BorderSide(color: AppColors.primary, width: 3),
              ),
            ),
            blockquotePadding: EdgeInsets.fromLTRB(12, 8, 12, 8),
            listBullet: TextStyle(
              color: AppColors.primary,
              fontSize: 15,
              height: 1.6,
            ),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            blockSpacing: 10,
          ),
        ),
        if (streaming)
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '▍',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}
