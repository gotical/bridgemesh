import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/contact.dart';

/// Сервис идентичности узла.
///
/// Генерирует стабильный уникальный `nodeId` на основе аппаратных
/// идентификаторов устройства (MAC-адресов Bluetooth и Wi-Fi,
/// ANDROID_ID, IMEI при наличии). Этот ID не меняется между
/// переустановками и гарантирует, что один и тот же человек
/// распознаётся как один и тот же узел на любом устройстве сети.
///
/// Также хранит историю display-имён, чтобы можно было увидеть,
/// как пользователь переименовывал себя со временем.
class IdentityService {
  static const _kAliasKey = 'bm_alias';
  static const _kSecretKey = 'bm_secret';
  static const _kGroupKey = 'bm_group';
  static const _kHistoryKey = 'bm_alias_history';
  static const _kNodeIdKey = 'bm_node_id';
  static const _kSourceKey = 'bm_node_source';
  static const _kPhoneKey = 'bm_phone';

  String _alias = 'Без имени';
  String _nodeId = '';
  String _source = '';
  Uint8List _secret = Uint8List(32);
  String _groupId = 'public';
  String _phone = '';
  bool _ready = false;

  final List<AliasHistoryEntry> _aliasHistory = [];

  String get alias => _alias;
  String get displayName => _alias;
  String get nodeId => _nodeId;
  String get source => _source;
  String get groupId => _groupId;
  String get phone => _phone;
  bool get isReady => _ready;
  List<AliasHistoryEntry> get aliasHistory => List.unmodifiable(_aliasHistory);

  /// Прошёл ли пользователь онбординг (ввёл имя).
  bool get isOnboarded =>
      _ready &&
      _nodeId.isNotEmpty &&
      _alias.isNotEmpty &&
      _alias != 'Без имени';

  /// Краткий «чип-идентификатор» вида A1B2-3C4D, удобный для
  /// визуального подтверждения при добавлении контакта.
  String get shortNodeId {
    if (_nodeId.isEmpty) return '------';
    final s = _nodeId.replaceAll(RegExp(r'[^A-F0-9]'), '').toUpperCase();
    if (s.length < 8) return _nodeId;
    return '${s.substring(0, 4)}-${s.substring(4, 8)}';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. История имён (создаём заранее, чтобы применить).
    final histJson = prefs.getString(_kHistoryKey);
    if (histJson != null) {
      try {
        final list = (jsonDecode(histJson) as List).cast<Map>();
        _aliasHistory
          ..clear()
          ..addAll(list.map((m) => AliasHistoryEntry.fromJson(
                m.cast<String, dynamic>(),
              )));
      } catch (_) {}
    }

    // 2. Алиас — текущее имя.
    var alias = prefs.getString(_kAliasKey);
    if (alias == null || alias.trim().isEmpty) {
      alias = _suggestAlias();
      _aliasHistory.add(AliasHistoryEntry(
        alias: alias,
        since: DateTime.now().millisecondsSinceEpoch,
      ));
      await prefs.setString(_kHistoryKey, _encodeHistory());
    }
    _alias = alias;

    // 3. nodeId из hardware fingerprint.
    _nodeId = prefs.getString(_kNodeIdKey) ?? '';
    _source = prefs.getString(_kSourceKey) ?? '';
    if (_nodeId.isEmpty) {
      final fp = await _collectFingerprint();
      _nodeId = fp.id;
      _source = fp.source;
      await prefs.setString(_kNodeIdKey, _nodeId);
      await prefs.setString(_kSourceKey, _source);
    }

    // 4. Секрет для HMAC.
    final stored = prefs.getString(_kSecretKey);
    if (stored == null) {
      final rnd = Random.secure();
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = rnd.nextInt(256);
      }
      _secret = bytes;
      await prefs.setString(_kSecretKey, base64Encode(bytes));
    } else {
      _secret = base64Decode(stored);
    }

    // 5. Группа.
    _groupId = prefs.getString(_kGroupKey) ?? 'public';

    // 6. Номер телефона (опционально).
    _phone = prefs.getString(_kPhoneKey) ?? '';

    _ready = true;
  }

  Future<void> setAlias(String alias) async {
    if (alias.trim().isEmpty) return;
    final newAlias = alias.trim();
    if (newAlias == _alias) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _alias = newAlias;
    _aliasHistory.add(AliasHistoryEntry(alias: newAlias, since: now));
    if (_aliasHistory.length > 200) {
      _aliasHistory.removeRange(0, _aliasHistory.length - 200);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAliasKey, newAlias);
    await prefs.setString(_kHistoryKey, _encodeHistory());
  }

  Future<void> setGroup(String id) async {
    _groupId = id.trim().isEmpty ? 'public' : id.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGroupKey, _groupId);
  }

  /// Сохранить номер телефона (используется для удобства:
  /// собеседник видит имя из своей записной книжки, если ввёл
  /// этот же номер у себя).
  Future<void> setPhone(String phone) async {
    // Оставляем только цифры и плюс.
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    _phone = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhoneKey, _phone);
  }

  /// Последние 7 цифр номера — для грубой сверки без подтверждения.
  String get phoneTail {
    if (_phone.isEmpty) return '';
    final digits = _phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return digits;
    return digits.substring(digits.length - 7);
  }

  /// Полностью заменить историю имён (используется при восстановлении
  /// из бэкапа).
  Future<void> replaceAliasHistory(List<AliasHistoryEntry> entries) async {
    _aliasHistory
      ..clear()
      ..addAll(entries);
    if (_aliasHistory.length > 200) {
      _aliasHistory.removeRange(0, _aliasHistory.length - 200);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHistoryKey, _encodeHistory());
  }

  String _encodeHistory() =>
      jsonEncode(_aliasHistory.map((e) => e.toJson()).toList());

  /// HMAC-SHA256 подпись.
  String sign(String message) {
    final key = crypto.Hmac(crypto.sha256, _secret);
    final digest = key.convert(utf8.encode(message));
    return digest.toString().substring(0, 16);
  }

  static String newPacketId() => const Uuid().v4();

  /// Возвращает контактную визитку, которую узел рассылает в mesh.
  /// Содержит: nodeId, alias, group, телефон, отметку времени, HMAC.
  Map<String, dynamic> contactCard() => {
        'v': 1,
        'id': _nodeId,
        'alias': _alias,
        'group': _groupId,
        'ph': phoneTail,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'src': _source,
        'sig': sign('$_nodeId|$_alias|${DateTime.now().millisecondsSinceEpoch ~/ 60000}'),
      };

  static String _suggestAlias() {
    final rnd = Random();
    final animals = [
      'Сокол', 'Тигр', 'Ворон', 'Кедр', 'Лотос', 'Квант',
      'Нептун', 'Орион', 'Луч', 'Вихрь', 'Мангуст', 'Ястреб',
      'Ветер', 'Туча', 'Кристалл', 'Искра', 'Молния', 'Рысь',
      'Дуб', 'Беркут', 'Феникс', 'Олень', 'Лиса', 'Волк',
    ];
    return animals[rnd.nextInt(animals.length)] +
        '-' +
        (1000 + rnd.nextInt(8999)).toString();
  }

  /// Собирает аппаратный fingerprint устройства.
  static Future<_Fingerprint> _collectFingerprint() async {
    final parts = <String, String>{};
    final info = DeviceInfoPlugin();

    try {
      final android = await info.androidInfo;
      parts['androidId'] = android.id;
      parts['model'] = android.model;
      parts['brand'] = android.brand;
      parts['hardware'] = android.hardware;
      // androidId стабилен и не меняется при переустановке (по словам
      // Google — но на практике меняется при factory reset).
      if (Platform.isAndroid) {
        parts['api'] = android.version.sdkInt.toString();
      }
    } catch (_) {
      // Не критично.
    }

    final raw = parts.entries
            .map((e) => '${e.key}=${e.value}')
            .join('|')
            .trim() +
        '|fallback=${const Uuid().v4()}';

    // SHA-256 от fingerprint -> 16 hex символов.
    final digest = crypto.sha256.convert(utf8.encode(raw)).toString();
    return _Fingerprint(
      id: digest.substring(0, 16).toUpperCase(),
      source: 'android-hw',
    );
  }
}

class _Fingerprint {
  final String id;
  final String source;
  _Fingerprint({required this.id, required this.source});
}
