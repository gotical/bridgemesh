import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact.dart';
import '../models/mesh_packet.dart';
import 'identity_service.dart';
import 'phonebook_service.dart';

/// Сервис контактов.
///
/// Хранит:
///  • мои контакты (узлы, которые я добавил)
///  • запросы на добавление (от кого пришёл contactRequest)
///  • последние визитки от любых узлов (autoLearсed), чтобы мы могли
///    показать историю имён даже для тех, кого не добавляли.
///
/// Реализует логику «mutual»: если узел A добавил B и узел B тоже
/// добавил A — связь помечается как взаимная, и каждая сторона
/// хранит короткую метку «вы добавили друг друга».
class ContactService extends ChangeNotifierService {
  static const _kContactsKey = 'bm_contacts';
  static const _kRequestsKey = 'bm_contact_requests';
  static const _kLearnedKey = 'bm_contact_learned';

  final IdentityService identity;
  PhoneBookService? _phonebook;

  final Map<String, Contact> _contacts = {};     // nodeId -> Contact
  final Map<String, Contact> _requests = {};    // входящие запросы
  final Map<String, Contact> _learned = {};     // авто-выученные визитки

  ContactService(this.identity);

  void bindPhoneBook(PhoneBookService pb) {
    _phonebook = pb;
  }

  List<Contact> get contacts => _contacts.values.toList()
    ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  List<Contact> get pendingRequests => _requests.values.toList()
    ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  Iterable<Contact> get learned => _learned.values;

  Contact? byId(String nodeId) =>
      _contacts[nodeId] ?? _learned[nodeId] ?? _requests[nodeId];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _loadFrom(prefs.getString(_kContactsKey), _contacts);
    _loadFrom(prefs.getString(_kRequestsKey), _requests);
    _loadFrom(prefs.getString(_kLearnedKey), _learned);
  }

  void _loadFrom(String? raw, Map<String, Contact> map) {
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map>();
      for (final m in list) {
        final c = Contact.fromJson(m.cast<String, dynamic>());
        map[c.nodeId] = c;
      }
    } catch (_) {}
  }

  Future<void> _save(String key, Map<String, Contact> map) async {
    final prefs = await SharedPreferences.getInstance();
    final list = map.values.map((c) => c.toJson()).toList();
    await prefs.setString(key, jsonEncode(list));
  }

  /// Обработка чужой визитной карточки (mesh-пакет contactCard).
  ///
  /// Если узел уже в контактах — обновляет alias и историю.
  /// Если нет — попадает в «learned», и его можно посмотреть/добавить.
  Future<void> onContactCard(Map<String, dynamic> card, String fromId) async {
    final id = card['id'] as String? ?? fromId;
    if (id == identity.nodeId) return;
    final alias = card['alias'] as String? ?? 'Без имени';
    final ts = (card['ts'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final sig = card['sig'] as String? ?? '';
    final phoneTail = card['ph'] as String? ?? '';

    if (sig.length < 8) return;

    final histRaw = (card['h'] as List?) ?? const [];
    final hist = <AliasHistoryEntry>[];
    if (histRaw.isNotEmpty) {
      for (final m in histRaw.cast<Map>()) {
        hist.add(AliasHistoryEntry.fromJson(m.cast<String, dynamic>()));
      }
    } else {
      hist.add(AliasHistoryEntry(alias: alias, since: ts));
    }

    // Сверяем с записной книжкой (если есть).
    String? pbName;
    if (_phonebook != null && phoneTail.isNotEmpty) {
      pbName = await _phonebook!.nameFor(phoneTail);
    }

    final newCard = Contact(
      nodeId: id,
      alias: alias,
      aliasHistory: hist,
      addedAt: ts,
      lastSeen: ts,
      group: card['group'] as String?,
      phone: phoneTail.isNotEmpty ? phoneTail : null,
      phoneBookName: pbName,
    );

    final wasContact = _contacts.containsKey(id);
    final wasRequest = _requests.containsKey(id);

    if (wasContact) {
      final old = _contacts[id]!;
      // Обновляем алиас и при необходимости историю.
      if (old.alias != alias) {
        newCard.aliasHistory.add(
          AliasHistoryEntry(
            alias: alias,
            since: ts,
          ),
        );
      }
      _contacts[id] = old.copyWith(
        alias: alias,
        aliasHistory: newCard.aliasHistory,
        lastSeen: ts,
        group: card['group'] as String?,
        online: true,
      );
      await _save(_kContactsKey, _contacts);
    } else if (wasRequest) {
      _requests[id] = _requests[id]!.copyWith(
        alias: alias,
        aliasHistory: hist,
        lastSeen: ts,
        online: true,
      );
      await _save(_kRequestsKey, _requests);
    } else {
      _learned[id] = newCard;
      await _save(_kLearnedKey, _learned);
    }
    notifyListeners();
  }

  /// Добавляет узел в мои контакты (по nodeId).
  Future<void> addContact(String nodeId, {String? note}) async {
    final src = _learned.remove(nodeId) ??
        _requests.remove(nodeId) ??
        Contact(
          nodeId: nodeId,
          alias: nodeId.substring(0, 4),
          addedAt: DateTime.now().millisecondsSinceEpoch,
          lastSeen: DateTime.now().millisecondsSinceEpoch,
        );
    src.note = note;
    _contacts[nodeId] = src.copyWith(
      lastSeen: DateTime.now().millisecondsSinceEpoch,
    );
    await _save(_kContactsKey, _contacts);
    await _save(_kLearnedKey, _learned);
    await _save(_kRequestsKey, _requests);
    notifyListeners();
  }

  /// Полностью заменить список контактов (для восстановления из бэкапа).
  Future<void> replaceAll(List<Contact> newContacts) async {
    _contacts
      ..clear()
      ..addEntries(newContacts.map((c) => MapEntry(c.nodeId, c)));
    await _save(_kContactsKey, _contacts);
    notifyListeners();
  }

  /// Отправить запрос на добавление в контакты (mesh).
  Future<MeshPacket> buildContactRequest() async {
    final id = IdentityService.newPacketId();
    return MeshPacket(
      type: MeshMessageType.contactRequest,
      from: identity.alias,
      to: null,
      id: id,
      ttl: 4,
      signature: identity.sign('cr|$id'),
      payload: {
        'myId': identity.nodeId,
        'alias': identity.alias,
        'ts': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Принять входящий запрос — добавить обоих.
  Future<void> acceptRequest(String nodeId) async {
    final req = _requests.remove(nodeId);
    if (req != null) {
      _contacts[nodeId] = req.copyWith(
        mutual: true,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
      );
      await _save(_kContactsKey, _contacts);
      await _save(_kRequestsKey, _requests);
      notifyListeners();
    }
  }

  /// Отклонить входящий запрос.
  Future<void> rejectRequest(String nodeId) async {
    _requests.remove(nodeId);
    await _save(_kRequestsKey, _requests);
    notifyListeners();
  }

  /// Удалить контакт.
  Future<void> removeContact(String nodeId) async {
    _contacts.remove(nodeId);
    await _save(_kContactsKey, _contacts);
    notifyListeners();
  }

  /// Создаёт mesh-пакет с моей визиткой.
  MeshPacket buildContactCardPacket() {
    final card = identity.contactCard();
    card['h'] = identity.aliasHistory
        .map((e) => e.toJson())
        .toList();
    return MeshPacket(
      type: MeshMessageType.contactCard,
      from: identity.alias,
      id: IdentityService.newPacketId(),
      ttl: 5,
      signature: identity.sign('cc'),
      payload: card,
    );
  }

  /// Очистить авто-выученные визитки.
  Future<void> clearLearned() async {
    _learned.clear();
    await _save(_kLearnedKey, _learned);
    notifyListeners();
  }
}

/// Минимальный аналог ChangeNotifier для изоляции.
abstract class ChangeNotifierService {
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
