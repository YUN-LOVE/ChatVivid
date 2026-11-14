import 'mcp_server.dart';
import 'prompt_injection.dart';
import 'skill.dart';

enum BackendMode {
  full('full', 'Full · 内嵌 C++'),
  client('client', 'Only client · 远程');

  const BackendMode(this.wireName, this.label);

  final String wireName;
  final String label;

  static BackendMode fromWire(String? value) {
    return BackendMode.values.firstWhere(
      (mode) => mode.wireName == value,
      orElse: () => BackendMode.full,
    );
  }
}

enum AppColorMode {
  classic('classic'),
  system('system'),
  stage('stage');

  const AppColorMode(this.wireName);

  final String wireName;

  static AppColorMode fromWire(String? value) =>
      AppColorMode.values.firstWhere(
        (mode) => mode.wireName == value,
        orElse: () => AppColorMode.classic,
      );
}

enum CharacterMode {
  rive('rive'),
  staticImage('static'),
  altImage('alt'),
  live2d('live2d'),
  live2dExternal('live2dExternal'),
  custom('custom');

  const CharacterMode(this.wireName);

  final String wireName;

  static CharacterMode fromWire(String? value) => CharacterMode.values.firstWhere(
        (mode) => mode.wireName == value,
        orElse: () => CharacterMode.live2d,
      );
}

enum TtsEngine {
  edge('edge', 'Edge TTS'),
  system('system', '系统 TTS');

  const TtsEngine(this.wireName, this.label);

  final String wireName;
  final String label;

  static TtsEngine fromWire(String? value) => TtsEngine.values.firstWhere(
        (engine) => engine.wireName == value,
        orElse: () => TtsEngine.edge,
      );
}

class AppSettings {
  const AppSettings({
    required this.mode,
    required this.clientBaseUrl,
    required this.clientToken,
    required this.provider,
    required this.model,
    required this.fullBaseUrl,
    required this.fullEndpoint,
    required this.apiKey,
    required this.systemPrompt,
    required this.injections,
    required this.skills,
    required this.mcpServers,
    required this.characterRivePath,
    required this.live2dDir,
    required this.live2dModel,
    required this.characterMode,
    required this.colorMode,
    required this.agentEnabled,
    required this.onboardingComplete,
    required this.ttsEngine,
    required this.ttsVoice,
    required this.ttsRate,
    required this.ttsPitchHz,
    required this.ttsVolume,
    required this.ttsAutoSpeak,
    required this.developerMode,
    required this.typewriterSpeed,
    required this.characterScale,
    required this.characterOffsetX,
    required this.characterOffsetY,
    required this.glassStrength,
  });

  factory AppSettings.defaults() {
    return AppSettings(
      mode: BackendMode.full,
      clientBaseUrl: 'http://127.0.0.1:8080',
      clientToken: '',
      provider: 'deepseek',
      model: 'deepseek-flash',
      fullBaseUrl: 'https://api.deepseek.com',
      fullEndpoint: '/responses',
      apiKey: '',
      systemPrompt: '',
      injections: const [],
      skills: const [],
      mcpServers: const [],
      characterRivePath: '',
      live2dDir: '',
      live2dModel: '',
      characterMode: CharacterMode.live2d,
      colorMode: AppColorMode.classic,
      agentEnabled: false,
      onboardingComplete: false,
      ttsEngine: TtsEngine.edge,
      ttsVoice: 'zh-CN-XiaoyiNeural',
      ttsRate: 1.0,
      ttsPitchHz: 0,
      ttsVolume: 1.0,
      ttsAutoSpeak: false,
      developerMode: false,
      typewriterSpeed: 1.0,
      characterScale: 1.0,
      characterOffsetX: 0.0,
      characterOffsetY: 0.0,
      glassStrength: 1.0,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    // v1 stored the retired Edge voices as defaults: zh-CN-XiaomengNeural was
    // removed from the Read Aloud service in 2026-09, and zh-CN-Xiaoxiao was the
    // pre-settings default. Migrate both to the new default (Xiaoyi, a working
    // young-female voice closest to Xiaomeng) unless the value is something
    // else the user explicitly chose.
    final settingsVersion = (json['settings_version'] as num?)?.toInt() ?? 1;
    var storedVoice = (json['tts_voice'] as String?) ?? '';
    if (settingsVersion < 2 &&
        (storedVoice.isEmpty ||
            storedVoice == 'zh-CN-XiaoxiaoNeural' ||
            storedVoice == 'zh-CN-XiaomengNeural')) {
      storedVoice = defaults.ttsVoice;
    }
    return AppSettings(
      mode: BackendMode.fromWire(json['mode'] as String?),
      clientBaseUrl:
          (json['client_base_url'] as String?) ?? defaults.clientBaseUrl,
      clientToken: (json['client_token'] as String?) ?? '',
      provider: (json['provider'] as String?) ?? defaults.provider,
      model: (json['model'] as String?) ?? defaults.model,
      fullBaseUrl:
          (json['full_base_url'] as String?) ?? defaults.fullBaseUrl,
      fullEndpoint:
          (json['full_endpoint'] as String?) ?? defaults.fullEndpoint,
      apiKey: (json['api_key'] as String?) ?? '',
      systemPrompt: (json['system_prompt'] as String?) ?? '',
      injections: (json['injections'] as List?)
              ?.whereType<Map>()
              .map((item) => PromptInjection.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList() ??
          const [],
      skills: (json['skills'] as List?)
              ?.whereType<Map>()
              .map((item) => Skill.fromJson(Map<String, dynamic>.from(item)))
              .toList() ??
          const [],
      mcpServers: (json['mcp_servers'] as List?)
              ?.whereType<Map>()
              .map((item) => McpServer.fromJson(Map<String, dynamic>.from(item)))
              .toList() ??
          const [],
      characterRivePath: (json['character_rive_path'] as String?) ?? '',
      live2dDir: (json['live2d_dir'] as String?) ?? '',
      live2dModel: (json['live2d_model'] as String?) ?? '',
      characterMode: CharacterMode.fromWire(
        json['character_mode'] as String?,
      ),
      colorMode: AppColorMode.fromWire(json['color_mode'] as String?),
      agentEnabled: (json['agent_enabled'] as bool?) ?? false,
      onboardingComplete: (json['onboarding_complete'] as bool?) ?? false,
      ttsEngine: TtsEngine.fromWire(json['tts_engine'] as String?),
      ttsVoice: storedVoice.isEmpty ? defaults.ttsVoice : storedVoice,
      ttsRate: (json['tts_rate'] as num?)?.toDouble() ?? defaults.ttsRate,
      ttsPitchHz:
          (json['tts_pitch_hz'] as num?)?.toInt() ?? defaults.ttsPitchHz,
      ttsVolume:
          (json['tts_volume'] as num?)?.toDouble() ?? defaults.ttsVolume,
      ttsAutoSpeak: (json['tts_auto_speak'] as bool?) ?? false,
      developerMode: (json['developer_mode'] as bool?) ?? false,
      typewriterSpeed: (json['typewriter_speed'] as num?)?.toDouble() ??
          defaults.typewriterSpeed,
      characterScale: (json['character_scale'] as num?)?.toDouble() ??
          defaults.characterScale,
      characterOffsetX: (json['character_offset_x'] as num?)?.toDouble() ??
          defaults.characterOffsetX,
      characterOffsetY: (json['character_offset_y'] as num?)?.toDouble() ??
          defaults.characterOffsetY,
      glassStrength: (json['glass_strength'] as num?)?.toDouble() ??
          defaults.glassStrength,
    );
  }

  final BackendMode mode;
  final String clientBaseUrl;
  final String clientToken;
  final String provider;
  final String model;
  final String fullBaseUrl;
  final String fullEndpoint;
  final String apiKey;
  final String systemPrompt;
  final List<PromptInjection> injections;
  final List<Skill> skills;
  final List<McpServer> mcpServers;
  final String characterRivePath;
  final String live2dDir;
  final String live2dModel;
  final CharacterMode characterMode;
  final AppColorMode colorMode;
  final bool agentEnabled;
  final bool onboardingComplete;
  final TtsEngine ttsEngine;
  final String ttsVoice;
  final double ttsRate;
  final int ttsPitchHz;
  final double ttsVolume;
  final bool ttsAutoSpeak;
  final bool developerMode;
  final double typewriterSpeed;
  final double characterScale;
  final double characterOffsetX;
  final double characterOffsetY;
  /// Global frosted-glass blur multiplier (设置 → 外观 → 毛玻璃强度).
  final double glassStrength;

  Map<String, Object?> toJson() => {
        'mode': mode.wireName,
        'client_base_url': clientBaseUrl,
        'client_token': clientToken,
        'provider': provider,
        'model': model,
        'full_base_url': fullBaseUrl,
        'full_endpoint': fullEndpoint,
        'api_key': apiKey,
        'system_prompt': systemPrompt,
        'injections': injections.map((item) => item.toJson()).toList(),
        'skills': skills.map((item) => item.toJson()).toList(),
        'mcp_servers': mcpServers.map((item) => item.toJson()).toList(),
        'character_rive_path': characterRivePath,
        'live2d_dir': live2dDir,
        'live2d_model': live2dModel,
        'character_mode': characterMode.wireName,
        'color_mode': colorMode.wireName,
        'agent_enabled': agentEnabled,
        'onboarding_complete': onboardingComplete,
        'settings_version': 2,
        'tts_engine': ttsEngine.wireName,
        'tts_voice': ttsVoice,
        'tts_rate': ttsRate,
        'tts_pitch_hz': ttsPitchHz,
        'tts_volume': ttsVolume,
        'tts_auto_speak': ttsAutoSpeak,
        'developer_mode': developerMode,
        'typewriter_speed': typewriterSpeed,
        'character_scale': characterScale,
        'character_offset_x': characterOffsetX,
        'character_offset_y': characterOffsetY,
        'glass_strength': glassStrength,
      };

  AppSettings copyWith({
    BackendMode? mode,
    String? clientBaseUrl,
    String? clientToken,
    String? provider,
    String? model,
    String? fullBaseUrl,
    String? fullEndpoint,
    String? apiKey,
    String? systemPrompt,
    List<PromptInjection>? injections,
    List<Skill>? skills,
    List<McpServer>? mcpServers,
    String? characterRivePath,
    String? live2dDir,
    String? live2dModel,
    CharacterMode? characterMode,
    AppColorMode? colorMode,
    bool? agentEnabled,
    bool? onboardingComplete,
    TtsEngine? ttsEngine,
    String? ttsVoice,
    double? ttsRate,
    int? ttsPitchHz,
    double? ttsVolume,
    bool? ttsAutoSpeak,
    bool? developerMode,
    double? typewriterSpeed,
    double? characterScale,
    double? characterOffsetX,
    double? characterOffsetY,
    double? glassStrength,
  }) {
    return AppSettings(
      mode: mode ?? this.mode,
      clientBaseUrl: clientBaseUrl ?? this.clientBaseUrl,
      clientToken: clientToken ?? this.clientToken,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      fullBaseUrl: fullBaseUrl ?? this.fullBaseUrl,
      fullEndpoint: fullEndpoint ?? this.fullEndpoint,
      apiKey: apiKey ?? this.apiKey,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      injections: injections ?? this.injections,
      skills: skills ?? this.skills,
      mcpServers: mcpServers ?? this.mcpServers,
      characterRivePath: characterRivePath ?? this.characterRivePath,
      live2dDir: live2dDir ?? this.live2dDir,
      live2dModel: live2dModel ?? this.live2dModel,
      characterMode: characterMode ?? this.characterMode,
      colorMode: colorMode ?? this.colorMode,
      agentEnabled: agentEnabled ?? this.agentEnabled,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsPitchHz: ttsPitchHz ?? this.ttsPitchHz,
      ttsVolume: ttsVolume ?? this.ttsVolume,
      ttsAutoSpeak: ttsAutoSpeak ?? this.ttsAutoSpeak,
      developerMode: developerMode ?? this.developerMode,
      typewriterSpeed: typewriterSpeed ?? this.typewriterSpeed,
      characterScale: characterScale ?? this.characterScale,
      characterOffsetX: characterOffsetX ?? this.characterOffsetX,
      characterOffsetY: characterOffsetY ?? this.characterOffsetY,
      glassStrength: glassStrength ?? this.glassStrength,
    );
  }

  String get cacheKey => [
        mode.wireName,
        clientBaseUrl,
        provider,
        model,
        fullBaseUrl,
        fullEndpoint,
        apiKey,
        clientToken,
        systemPrompt,
        injections.map((item) => item.toJson().toString()).join(';'),
        skills.map((item) => item.toJson().toString()).join(';'),
        mcpServers.map((item) => item.toJson().toString()).join(';'),
        characterRivePath,
        live2dDir,
        live2dModel,
        characterMode.wireName,
        agentEnabled,
      ].join('|');
}
