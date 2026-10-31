import 'dart:io';

import 'prompt_injection.dart';

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
    required this.onboardingComplete,
  });

  factory AppSettings.defaults() {
    return AppSettings(
      mode: Platform.isAndroid ? BackendMode.full : BackendMode.client,
      clientBaseUrl: 'http://127.0.0.1:8080',
      clientToken: '',
      provider: 'deepseek',
      model: 'deepseek-flash',
      fullBaseUrl: 'https://api.deepseek.com',
      fullEndpoint: '/responses',
      apiKey: '',
      systemPrompt: '',
      injections: const [],
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
      ].join('|');
}
