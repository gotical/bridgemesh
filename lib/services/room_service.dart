import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mesh_packet.dart';
import '../models/room.dart';
import 'identity_service.dart';
import 'geo_service.dart';

/// Сервис городских (гео) чатов.
///
/// Хранит локальные ленты сообщений по комнатам, синхронизирует
/// их с соседями, накапливает историю и выдаёт «новости» с учётом
/// времени (TTL). Это позволяет узлам узнавать о событиях в
/// городе, даже если они не были в эфире в момент публикации.
///
/// Стратегия:
///  • Каждое сообщение хранится вечно (до разумного лимита).
///  • При встрече с другим узлом отправляется `roomSnapshot` —
///    последние N сообщений комнат, в которых оба состоят.
///  • Принимающий узел дополняет свою ленту недостающими
///    сообщениями (дедуп по id).
class RoomService extends ChangeNotifierLike {
  static const _kRoomsKey = 'bm_rooms_v1';
  static const int maxMessagesPerRoom = 500;
  static const int snapshotSize = 25;

  final IdentityService identity;
  final GeoService geo;

  final Map<String, Queue<RoomMessage>> _rooms = {};

  RoomService(this.identity, this.geo);

  /// Название комнаты, к которой сейчас привязан узел (по GPS).
  String get currentRoom => geo.currentCityName;

  /// Слаг комнаты (slug), используется как стабильный ключ.
  String get currentRoomSlug => geo.currentCitySlug;

  List<RoomMessage> messagesOf(String room) {
    final q = _rooms[room];
    if (q == null) return const [];
    return q.toList().reversed.toList();
  }

  Iterable<String> get rooms => _rooms.keys;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRoomsKey);
    if (raw == null) return;
    try {
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      for (final entry in map.entries) {
        final list = (entry.value as List).cast<Map>();
        final q = Queue<RoomMessage>();
        for (final m in list) {
          q.add(RoomMessage.fromJson(m.cast<String, dynamic>()));
        }
        _rooms[entry.key] = q;
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    _rooms.forEach((k, v) {
      out[k] = v.map((m) => m.toJson()).toList();
    });
    await prefs.setString(_kRoomsKey, jsonEncode(out));
  }

  /// Добавляет сообщение в локальную ленту (свежее сверху).
  Future<void> _append(RoomMessage msg) async {
    final room = msg.room;
    final q = _rooms.putIfAbsent(room, () => Queue<RoomMessage>());
    if (q.any((m) => m.id == msg.id)) return;
    q.addFirst(msg);
    if (q.length > maxMessagesPerRoom) {
      q.removeLast();
    }
    await _persist();
    notifyListeners();
  }

  /// Публикация сообщения в текущей комнате.
  MeshPacket buildRoomMessagePacket(String text, {String? replyTo}) {
    final id = IdentityService.newPacketId();
    final msg = RoomMessage(
      id: id,
      fromId: identity.nodeId,
      fromAlias: identity.alias,
      room: currentRoom,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      replyTo: replyTo,
    );
    // Сразу в локальную ленту.
    _append(msg);
    return MeshPacket(
      type: MeshMessageType.room,
      from: identity.alias,
      to: null, // broadcast в комнату
      id: id,
      ttl: 8,
      signature: identity.sign('room|$id'),
      payload: msg.toJson(),
    );
  }

  /// Принимает пакет room / roomSnapshot от соседа.
  Future<void> onRoomPacket(MeshPacket pkt) async {
    if (pkt.type == MeshMessageType.room) {
      final m = RoomMessage.fromJson(
        (pkt.payload).cast<String, dynamic>(),
      ).copyWith(hops: pkt.hop);
      await _append(m);
    } else if (pkt.type == MeshMessageType.roomSnapshot) {
      final msgs = (pkt.payload['msgs'] as List?) ?? [];
      for (final raw in msgs.cast<Map>()) {
        try {
          final m = RoomMessage.fromJson(raw.cast<String, dynamic>())
              .copyWith(hops: pkt.hop);
          await _append(m);
        } catch (_) {}
      }
    }
  }

  /// Строит пакет-снимок для отправки соседу.
  MeshPacket buildSnapshotPacket(String room) {
    final list = messagesOf(room).take(snapshotSize).toList();
    return MeshPacket(
      type: MeshMessageType.roomSnapshot,
      from: identity.alias,
      to: null,
      id: IdentityService.newPacketId(),
      ttl: 3,
      signature: identity.sign('snap'),
      payload: {
        'room': room,
        'msgs': list.map((m) => m.toJson()).toList(),
      },
    );
  }

  /// Текущая «версия» хранилища комнат — используется для инкрементальных
  /// обновлений (можно сравнивать с прошлым значением).
  int get versionTag => _rooms.length * 1000 +
      _rooms.values.fold(0, (s, q) => s + q.length);

  /// Возвращает JSON-совместимый снимок всех комнат для бэкапа.
  Map<String, dynamic> snapshotForBackup() {
    return {
      for (final e in _rooms.entries)
        e.key: e.value.toList().map((m) => m.toJson()).toList(),
    };
  }

  /// Восстанавливает комнаты из бэкапа.
  Future<void> restoreFromBackup(Map<String, dynamic> data) async {
    _rooms.clear();
    for (final entry in data.entries) {
      final list = (entry.value as List).cast<Map>();
      final q = Queue<RoomMessage>();
      for (final m in list) {
        q.add(RoomMessage.fromJson(m.cast<String, dynamic>()));
        if (q.length > maxMessagesPerRoom) q.removeFirst();
      }
      _rooms[entry.key] = q;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRoomsKey, jsonEncode(_persistMap()));
    notifyListeners();
  }

  Map<String, dynamic> _persistMap() {
    return {
      for (final e in _rooms.entries) e.key: e.value.toList().map((m) => m.toJson()).toList(),
    };
  }
}

/// Минимальный интерфейс без зависимости от flutter/foundation.
abstract class ChangeNotifierLike {
  final List<void Function()> _listeners = [];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void notifyListeners() {
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {}
    }
  }
}
