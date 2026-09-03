import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mesh_packet.dart';
import 'identity_service.dart';

/// Хранилище пакетов «до востребования» — store-and-forward.
///
/// Когда узел получает пакет, у которого ещё есть TTL и который
/// не для нас — он сохраняется в локальной очереди. Каждые N
/// секунд мы:
///   • Повторно транслируем самые «свежие» и приоритетные пакеты.
///   • Это помогает донести сообщение даже в ситуации, когда
///     встречный узел был вне зоны покрытия, но в сети есть
///     другие узлы с тем же пакетом.
///
/// Также здесь хранятся «дальнобойные» копии для конкретных
/// адресатов: если вы знаете, что ваш друг — в Рыбинске, но он
/// сейчас не в сети, любой встречный узел из Рыбинска сможет
/// доставить ему сообщение.
class MessageStore {
  static const _kStoreKey = 'bm_msg_store_v1';
  static const int maxItems = 2000;

  final IdentityService identity;
  final Map<String, _StoredItem> _items = {};
  bool _loaded = false;

  MessageStore(this.identity);

  Iterable<_StoredItem> get items => _items.values;

  int get pendingForOthers => _items.values
      .where((i) => !i.delivered && i.pkt.to != null)
      .length;

  int get pendingBroadcast => _items.values
      .where((i) => !i.delivered && i.pkt.to == null)
      .length;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStoreKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map>();
        for (final m in list) {
          final s = _StoredItem.fromJson(m.cast<String, dynamic>());
          if ((DateTime.now().millisecondsSinceEpoch - s.savedAt) >
              1000 * 60 * 60 * 24 * 7) {
            continue; // не старше 7 дней
          }
          _items[s.pkt.id] = s;
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> put(MeshPacket pkt) async {
    if (_items.containsKey(pkt.id)) return;
    _items[pkt.id] = _StoredItem(
      pkt: pkt,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      attempts: 0,
      delivered: false,
      priority: _priority(pkt),
    );
    if (_items.length > maxItems) {
      // Удаляем самые старые/менее приоритетные.
      final list = _items.values.toList()
        ..sort((a, b) =>
            b.priority.compareTo(a.priority) == 0
                ? a.savedAt.compareTo(b.savedAt)
                : b.priority.compareTo(a.priority));
      while (list.length > maxItems) {
        final last = list.removeLast();
        _items.remove(last.pkt.id);
      }
    }
    await _persist();
  }

  Future<void> markDelivered(String packetId) async {
    final i = _items[packetId];
    if (i == null) return;
    i.delivered = true;
    // Через 30 минут полностью удалим, чтобы не разрастаться.
    Future.delayed(const Duration(minutes: 30), () {
      _items.remove(packetId);
    });
    await _persist();
  }

  Future<void> markAttempt(String packetId) async {
    final i = _items[packetId];
    if (i == null) return;
    i.attempts++;
    await _persist();
  }

  /// Выбирает до `limit` пакетов для повторной трансляции.
  List<MeshPacket> pickForRebroadcast({int limit = 10}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = _items.values
        .where((i) =>
            !i.delivered &&
            now - i.savedAt < 1000 * 60 * 60 * 24 && // 24 ч
            now - i.lastTried > 30 * 1000) // не чаще раза в 30 сек
        .toList()
      ..sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        return a.savedAt.compareTo(b.savedAt);
      });
    return list.take(limit).map((i) {
      i.lastTried = now;
      return i.pkt;
    }).toList();
  }

  int _priority(MeshPacket pkt) {
    switch (pkt.type) {
      case MeshMessageType.sos:
        return 100;
      case MeshMessageType.text:
        // Адресные — приоритетнее, чем broadcast.
        return pkt.to != null ? 80 : 60;
      case MeshMessageType.room:
        return 50;
      case MeshMessageType.roomSnapshot:
        return 40;
      case MeshMessageType.contactRequest:
        return 30;
      case MeshMessageType.contactCard:
        return 20;
      default:
        return 10;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _items.values
        .where((i) => !i.delivered)
        .map((i) => i.toJson())
        .toList();
    await prefs.setString(_kStoreKey, jsonEncode(list));
  }
}

class _StoredItem {
  final MeshPacket pkt;
  final int savedAt;
  int attempts;
  bool delivered;
  int lastTried;
  final int priority;

  _StoredItem({
    required this.pkt,
    required this.savedAt,
    required this.attempts,
    required this.delivered,
    required this.priority,
    this.lastTried = 0,
  });

  Map<String, dynamic> toJson() => {
        'p': pkt.toJson(),
        's': savedAt,
        'a': attempts,
        'd': delivered,
        't': lastTried,
      };

  factory _StoredItem.fromJson(Map<String, dynamic> json) {
    return _StoredItem(
      pkt: MeshPacket.fromJson(json['p'] as Map<String, dynamic>),
      savedAt: (json['s'] as num).toInt(),
      attempts: (json['a'] as num?)?.toInt() ?? 0,
      delivered: json['d'] as bool? ?? false,
      priority: 0,
      lastTried: (json['t'] as num?)?.toInt() ?? 0,
    );
  }
}
