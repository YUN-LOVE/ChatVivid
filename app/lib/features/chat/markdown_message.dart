// ignore_for_file: prefer_const_constructors_in_immutables
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../theme/app_theme.dart';

class MarkdownMessage extends StatelessWidget {
  MarkdownMessage({
    super.key,
    required this.data,
    required this.streaming,
  });

  final String data;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
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
