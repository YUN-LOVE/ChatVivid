class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    required this.enabled,
  });

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        instructions: (json['instructions'] ?? '').toString(),
        enabled: (json['enabled'] as bool?) ?? true,
      );

  final String id;
  final String name;
  final String description;
  final String instructions;
  final bool enabled;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'instructions': instructions,
        'enabled': enabled,
      };

  Skill copyWith({
    String? name,
    String? description,
    String? instructions,
    bool? enabled,
  }) =>
      Skill(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        instructions: instructions ?? this.instructions,
        enabled: enabled ?? this.enabled,
      );
}
