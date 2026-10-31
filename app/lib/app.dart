import 'package:flutter/material.dart';

import 'app/startup_gate.dart';
import 'theme/app_theme.dart';

class ChatvvApp extends StatelessWidget {
  const ChatvvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatVivid',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const StartupGate(),
    );
  }
}
