class PromptInjection {
  const PromptInjection({
    required this.id,
    required this.name,
    required this.position,
    required this.content,
    this.mode = 'append',
    this.trust = 'data',
    this.description = '',
    this.depth = 0,
    this.priority = 100,
    this.enabled = true,
  });

  factory PromptInjection.fromJson(Map<String, dynamic> json) {
    return PromptInjection(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '注入').toString(),
      position: (json['position'] ?? 'before_latest').toString(),
      content: (json['content'] ?? '').toString(),
      mode: (json['mode'] ?? 'append').toString(),
      trust: (json['trust'] ?? 'data').toString(),
      description: (json['description'] ?? '').toString(),
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 100,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final String position;
  final String content;
  final String mode;
  final String trust;
  final String description;
  final int depth;
  final int priority;
  final bool enabled;

  static const positions = [
    'before_system',
    'system',
    'after_system',
    'chat_start',
    'after_first_message',
    'before_latest',
    'at_depth',
  ];

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'position': position,
        'content': content,
        'mode': mode,
        'trust': trust,
        'description': description,
        'depth': depth,
        'priority': priority,
        'enabled': enabled,
      };

  /// Shape accepted by chatvvd's `/v1/turns` injections array.
  Map<String, Object?> toApiJson() => {
        'name': name,
        'position': position,
        'content': content,
        'mode': mode,
        'trust': trust,
        'priority': priority,
        'depth': depth,
        'enabled': enabled,
      };

  PromptInjection copyWith({
    String? id,
    String? name,
    String? position,
    String? content,
    String? mode,
    String? trust,
    String? description,
    int? depth,
    int? priority,
    bool? enabled,
  }) {
    return PromptInjection(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      content: content ?? this.content,
      mode: mode ?? this.mode,
      trust: trust ?? this.trust,
      description: description ?? this.description,
      depth: depth ?? this.depth,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
    );
  }
}
