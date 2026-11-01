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

enum CharacterMode {
  rive('rive'),
  staticImage('static'),
  custom('custom');

  const CharacterMode(this.wireName);

  final String wireName;

  static CharacterMode fromWire(String? value) => CharacterMode.values.firstWhere(
        (mode) => mode.wireName == value,
        orElse: () => CharacterMode.rive,
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
    required this.characterMode,
    required this.agentEnabled,
    required this.onboardingComplete,
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
      characterMode: CharacterMode.rive,
      agentEnabled: false,
      onboardingComplete: false,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
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
      characterMode: CharacterMode.fromWire(
        json['character_mode'] as String?,
      ),
      agentEnabled: (json['agent_enabled'] as bool?) ?? false,
      onboardingComplete: (json['onboarding_complete'] as bool?) ?? false,
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
  final CharacterMode characterMode;
  final bool agentEnabled;
  final bool onboardingComplete;

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
        'character_mode': characterMode.wireName,
        'agent_enabled': agentEnabled,
        'onboarding_complete': onboardingComplete,
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
    CharacterMode? characterMode,
    bool? agentEnabled,
    bool? onboardingComplete,
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
      characterMode: characterMode ?? this.characterMode,
      agentEnabled: agentEnabled ?? this.agentEnabled,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
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
        characterMode.wireName,
        agentEnabled,
      ].join('|');
}
