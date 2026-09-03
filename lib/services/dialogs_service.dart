import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import 'identity_service.dart';

/// Хранит личные сообщения и список диалогов.
///
/// В моей модели личные сообщения — это ВСЕГДА сообщения
/// с конкретным собеседником (`peerId`), они попадают в
/// соответствующий диалог. Групповые (комнатные) сообщения
/// живут отдельно в `RoomService`.
class DialogsService extends ChangeNotifier {
  static const _kDialogsKey = 'bm_dialogs';
  static const _kMessagesKey = 'bm_dm_msgs';

  final IdentityService identity;
  DialogsService(this.identity);

  // peerId -> Conversation
  final Map<String, Conversation> _dialogs = {};
  // id -> ChatMessage (все сообщения, чтобы не терялись)
  final Map<String, ChatMessage> _messages = {};

  List<Conversation> get conversations {
    final list = _dialogs.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return list;
  }

  Conversation? byPeer(String peerId) => _dialogs[peerId];

  List<ChatMessage> messagesWith(String peerId) {
    return _messages.values
        .where((m) => m.peerId == peerId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  int get totalUnread =>
      _dialogs.values.fold(0, (s, c) => s + c.unread);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dRaw = prefs.getString(_kDialogsKey);
    if (dRaw != null) {
      try {
        final list = (jsonDecode(dRaw) as List).cast<Map>();
        for (final j in list) {
          final c = Conversation.fromJson(j.cast<String, dynamic>());
          _dialogs[c.peerId] = c;
        }
      } catch (_) {}
    }
    final mRaw = prefs.getString(_kMessagesKey);
    if (mRaw != null) {
      try {
        final list = (jsonDecode(mRaw) as List).cast<Map>();
        for (final j in list) {
          final m = ChatMessage.fromJson(j.cast<String, dynamic>());
          _messages[m.id] = m;
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final dList = _dialogs.values.map((c) => c.toJson()).toList();
    final mList = _messages.values.map((m) => m.toJson()).toList();
    await prefs.setString(_kDialogsKey, jsonEncode(dList));
    await prefs.setString(_kMessagesKey, jsonEncode(mList));
  }

  /// Добавить сообщение. `peerId` — узел собеседника (или мой, если моё).
  /// Для входящих — `peerId` это тот, от кого пришло.
  /// Для исходящих — `peerId` это кому отправили.
  Future<void> add(ChatMessage m, {bool incrementUnread = false}) async {
    final peer = m.peerId;
    if (peer == null) return;
    _messages[m.id] = m;
    final conv = _dialogs.putIfAbsent(
      peer,
      () => Conversation(
        peerId: peer,
        peerName: m.isMine ? (m.to ?? peer) : m.from,
        lastSeen: m.timestamp,
      ),
    );
    if (m.isMine) {
      conv.peerName = m.to ?? peer;
    } else if (conv.peerName == peer || conv.peerName.isEmpty) {
      conv.peerName = m.from;
    }
    conv.lastMessage = m;
    conv.lastSeen = m.timestamp;
    if (incrementUnread) conv.unread++;
    notifyListeners();
    await save();
  }

  /// Отметить диалог прочитанным.
  Future<void> markRead(String peerId) async {
    final c = _dialogs[peerId];
    if (c == null || c.unread == 0) return;
    c.unread = 0;
    notifyListeners();
    await save();
  }

  /// Привязать имя из записной книжки.
  Future<void> setPhoneBookName(String peerId, String? name) async {
    final c = _dialogs[peerId];
    if (c == null) return;
    c.phoneBookName = name;
    notifyListeners();
    await save();
  }

  /// Удалить диалог и его сообщения.
  Future<void> remove(String peerId) async {
    _dialogs.remove(peerId);
    _messages.removeWhere((_, m) => m.peerId == peerId);
    notifyListeners();
    await save();
  }

  /// Полная очистка.
  Future<void> clear() async {
    _dialogs.clear();
    _messages.clear();
    notifyListeners();
    await save();
  }
}
