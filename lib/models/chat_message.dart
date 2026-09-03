import 'package:flutter/material.dart';

/// Статус доставки сообщения.
enum DeliveryStatus { sending, sent, relayed, delivered, failed }

/// Личное сообщение между двумя узлами mesh.
///
/// Сообщение привязано к диалогу (peer — уникальный собеседник),
/// и к комнате (если сообщение отправлено в геочату).
class ChatMessage {
  final String id;
  final String from;
  final String? to;
  final String text;
  final int timestamp;
  final DeliveryStatus status;
  final int hops;
  final bool isMine;

  /// Собеседник (peer) — для личных сообщений это узел с другой стороны;
  /// для групповых (комнатных) — null (см. поле room).
  final String? peerId;

  /// ID комнаты (если сообщение из группового чата).
  final String? roomId;

  ChatMessage({
    required this.id,
    required this.from,
    this.to,
    required this.text,
    required this.timestamp,
    required this.status,
    this.hops = 0,
    this.isMine = false,
    this.peerId,
    this.roomId,
  });

  ChatMessage copyWith({
    DeliveryStatus? status,
    int? hops,
    bool? isMine,
  }) {
    return ChatMessage(
      id: id,
      from: from,
      to: to,
      text: text,
      timestamp: timestamp,
      status: status ?? this.status,
      hops: hops ?? this.hops,
      isMine: isMine ?? this.isMine,
      peerId: peerId,
      roomId: roomId,
    );
  }

  IconData statusIcon() {
    switch (status) {
      case DeliveryStatus.sending:
        return Icons.schedule;
      case DeliveryStatus.sent:
        return Icons.check;
      case DeliveryStatus.relayed:
        return Icons.share;
      case DeliveryStatus.delivered:
        return Icons.done_all;
      case DeliveryStatus.failed:
        return Icons.error_outline;
    }
  }

  Color statusColor(ColorScheme cs) {
    switch (status) {
      case DeliveryStatus.sending:
        return cs.onSurface.withValues(alpha: 0.4);
      case DeliveryStatus.sent:
        return cs.onSurface.withValues(alpha: 0.6);
      case DeliveryStatus.relayed:
        return cs.primary.withValues(alpha: 0.7);
      case DeliveryStatus.delivered:
        return cs.primary;
      case DeliveryStatus.failed:
        return cs.error;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'text': text,
        'ts': timestamp,
        'status': status.index,
        'hops': hops,
        'mine': isMine,
        'peer': peerId,
        'room': roomId,
      };

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        from: j['from'] as String,
        to: j['to'] as String?,
        text: j['text'] as String,
        timestamp: (j['ts'] as num).toInt(),
        status: DeliveryStatus.values[(j['status'] as num?)?.toInt() ?? 3],
        hops: (j['hops'] as num?)?.toInt() ?? 0,
        isMine: j['mine'] as bool? ?? false,
        peerId: j['peer'] as String?,
        roomId: j['room'] as String?,
      );
}

/// Запись в списке диалогов (отдельная «комната» общения).
class Conversation {
  final String peerId;
  String peerName;
  String? phoneBookName;
  String? phone;
  ChatMessage? lastMessage;
  int unread;
  int lastSeen;

  Conversation({
    required this.peerId,
    required this.peerName,
    this.phoneBookName,
    this.phone,
    this.lastMessage,
    this.unread = 0,
    required this.lastSeen,
  });

  /// Имя, которое видит пользователь: имя из записной книжки
  /// важнее mesh-имени.
  String get displayName =>
      (phoneBookName != null && phoneBookName!.isNotEmpty)
          ? phoneBookName!
          : peerName;

  Map<String, dynamic> toJson() => {
        'peer': peerId,
        'name': peerName,
        'pb': phoneBookName,
        'ph': phone,
        'unread': unread,
        'ls': lastSeen,
      };

  static Conversation fromJson(Map<String, dynamic> j) => Conversation(
        peerId: j['peer'] as String,
        peerName: j['name'] as String,
        phoneBookName: j['pb'] as String?,
        phone: j['ph'] as String?,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
        lastSeen: (j['ls'] as num).toInt(),
      );
}
