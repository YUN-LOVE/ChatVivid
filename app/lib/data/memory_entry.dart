class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.lastUsedAt,
    required this.useCount,
    required this.importance,
    required this.durability,
    required this.status,
  });

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    return MemoryEntry(
      id: (json['id'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: _date(json['created_at']),
      lastUsedAt: _date(json['last_used_at']),
      useCount: (json['use_count'] as num?)?.toInt() ?? 0,
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      durability: (json['durability'] as num?)?.toInt() ?? 3,
      status: (json['status'] ?? 'active').toString(),
    );
  }

  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final int useCount;
  final double importance;
  final int durability;
  final String status;

  static DateTime _date(Object? value) {
    if (value is num && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class MemoryArchiveResult {
  const MemoryArchiveResult({
    required this.archivedMessages,
    required this.cutoffSeq,
    this.memory,
  });

  factory MemoryArchiveResult.fromJson(Map<String, dynamic> json) {
    final raw = json['memory'];
    return MemoryArchiveResult(
      archivedMessages: (json['archived_messages'] as num?)?.toInt() ?? 0,
      cutoffSeq: (json['cutoff_seq'] as num?)?.toInt() ?? 0,
      memory: raw is Map
          ? MemoryEntry.fromJson(Map<String, dynamic>.from(raw))
          : null,
    );
  }

  final int archivedMessages;
  final int cutoffSeq;
  final MemoryEntry? memory;
}
