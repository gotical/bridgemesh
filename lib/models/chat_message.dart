import 'package:flutter/material.dart';

/// Статус доставки сообщения.
enum DeliveryStatus { sending, sent, relayed, delivered, failed }

class ChatMessage {
  final String id;
  final String from;
  final String? to;
  final String text;
  final int timestamp;
  final DeliveryStatus status;
  final int hops;
  final bool isMine;

  ChatMessage({
    required this.id,
    required this.from,
    this.to,
    required this.text,
    required this.timestamp,
    required this.status,
    this.hops = 0,
    this.isMine = false,
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
}
