import 'package:flutter/material.dart';

import 'app/startup_gate.dart';
import 'data/app_settings.dart';
import 'theme/app_theme.dart';

class ChatvvApp extends StatelessWidget {
  const ChatvvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appThemeController,
      builder: (context, _) {
        ColorScheme? scheme;
        switch (appThemeController.mode) {
          case AppColorMode.classic:
            scheme = null;
          case AppColorMode.system:
            scheme = appThemeController.systemScheme;
          case AppColorMode.stage:
            scheme = appThemeController.stageScheme;
        }
        return MaterialApp(
          title: 'ChatVivid',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(scheme: scheme),
          darkTheme: AppTheme.dark(scheme: scheme),
          themeMode: ThemeMode.dark,
          home: StartupGate(),
        );
      },
    );
  }
}
