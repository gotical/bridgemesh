import 'dart:convert';
import 'dart:typed_data';

/// Типы пакетов в меш-сети.
enum MeshMessageType {
  /// Периодический «я живой» пакет для построения таблицы соседей.
  beacon,

  /// Произвольное текстовое сообщение.
  text,

  /// Пакет ретрансляции (промежуточный узел).
  relay,

  /// Подтверждение доставки.
  ack,

  /// Запрос на обнаружение сервиса.
  discovery,

  /// Экстренный сигнал «SOS» (распространяется волной).
  sos,

  /// Управление каналом/группой.
  group,

  /// Визитная карточка узла (имя, nodeId, подпись, история имён).
  contactCard,

  /// Запрос на добавление в контакты.
  contactRequest,

  /// Сообщение в городской (гео) комнате.
  room,

  /// Снимок последних сообщений комнаты — для синхронизации между узлами.
  roomSnapshot,

  /// Координаты узла (для определения комнаты/города).
  geo,

  /// Запрос «кто рядом»: получить список ближайших соседей.
  whoNear,
}

/// Заголовок пакета меш-сети.
class MeshPacket {
  final MeshMessageType type;
  final String from;       // ID отправителя
  final String? to;        // ID получателя (null = broadcast)
  final String id;         // UUID пакета
  final int ttl;           // сколько ещё пересылок
  final int hop;           // сколько пересылок уже сделано
  final String signature;  // HMAC-подпись (для аутентификации)
  final Map<String, dynamic> payload;
  final int timestamp;

  MeshPacket({
    required this.type,
    required this.from,
    this.to,
    required this.id,
    this.ttl = 6,
    this.hop = 0,
    required this.signature,
    required this.payload,
    this.timestamp = 0,
  });

  MeshPacket copyWith({
    String? to,
    int? ttl,
    int? hop,
    Map<String, dynamic>? payload,
  }) {
    return MeshPacket(
      type: type,
      from: from,
      to: to ?? this.to,
      id: id,
      ttl: ttl ?? this.ttl,
      hop: hop ?? this.hop,
      signature: signature,
      payload: payload ?? this.payload,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        't': type.index,
        'f': from,
        if (to != null) 'to': to,
        'i': id,
        'l': ttl,
        'h': hop,
        's': signature,
        'p': payload,
        'ts': timestamp == 0 ? DateTime.now().millisecondsSinceEpoch : timestamp,
      };

  factory MeshPacket.fromJson(Map<String, dynamic> json) {
    return MeshPacket(
      type: MeshMessageType.values[json['t'] as int],
      from: json['f'] as String,
      to: json['to'] as String?,
      id: json['i'] as String,
      ttl: (json['l'] as num?)?.toInt() ?? 6,
      hop: (json['h'] as num?)?.toInt() ?? 0,
      signature: json['s'] as String? ?? '',
      payload: (json['p'] as Map?)?.cast<String, dynamic>() ?? {},
      timestamp: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }

  /// Максимальный размер одного фрагмента (BLE MTU обычно 20-512).
  /// 140 оставляем запас на заголовок адаптируемого уровня.
  static const int fragmentSize = 140;

  /// Сериализация в байты с маркером длины.
  /// Если пакет больше `fragmentSize`, он автоматически разбивается
  /// на фрагменты с общим заголовком сборки. Сборка — на принимающей
  /// стороне через [decode].
  Uint8List encode() {
    final body = utf8.encode(jsonEncode(toJson()));
    if (body.length <= fragmentSize) {
      final out = Uint8List(4 + body.length);
      out[0] = (body.length >> 24) & 0xFF;
      out[1] = (body.length >> 16) & 0xFF;
      out[2] = (body.length >> 8) & 0xFF;
      out[3] = body.length & 0xFF;
      out.setRange(4, 4 + body.length, body);
      return out;
    }
    // Большой пакет: вернём первый фрагмент (остальные будут
    // переданы отдельно через фрагментированный режим).
    return _encodeFragmented(body, 0, _fragmentsCount(body.length));
  }

  static int _fragmentsCount(int len) =>
      (len + fragmentSize - 1) ~/ fragmentSize;

  Uint8List _encodeFragmented(List<int> body, int index, int total) {
    final start = index * fragmentSize;
    final end = (start + fragmentSize) > body.length
        ? body.length
        : start + fragmentSize;
    final chunk = body.sublist(start, end);
    // Заголовок: 1 байт — флаг фрагмента, 1 байт — индекс, 1 байт — всего.
    final out = Uint8List(3 + chunk.length);
    out[0] = 0xFF; // флаг фрагмента
    out[1] = index;
    out[2] = total;
    out.setRange(3, 3 + chunk.length, chunk);
    return out;
  }

  /// Декодирование из массива байт; null при ошибке.
  /// Если пришёл первый фрагмент большого пакета, остальные
  /// можно склеить через [decodeFragmented].
  static MeshPacket? decode(Uint8List bytes) {
    try {
      if (bytes.length < 4) return null;
      // Фрагментированный пакет?
      if (bytes[0] == 0xFF) {
        // Нужна полная сборка — здесь мы её не делаем, возвращаем null
        // (получатель должен использовать [assembleFragments]).
        return null;
      }
      final len =
          (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
      if (len <= 0 || 4 + len > bytes.length) return null;
      final body = utf8.decode(bytes.sublist(4, 4 + len));
      final json = jsonDecode(body) as Map<String, dynamic>;
      return MeshPacket.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Склеивает фрагменты и возвращает итоговый пакет.
  static MeshPacket? assembleFragments(List<Uint8List> fragments) {
    if (fragments.isEmpty) return null;
    final buf = <int>[];
    for (final f in fragments) {
      if (f.length < 3 || f[0] != 0xFF) continue;
      buf.addAll(f.sublist(3));
    }
    return decode(Uint8List.fromList(buf));
  }

  /// Возвращает список фрагментов для отправки.
  List<Uint8List> toFragments() {
    final body = utf8.encode(jsonEncode(toJson()));
    if (body.length <= fragmentSize) return [encode()];
    final total = _fragmentsCount(body.length);
    return List.generate(
      total,
      (i) => _encodeFragmented(body, i, total),
    );
  }

  /// Краткая сводка для отображения в логах/UI.
  String describe() {
    switch (type) {
      case MeshMessageType.text:
        return 'TEXT from ${shortId(from)}: ${payload['text'] ?? ''}';
      case MeshMessageType.beacon:
        return 'BEACON ${shortId(from)}';
      case MeshMessageType.relay:
        return 'RELAY hop=$hop from=${shortId(from)}';
      case MeshMessageType.ack:
        return 'ACK for ${shortId(payload['id']?.toString() ?? '')}';
      case MeshMessageType.discovery:
        return 'DISCOVERY ${payload['name'] ?? ''}';
      case MeshMessageType.sos:
        return 'SOS from ${shortId(from)}: ${payload['text'] ?? ''}';
      case MeshMessageType.group:
        return 'GROUP ${payload['op'] ?? ''}';
      case MeshMessageType.contactCard:
        return 'CARD ${shortId(from)} alias=${payload['alias'] ?? ''}';
      case MeshMessageType.contactRequest:
        return 'CONTACT_REQ ${shortId(from)}';
      case MeshMessageType.room:
        return 'ROOM ${payload['room'] ?? ''} ${shortId(from)}: '
            '${payload['text'] ?? ''}';
      case MeshMessageType.roomSnapshot:
        return 'ROOM_SNAP ${payload['room'] ?? ''} '
            'n=${(payload['msgs'] as List?)?.length ?? 0}';
      case MeshMessageType.geo:
        return 'GEO ${payload['lat']}/${payload['lon']} city='
            '${payload['city'] ?? '?'}';
      case MeshMessageType.whoNear:
        return 'WHO_NEAR from ${shortId(from)}';
    }
  }

  static String shortId(String id) =>
      id.length <= 6 ? id : id.substring(0, 6);
}
