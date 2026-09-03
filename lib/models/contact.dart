/// Запись контакта — узел mesh-сети, который пользователь явно
/// добавил в свой список контактов.
class Contact {
  final String nodeId;
  String alias;
  final List<AliasHistoryEntry> aliasHistory;
  int addedAt;
  int lastSeen;
  bool mutual;
  String? note;
  String? group;
  String? phone; // последние 7 цифр, если собеседник их указал
  String? phoneBookName; // имя из записной книжки текущего устройства
  bool online;

  Contact({
    required this.nodeId,
    required this.alias,
    List<AliasHistoryEntry>? aliasHistory,
    required this.addedAt,
    required this.lastSeen,
    this.mutual = false,
    this.note,
    this.group,
    this.phone,
    this.phoneBookName,
    this.online = false,
  }) : aliasHistory = aliasHistory ?? [];

  /// Имя, которое видит пользователь: либо имя из записной книжки,
  /// либо alias из mesh.
  String get displayName =>
      (phoneBookName != null && phoneBookName!.isNotEmpty)
          ? phoneBookName!
          : alias;

  /// Короткая метка узла.
  String get shortId {
    final s = nodeId.toUpperCase();
    if (s.length < 8) return s;
    return '${s.substring(0, 4)}-${s.substring(4, 8)}';
  }

  bool get isStale {
    final age = DateTime.now().millisecondsSinceEpoch - lastSeen;
    return age > 1000 * 60 * 60 * 24 * 14;
  }

  Contact copyWith({
    String? alias,
    List<AliasHistoryEntry>? aliasHistory,
    int? lastSeen,
    bool? mutual,
    String? note,
    String? group,
    String? phone,
    String? phoneBookName,
    bool? online,
  }) {
    return Contact(
      nodeId: nodeId,
      alias: alias ?? this.alias,
      aliasHistory: aliasHistory ?? this.aliasHistory,
      addedAt: addedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      mutual: mutual ?? this.mutual,
      note: note ?? this.note,
      group: group ?? this.group,
      phone: phone ?? this.phone,
      phoneBookName: phoneBookName ?? this.phoneBookName,
      online: online ?? this.online,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': nodeId,
        'a': alias,
        'h': aliasHistory.map((e) => e.toJson()).toList(),
        'aa': addedAt,
        'ls': lastSeen,
        'm': mutual,
        'n': note,
        'g': group,
        'ph': phone,
        'pb': phoneBookName,
      };

  factory Contact.fromJson(Map<String, dynamic> json) {
    final hist = ((json['h'] as List?) ?? [])
        .cast<Map>()
        .map((m) => AliasHistoryEntry.fromJson(m.cast<String, dynamic>()))
        .toList();
    return Contact(
      nodeId: json['id'] as String,
      alias: json['a'] as String,
      aliasHistory: hist,
      addedAt: (json['aa'] as num?)?.toInt() ?? 0,
      lastSeen: (json['ls'] as num?)?.toInt() ?? 0,
      mutual: json['m'] as bool? ?? false,
      note: json['n'] as String?,
      group: json['g'] as String?,
      phone: json['ph'] as String?,
      phoneBookName: json['pb'] as String?,
    );
  }
}

class AliasHistoryEntry {
  final String alias;
  final int since;
  AliasHistoryEntry({required this.alias, required this.since});

  factory AliasHistoryEntry.fromJson(Map<String, dynamic> json) {
    return AliasHistoryEntry(
      alias: json['a'] as String,
      since: (json['s'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {'a': alias, 's': since};
}
