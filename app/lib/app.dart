import 'package:flutter/material.dart';

import 'features/chat/chat_screen.dart';
import 'theme/app_theme.dart';

class ChatvvApp extends StatelessWidget {
  const ChatvvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'chatvv',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const ChatScreen(),
    );
  }
}
