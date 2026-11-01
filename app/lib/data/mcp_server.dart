class McpServer {
  const McpServer({
    required this.id,
    required this.name,
    required this.url,
    required this.token,
    required this.enabled,
  });

  factory McpServer.fromJson(Map<String, dynamic> json) => McpServer(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        token: (json['token'] ?? '').toString(),
        enabled: (json['enabled'] as bool?) ?? true,
      );

  final String id;
  final String name;
  final String url;
  final String token;
  final bool enabled;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'token': token,
        'enabled': enabled,
      };

  McpServer copyWith({
    String? name,
    String? url,
    String? token,
    bool? enabled,
  }) =>
      McpServer(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        token: token ?? this.token,
        enabled: enabled ?? this.enabled,
      );
}
