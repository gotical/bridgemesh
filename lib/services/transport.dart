import 'dart:async';
import 'dart:typed_data';

/// Базовый интерфейс mesh-транспорта.
abstract class MeshTransport {
  String get name;
  bool get isRunning;

  /// Событие «пришёл байтовый пакет от узла с id remoteId».
  /// Всегда выдаёт уже собранные (assembled) пакеты.
  Stream<Telegram> get incoming;

  /// Событие «появился новый сосед» (для UI).
  Stream<NeighborEvent> get neighbors;

  Future<void> start();
  Future<void> stop();

  /// Отправляет байты всем доступным соседям в зоне покрытия.
  Future<void> broadcast(Uint8List data);

  /// Отправляет байты конкретному соседу (если возможно).
  Future<void> sendTo(String remoteId, Uint8List data);
}

class Telegram {
  final String fromId;
  final Uint8List data;
  final int rssi;
  final String transportName;
  const Telegram({
    required this.fromId,
    required this.data,
    required this.rssi,
    required this.transportName,
  });
}

class NeighborEvent {
  final String id;
  final String name;
  final int rssi;
  final bool gone;
  final String addr;
  const NeighborEvent({
    required this.id,
    required this.name,
    required this.rssi,
    required this.gone,
    required this.addr,
  });
}

/// Менеджер сборки фрагментированных mesh-пакетов.
///
/// BLE MTU обычно 20-180 байт. Большое сообщение режется на
/// чанки по 140 байт, каждый чанк передаётся независимо через
/// все доступные транспорты. На принимающей стороне чанки
/// собираются в полный пакет.
///
/// Идентификация по (source_id, packet_id): все фрагменты
/// помечены общим packetId (первые 4 байта полезной нагрузки
/// после заголовка 0xFF index total).
class FragmentAssembler {
  /// source_id (идентификатор соседа) -> packet_id -> фрагменты.
  final Map<String, Map<String, _Pending>> _pending = {};
  final StreamController<Telegram> _out = StreamController.broadcast();

  Stream<Telegram> get output => _out.stream;

  /// Принять фрагмент. Если удалось собрать пакет — публикует
  /// его через [output] как обычный Telegram.
  void ingest(Uint8List data, String fromId, int rssi, String transport) {
    if (data.isEmpty) return;
    // Полный пакет (без флагa 0xFF): отдаём как есть.
    if (data[0] != 0xFF) {
      _out.add(Telegram(
        fromId: fromId,
        data: data,
        rssi: rssi,
        transportName: transport,
      ));
      return;
    }
    if (data.length < 4) return;
    final total = data[2];
    final index = data[1];
    // packetId = первые 4 байта полезной нагрузки после байтов заголовка.
    final pfx = data.sublist(3, data.length < 7 ? data.length : 7);
    final packetId = String.fromCharCodes(pfx);
    final pendings = _pending.putIfAbsent(fromId, () => {});
    final p = pendings.putIfAbsent(
      packetId,
      () => _Pending(total: total),
    );
    if (p.fragments.length < total + 1) {
      p.fragments[index] = data;
      p.receivedAt = DateTime.now().millisecondsSinceEpoch;
    }
    // Готов?
    if (p.fragments.length >= total && p.total == total) {
      final concat = _join(p.fragments, total);
      pendings.remove(packetId);
      _out.add(Telegram(
        fromId: fromId,
        data: concat,
        rssi: rssi,
        transportName: transport,
      ));
    }
  }

  Uint8List _join(Map<int, Uint8List> fragments, int total) {
    final buf = BytesBuilder();
    for (var i = 0; i < total; i++) {
      final f = fragments[i];
      if (f == null) continue;
      buf.add(f.sublist(3));
    }
    final all = buf.toBytes();
    // Превращаем обратно в «полный» формат: 4 байта длины + тело.
    final len = all.length;
    final out = Uint8List(4 + len);
    out[0] = (len >> 24) & 0xFF;
    out[1] = (len >> 16) & 0xFF;
    out[2] = (len >> 8) & 0xFF;
    out[3] = len & 0xFF;
    out.setRange(4, 4 + len, all);
    return out;
  }

  /// Удаляет сборки, которые не были завершены за 30 секунд.
  void prune() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _pending.removeWhere((_, perPacket) {
      perPacket.removeWhere((_, p) =>
          now - p.receivedAt > 30 * 1000);
      return perPacket.isEmpty;
    });
  }
}

class _Pending {
  final int total;
  final Map<int, Uint8List> fragments = {};
  int receivedAt;
  _Pending({required this.total}) : receivedAt = DateTime.now().millisecondsSinceEpoch;
}
