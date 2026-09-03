/// Городской (гео) чат. Каждый узел автоматически подписан на
/// комнату с названием ближайшего города по GPS.
///
/// Сообщения в комнате — это обычные mesh-пакеты типа `room`,
/// которые сохраняются и накапливаются у каждого участника.
/// Когда узлы встречаются, они обмениваются «снимками» комнат и
/// дополняют друг друга. Это даёт эффект «новостной ленты города»,
/// даже если участники не знакомы лично.
///
/// `fingerprint` — это короткий хэш сообщения, чтобы дедуплицировать.
class RoomMessage {
  final String id;
  final String fromId;
  final String fromAlias;
  final String room;
  final String text;
  final int timestamp;
  final int hops;
  final String? replyTo;

  RoomMessage({
    required this.id,
    required this.fromId,
    required this.fromAlias,
    required this.room,
    required this.text,
    required this.timestamp,
    this.hops = 0,
    this.replyTo,
  });

  RoomMessage copyWith({int? hops}) => RoomMessage(
        id: id,
        fromId: fromId,
        fromAlias: fromAlias,
        room: room,
        text: text,
        timestamp: timestamp,
        hops: hops ?? this.hops,
        replyTo: replyTo,
      );

  Map<String, dynamic> toJson() => {
        'i': id,
        'f': fromId,
        'a': fromAlias,
        'r': room,
        't': text,
        'ts': timestamp,
        'h': hops,
        if (replyTo != null) 'rt': replyTo,
      };

  factory RoomMessage.fromJson(Map<String, dynamic> json) {
    return RoomMessage(
      id: json['i'] as String,
      fromId: json['f'] as String,
      fromAlias: json['a'] as String? ?? '...',
      room: json['r'] as String,
      text: json['t'] as String,
      timestamp: (json['ts'] as num).toInt(),
      hops: (json['h'] as num?)?.toInt() ?? 0,
      replyTo: json['rt'] as String?,
    );
  }
}

/// Город (комната), определяемая по координатам пользователя.
/// Используется грубая кластеризация: широта/долгота округляются
/// до ~3 км, и в этих границах выбирается «эталонное» название
/// города, разделяемое всеми узлами.
class CityRoom {
  final String name;
  final String slug;        // 'rybinsk', 'moscow' — стабильный ключ
  final int lastActivity;
  final int memberEstimate; // сколько узлов «вроде бы здесь» (по наблюдениям)

  CityRoom({
    required this.name,
    required this.slug,
    required this.lastActivity,
    required this.memberEstimate,
  });
}
