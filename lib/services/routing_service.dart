import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/mesh_packet.dart';
import '../models/chat_message.dart';
import '../models/neighbor.dart';
import 'identity_service.dart';
import 'transport.dart';
import 'transport_bluetooth.dart';
import 'transport_wifi_direct.dart';
import 'contact_service.dart';
import 'room_service.dart';
import 'geo_service.dart';
import 'message_store.dart';
import 'secure_chat.dart';
import 'dialogs_service.dart';
import 'local_notify.dart';

/// Сервис маршрутизации и ретрансляции.
///
/// Каждый узел:
///  • Периодически отправляет beacon + contactCard + geo + roomSnapshot.
///  • Принимает пакеты от соседей, фильтрует дубли, доставляет локально.
///  • Если TTL > 0 и доставка ещё не финальная — ретранслирует.
///  • Защита от петель — дедуп по packet.id.
class RoutingService extends ChangeNotifier {
  RoutingService({
    required this.identity,
    required this.contacts,
    required this.rooms,
    required this.geo,
    required this.store,
    required this.dialogs,
  });

  final IdentityService identity;
  final ContactService contacts;
  final RoomService rooms;
  final GeoService geo;
  final MessageStore store;
  final DialogsService dialogs;

  BluetoothTransport? _bt;
  WifiDirectTransport? _wifi;

  final List<Neighbor> _neighbors = [];
  final Set<String> _seen = {};
  final StreamController<Neighbor> _neighborsCtrl =
      StreamController.broadcast();

  StreamSubscription? _btSub;
  StreamSubscription? _wifiSub;
  StreamSubscription? _btNbrSub;
  StreamSubscription? _wifiNbrSub;

  Timer? _beaconTimer;
  Timer? _pruneTimer;
  Timer? _roomSyncTimer;
  Timer? _geoTimer;
  int _seenTruncateCounter = 0;

  bool _running = false;
  bool get isRunning => _running;

  List<Neighbor> get neighbors => List.unmodifiable(_neighbors);
  Stream<Neighbor> get onNeighbor => _neighborsCtrl.stream;

  void attachBluetooth(BluetoothTransport bt) => _bt = bt;
  void attachWifi(WifiDirectTransport w) => _wifi = w;

  void start() async {
    if (_running) return;
    _running = true;
    await identity.load();
    await contacts.load();
    await rooms.load();
    await store.load();
    await geo.load();
    await geo.start();

    _bt?.start();
    _wifi?.start();

    _btSub = _bt?.incoming.listen((t) => _onIncoming(t));
    _wifiSub = _wifi?.incoming.listen((t) => _onIncoming(t));
    _btNbrSub = _bt?.neighbors.listen(_onNeighborEvent);
    _wifiNbrSub = _wifi?.neighbors.listen(_onNeighborEvent);

    _beaconTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _broadcastBeacon();
    });
    _pruneTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pruneStale();
    });
    // Каждые 60 секунд публикуем свою визитку.
    Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_running) return;
      _sendRaw(contacts.buildContactCardPacket());
    });
    // Каждые 90 секунд публикуем geo-координаты и снимок комнаты.
    _geoTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (!_running) return;
      _publishGeo();
    });
    // Store-and-forward: повторная трансляция важных пакетов.
    Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_running) return;
      _rebroadcastStored();
    });
    _roomSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_running) return;
      _publishRoomSnapshots();
    });

    // При каждом старте сразу публикуем визитку.
    _sendRaw(contacts.buildContactCardPacket());
    _publishGeo();
    notifyListeners();
  }

  void stop() {
    _running = false;
    _beaconTimer?.cancel();
    _pruneTimer?.cancel();
    _geoTimer?.cancel();
    _roomSyncTimer?.cancel();
    _btSub?.cancel();
    _wifiSub?.cancel();
    _btNbrSub?.cancel();
    _wifiNbrSub?.cancel();
    geo.stop();
    _bt?.stop();
    _wifi?.stop();
    _neighborsCtrl.close();
    notifyListeners();
  }

  Future<void> sendText(String text, {String? to}) async {
    final id = IdentityService.newPacketId();
    // Личные сообщения шифруем (E2E). Посредники НИКОГДА не видят
    // открытый текст: они получают только base64-блоб `enc:...` и
    // пересылают его дальше по цепочке. Расшифровать может только
    // отправитель и адресат (общий ключ из SHA-256 от alias1:alias2).
    final isPrivate = to != null && to.isNotEmpty;
    final wireText = isPrivate
        ? SecureChat.encrypt(text, identity.alias, to, id)
        : text;
    final pkt = MeshPacket(
      type: MeshMessageType.text,
      from: identity.alias,
      to: to,
      id: id,
      ttl: 8,
      signature: identity.sign('$id|$text'),
      payload: {
        'text': wireText,
        'enc': isPrivate,
        // 'clear' — true только для публичных broadcast-сообщений.
        // Для личных — false: посредник не должен видеть текст.
        'clear': !isPrivate,
      },
    );
    if (isPrivate) {
      final msg = ChatMessage(
        id: id,
        from: identity.alias,
        to: to,
        peerId: to,
        text: text,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: DeliveryStatus.sending,
        hops: 0,
        isMine: true,
      );
      await dialogs.add(msg);
      await _sendRaw(pkt);
      await _updateMessageStatus(id, DeliveryStatus.sent);
      notifyListeners();
    } else {
      // Broadcast отправляется без личного диалога (используется
      // sendBroadcast() ниже).
      await _sendRaw(pkt);
    }
  }

  /// Публичное объявление (видят все в mesh).
  Future<void> sendBroadcast(String text) async {
    if (text.trim().isEmpty) return;
    final id = IdentityService.newPacketId();
    final pkt = MeshPacket(
      type: MeshMessageType.text,
      from: identity.alias,
      id: id,
      ttl: 6,
      signature: identity.sign('$id|$text'),
      // Broadcast — публичный текст, любой посредник видит.
      payload: {'text': text, 'enc': false, 'clear': true},
    );
    await _sendRaw(pkt);
    LocalNotify.system(
      id: id.hashCode & 0x7fffffff,
      title: 'Объявление отправлено',
      body: 'Все увидят: «$text»',
    );
  }

  Future<void> sendSos(String text) async {
    final id = IdentityService.newPacketId();
    final pos = geo.position;
    final payload = <String, dynamic>{
      'text': text,
      if (pos != null) ...{
        'lat': pos.latitude,
        'lon': pos.longitude,
        'acc': pos.accuracy,
        'ts': pos.timestamp.millisecondsSinceEpoch,
      },
    };
    final pkt = MeshPacket(
      type: MeshMessageType.sos,
      from: identity.alias,
      id: id,
      ttl: 12,
      signature: identity.sign('$id|SOS'),
      payload: payload,
    );
    await _sendRaw(pkt);
    LocalNotify.alert(
      id: id.hashCode & 0x7fffffff,
      title: '🚨 SOS отправлено',
      body: 'Сеть узнает, что вам нужна помощь',
    );
  }

  /// Публикация сообщения в городском или общем чате.
  ///
  /// [slug] — slug комнаты (по умолчанию текущий город).
  /// Для общего чата передавайте `RoomService.globalSlug`.
  Future<void> sendRoomMessage(String text, {String? slug}) async {
    if (text.trim().isEmpty) return;
    final pkt = rooms.buildRoomMessagePacket(
      text.trim(),
      slug: slug,
    );
    await _sendRaw(pkt);
  }

  Future<void> sendContactCard() async {
    await _sendRaw(contacts.buildContactCardPacket());
  }

  Future<void> sendContactRequest() async {
    final pkt = await contacts.buildContactRequest();
    await _sendRaw(pkt);
  }

  void _broadcastBeacon() {
    if (!_running) return;
    final pkt = MeshPacket(
      type: MeshMessageType.beacon,
      from: identity.alias,
      id: IdentityService.newPacketId(),
      ttl: 1,
      signature: identity.sign('beacon'),
      payload: {'group': identity.groupId, 'r': true},
    );
    _sendRaw(pkt);
  }

  /// Store-and-forward — повторная трансляция сохранённых пакетов.
  /// Это критически важно для надёжности: один узел мог пропустить
  /// сообщение, но другой его увидит при следующей встрече.
  void _rebroadcastStored() {
    final picks = store.pickForRebroadcast(limit: 8);
    for (final p in picks) {
      store.markAttempt(p.id);
      _sendRaw(p);
    }
  }

  void _publishGeo() {
    final pos = geo.position;
    if (pos == null) return;
    final pkt = MeshPacket(
      type: MeshMessageType.geo,
      from: identity.alias,
      id: IdentityService.newPacketId(),
      ttl: 4,
      signature: identity.sign('geo'),
      payload: {
        'id': identity.nodeId,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'city': geo.currentCityName,
        'slug': geo.currentCitySlug,
        'ts': DateTime.now().millisecondsSinceEpoch,
      },
    );
    _sendRaw(pkt);
  }

  void _publishRoomSnapshots() {
    final room = rooms.currentRoom;
    if (room.isEmpty || room == 'Не определён') return;
    _sendRaw(rooms.buildSnapshotPacket(room));
  }

  Future<void> _sendRaw(MeshPacket pkt) async {
    final fragments = pkt.toFragments();
    for (final f in fragments) {
      await _bt?.broadcast(f);
      await _wifi?.broadcast(f);
    }
  }

  Future<void> _onIncoming(Telegram t) async {
    final pkt = MeshPacket.decode(t.data);
    if (pkt == null) return;
    if (_seen.contains(pkt.id)) return;
    _seen.add(pkt.id);
    _seenTruncateCounter++;
    if (_seenTruncateCounter > 200) {
      // Периодическая очистка.
      final list = _seen.toList();
      _seen.clear();
      _seen.addAll(list.sublist(list.length ~/ 2));
      _seenTruncateCounter = 0;
    }

    // Сохраняем в store-and-forward только «свежие» пакеты
    // (TTL > 0, чтобы была возможность передать дальше).
    //
    // Важно: для личных сообщений `payload['text']` уже зашифрован
    // (AES-256-CBC + HMAC). Посредник видит только base64-блоб
    // и ретранслирует его дальше. Расшифровать может только
    // отправитель и конечный адресат — у них общий ключ из
    // SHA-256(alias1:alias2).
    if (pkt.ttl > 0 && pkt.from != identity.alias) {
      store.put(pkt);
    }

    // Обновим/создадим соседа по факту прихода пакета.
    _markNeighbor(pkt.from, t);

    // Свои собственные пакеты — пропускаем.
    if (pkt.from == identity.alias) return;

    final isForMe = pkt.to == null ||
        pkt.to == identity.alias ||
        pkt.to == identity.nodeId;

    switch (pkt.type) {
      case MeshMessageType.beacon:
        // Отмечаем соседа и всё.
        break;

      case MeshMessageType.text:
        if (isForMe) {
          // Попробуем расшифровать, если сообщение зашифровано.
          //
          // Безопасность: расшифровка вызывается ТОЛЬКО для
          // сообщений, адресованных нам (`pkt.to == identity.alias`).
          // Если узел — посредник, isForMe == false и эта ветка
          // не выполняется вообще. Посредник никогда не увидит
          // открытый текст и не сможет его восстановить: у него
          // нет общего ключа с парой (pkt.from, pkt.to).
          final rawText = pkt.payload['text']?.toString() ?? '';
          final isEncrypted = pkt.payload['enc'] == true;
          String displayText = rawText;
          if (isEncrypted &&
              pkt.to != null &&
              pkt.to == identity.alias) {
            final dec = SecureChat.decrypt(
              rawText, pkt.from, pkt.to!, pkt.id,
            );
            if (dec != null) {
              displayText = dec;
            } else {
              displayText = '🔒 [не удалось расшифровать]';
            }
          } else if (SecureChat.isEncrypted(rawText) &&
              pkt.to != null &&
              pkt.to == identity.alias) {
            // Старый формат без флага enc — пробуем всё равно.
            final dec = SecureChat.decrypt(
              rawText, pkt.from, pkt.to!, pkt.id,
            );
            if (dec != null) displayText = dec;
          }
          final peer = pkt.to == identity.alias
              ? pkt.from
              : (pkt.to ?? pkt.from);
          final msg = ChatMessage(
            id: pkt.id,
            from: pkt.from,
            to: pkt.to,
            peerId: peer,
            text: displayText,
            timestamp: pkt.timestamp == 0
                ? DateTime.now().millisecondsSinceEpoch
                : pkt.timestamp,
            status: DeliveryStatus.delivered,
            hops: pkt.hop,
            isMine: false,
          );
          await dialogs.add(msg, incrementUnread: true);
          // Локальное push-уведомление — работает офлайн, без сервера.
          await LocalNotify.message(
            id: pkt.id.hashCode & 0x7fffffff,
            title: 'Сообщение от ${pkt.from}',
            body: displayText,
            payload: peer,
          );
          // ACK
          _sendRaw(MeshPacket(
            type: MeshMessageType.ack,
            from: identity.alias,
            to: pkt.from,
            id: IdentityService.newPacketId(),
            ttl: 4,
            signature: identity.sign('ack'),
            payload: {'id': pkt.id, 'group': identity.groupId},
          ));
          store.markDelivered(pkt.id);
        }
        if (pkt.ttl > 1) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;

      case MeshMessageType.ack:
        final ackId = pkt.payload['id']?.toString() ?? '';
        if (ackId.isNotEmpty) {
          _updateMessageStatus(ackId, DeliveryStatus.delivered);
          store.markDelivered(ackId);
        }
        if (pkt.ttl > 1 && pkt.to != null && pkt.to != identity.alias) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;

      case MeshMessageType.sos:
        if (isForMe) {
          final lat = pkt.payload['lat'];
          final lon = pkt.payload['lon'];
          String text = '🚨 ${pkt.payload['text'] ?? ''}';
          String bodyText = text;
          if (lat != null && lon != null) {
            final latStr = (lat as num).toStringAsFixed(5);
            final lonStr = (lon as num).toStringAsFixed(5);
            text += '\n📍 $latStr, $lonStr';
            bodyText = '${pkt.payload['text'] ?? ''} — $latStr, $lonStr';
          }
          await LocalNotify.alert(
            id: pkt.id.hashCode & 0x7fffffff,
            title: '🚨 SOS от ${pkt.from}',
            body: bodyText,
            payload: pkt.from,
          );
        }
        if (pkt.ttl > 1) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;

      case MeshMessageType.contactCard:
        contacts.onContactCard(
          (pkt.payload).cast<String, dynamic>(),
          pkt.from,
        );
        if (pkt.ttl > 1) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;

      case MeshMessageType.contactRequest:
        // Добавляем как запрос (если ещё не в контактах).
        contacts.onContactCard(
          {
            'id': pkt.payload['myId'] ?? pkt.from,
            'alias': pkt.payload['alias'] ?? pkt.from,
            'ts': pkt.payload['ts'] ?? DateTime.now().millisecondsSinceEpoch,
            'group': identity.groupId,
          },
          pkt.from,
        );
        // В ответ автоматически отправляем свою визитку.
        _sendRaw(contacts.buildContactCardPacket());
        if (pkt.ttl > 1) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;

      case MeshMessageType.room:
      case MeshMessageType.roomSnapshot:
        await rooms.onRoomPacket(pkt);
        // Локальный пуш на входящее сообщение в любом чате
        // (городском или общем). Срабатывает только для чужого
        // пакета.
        if (pkt.type == MeshMessageType.room &&
            pkt.from != identity.alias) {
          final text = pkt.payload['text']?.toString() ?? '';
          final slug = pkt.payload['room']?.toString() ?? '';
          final isGlobal = slug == 'global';
          await LocalNotify.message(
            id: pkt.id.hashCode & 0x7fffffff,
            title: isGlobal
                ? 'Общий чат'
                : 'Чат города',
            body: '${pkt.from}: $text',
            payload: pkt.from,
          );
        }
        if (pkt.ttl > 1) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;

      case MeshMessageType.geo:
        // Запоминаем город отправителя (если знаем slug).
        final slug = pkt.payload['slug']?.toString();
        final name = pkt.payload['city']?.toString();
        if (slug != null && name != null && name.isNotEmpty) {
          geo.rememberCityName(slug, name);
        }
        if (pkt.ttl > 1) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;

      case MeshMessageType.whoNear:
        // В ответ отдаём свою визитку.
        _sendRaw(contacts.buildContactCardPacket());
        _sendRaw(MeshPacket(
          type: MeshMessageType.beacon,
          from: identity.alias,
          id: IdentityService.newPacketId(),
          ttl: 1,
          signature: identity.sign('beacon'),
          payload: {
            'group': identity.groupId,
            'r': true,
            'replyTo': pkt.payload['reqId'],
          },
        ));
        if (pkt.ttl > 1) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;

      case MeshMessageType.relay:
      case MeshMessageType.discovery:
      case MeshMessageType.group:
        if (pkt.ttl > 1) {
          _sendRaw(pkt.copyWith(ttl: pkt.ttl - 1, hop: pkt.hop + 1));
        }
        break;
    }
    notifyListeners();
  }

  void _onNeighborEvent(NeighborEvent ev) {
    if (ev.gone) {
      _neighbors.removeWhere((n) => n.id == ev.id || n.addr == ev.addr);
    } else {
      final idx = _neighbors.indexWhere(
        (n) => n.id == ev.id || (n.addr != null && n.addr == ev.addr),
      );
      final n = Neighbor(
        id: ev.id,
        transport: 'mesh',
        name: ev.name,
        rssi: ev.rssi,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        addr: ev.addr,
      );
      if (idx >= 0) {
        _neighbors[idx] = n;
      } else {
        _neighbors.add(n);
        _neighborsCtrl.add(n);
      }
    }
    notifyListeners();
  }

  void _markNeighbor(String alias, Telegram t) {
    final id = '${t.transportName}:${t.fromId}';
    final idx = _neighbors.indexWhere((n) => n.id == id);
    final n = Neighbor(
      id: id,
      transport: t.transportName,
      name: alias,
      rssi: t.rssi,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      addr: t.fromId,
    );
    if (idx >= 0) {
      _neighbors[idx] = _neighbors[idx].copyWith(
        name: alias,
        rssi: t.rssi,
        lastSeen: n.lastSeen,
      );
    } else {
      _neighbors.add(n);
      _neighborsCtrl.add(n);
    }
  }

  Future<void> _updateMessageStatus(String id, DeliveryStatus status) async {
    // Ищем среди сообщений диалогов и обновляем статус.
    final allMsgs = dialogs.conversations
        .expand((c) => dialogs.messagesWith(c.peerId))
        .toList();
    for (final m in allMsgs) {
      if (m.id == id) {
        final updated = m.copyWith(status: status);
        await dialogs.add(updated);
        notifyListeners();
        return;
      }
    }
  }

  void _pruneStale() {
    var removed = false;
    _neighbors.removeWhere((n) {
      if (n.isStale) {
        removed = true;
        return true;
      }
      return false;
    });
    if (removed) notifyListeners();
  }
}
