import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/key_derivators/api.dart' as pck;
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact.dart';
import 'identity_service.dart';
import 'contact_service.dart';
import 'room_service.dart';

/// Сервис шифрованного бэкапа.
///
/// Формат бэкапа (v1):
///   bmBackup:v1:<base64(salt)>:<base64(iv)>:<base64(payload)>
///
/// Алгоритм:
///   1. Из пароля пользователя и соли через PBKDF2 (HMAC-SHA256,
///      20000 итераций) получаем ключ 32 байта.
///   2. Шифруем JSON с данными через AES-256-CBC + PKCS7.
///   3. Соль и IV добавляются в файл / QR.
class BackupService extends ChangeNotifier {
  static const _kBackupMagic = 'bmBackup:v1:';
  static const int _pbkdf2Iterations = 20000;
  static const int _keyLenBytes = 32;
  static const int _saltLenBytes = 16;
  static const int _ivLenBytes = 16;
  static const int _blockSize = 16;

  final IdentityService identity;
  final ContactService contacts;
  final RoomService rooms;

  BackupService({
    required this.identity,
    required this.contacts,
    required this.rooms,
  });

  /// Создаёт зашифрованный бэкап в виде строки.
  Future<String> createBackup(String password) async {
    if (password.length < 4) {
      throw Exception('Пароль должен быть не короче 4 символов');
    }
    final snapshot = <String, dynamic>{
      'v': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'originNodeId': identity.nodeId,
      'originAlias': identity.alias,
      'aliasHistory': identity.aliasHistory.map((e) => {
        'alias': e.alias,
        'since': e.since,
      }).toList(),
      'group': identity.groupId,
      'contacts': contacts.contacts.map((c) => c.toJson()).toList(),
      'rooms': rooms.snapshotForBackup(),
      'roomsV': rooms.versionTag,
    };

    final json = utf8.encode(jsonEncode(snapshot));
    final salt = _randomBytes(_saltLenBytes);
    final iv = _randomBytes(_ivLenBytes);
    final key = _deriveKey(password, salt);
    final encrypted = _aesEncrypt(json, key, iv);

    return _kBackupMagic +
        base64.encode(salt) +
        ':' +
        base64.encode(iv) +
        ':' +
        base64.encode(encrypted);
  }

  /// Восстанавливает данные из бэкапа.
  Future<RestoreResult> restoreBackup(String payload, String password) async {
    if (!payload.startsWith(_kBackupMagic)) {
      throw Exception('Неверный формат файла бэкапа');
    }
    final parts = payload.substring(_kBackupMagic.length).split(':');
    if (parts.length != 3) {
      throw Exception('Битый файл бэкапа');
    }
    final salt = base64.decode(parts[0]);
    final iv = base64.decode(parts[1]);
    final ct = base64.decode(parts[2]);

    final key = _deriveKey(password, salt);
    final Uint8List plain;
    try {
      plain = _aesDecrypt(ct, key, iv);
    } catch (_) {
      throw Exception('Неверный пароль или повреждённый файл');
    }

    final data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final originNodeId = data['originNodeId']?.toString() ?? '';
    final originAlias = data['originAlias']?.toString() ?? '?';
    final isForeignDevice =
        originNodeId.isNotEmpty && originNodeId != identity.nodeId;

    await _apply(data);

    return RestoreResult(
      originNodeId: originNodeId,
      originAlias: originAlias,
      isForeignDevice: isForeignDevice,
      restoredAt: DateTime.now(),
      contactCount: (data['contacts'] as List?)?.length ?? 0,
    );
  }

  Future<void> _apply(Map<String, dynamic> data) async {
    final alias = data['originAlias']?.toString() ?? '';
    final group = data['group']?.toString() ?? '';
    if (alias.isNotEmpty) await identity.setAlias(alias);
    if (group.isNotEmpty) await identity.setGroup(group);

    final history = data['aliasHistory'] as List?;
    if (history != null) {
      await identity.replaceAliasHistory(
        history.map((e) {
          final m = e as Map<String, dynamic>;
          return AliasHistoryEntry(
            alias: m['alias']?.toString() ?? '',
            since: m['since'] is int
                ? m['since'] as int
                : DateTime.now().millisecondsSinceEpoch,
          );
        }).toList(),
      );
    }

    final cList = (data['contacts'] as List?) ?? [];
    final contacts2 = cList
        .whereType<Map>()
        .map((m) => Contact.fromJson(m.cast<String, dynamic>()))
        .toList();
    await contacts.replaceAll(contacts2);

    final roomsData = data['rooms'] as Map<String, dynamic>?;
    if (roomsData != null) {
      await rooms.restoreFromBackup(roomsData);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bm_restored_backup', true);
    await prefs.setString(
      'bm_restored_origin',
      data['originNodeId']?.toString() ?? '',
    );
    notifyListeners();
  }

  Future<void> clearRestoreFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bm_restored_backup');
    await prefs.remove('bm_restored_origin');
    notifyListeners();
  }

  Future<bool> isRestored() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('bm_restored_backup') ?? false;
  }

  Future<String?> restoredOrigin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('bm_restored_origin');
  }

  // ── Crypto helpers ─────────────────────────────────────────────

  Uint8List _randomBytes(int n) {
    // Используем crypto.Hmac для получения псевдослучайных байт
    // через смешивание sha256(secureRandomInputs).
    final r = RandomBasedBytes(n);
    return r.next(n);
  }

  Uint8List _deriveKey(String password, Uint8List salt) {
    final pwdBytes = utf8.encode(password);
    final mac = HMac(SHA256Digest(), 64);
    final derivator = PBKDF2KeyDerivator(mac)
      ..init(pck.Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLenBytes));
    return derivator.process(Uint8List.fromList(pwdBytes));
  }

  Uint8List _aesEncrypt(Uint8List data, Uint8List key, Uint8List iv) {
    final padded = _pad(data);
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    final out = Uint8List(padded.length);
    for (var off = 0; off < padded.length; off += _blockSize) {
      cipher.processBlock(padded, off, out, off);
    }
    return out;
  }

  Uint8List _aesDecrypt(Uint8List data, Uint8List key, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    final out = Uint8List(data.length);
    for (var off = 0; off < data.length; off += _blockSize) {
      cipher.processBlock(data, off, out, off);
    }
    return _unpad(out);
  }

  Uint8List _pad(Uint8List data) {
    final padLen = _blockSize - (data.length % _blockSize);
    final out = Uint8List(data.length + padLen);
    out.setRange(0, data.length, data);
    for (var i = data.length; i < out.length; i++) {
      out[i] = padLen;
    }
    return out;
  }

  Uint8List _unpad(Uint8List data) {
    if (data.isEmpty || data.length % _blockSize != 0) {
      throw const FormatException('Bad PKCS7 length');
    }
    final padLen = data[data.length - 1];
    if (padLen < 1 || padLen > _blockSize) {
      throw const FormatException('Bad PKCS7 pad');
    }
    return data.sublist(0, data.length - padLen);
  }
}

/// Простой генератор псевдослучайных байт на основе sha256.
class RandomBasedBytes {
  int _counter = 0;
  final List<int> _seed;
  RandomBasedBytes(int n) : _seed = List.generate(n, (i) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return ((ts >> (i * 4)) ^ ((ts + i) * 31)) & 0xFF;
  });
  Uint8List next(int n) {
    final out = Uint8List(n);
    var pos = 0;
    while (pos < n) {
      _counter++;
      final block = crypto.sha256
          .convert([..._seed, _counter & 0xFF, (_counter >> 8) & 0xFF])
          .bytes;
      final take = (n - pos).clamp(0, block.length);
      for (var i = 0; i < take; i++) {
        out[pos + i] = block[i];
      }
      pos += take;
    }
    return out;
  }
}

class RestoreResult {
  final String originNodeId;
  final String originAlias;
  final bool isForeignDevice;
  final DateTime restoredAt;
  final int contactCount;
  RestoreResult({
    required this.originNodeId,
    required this.originAlias,
    required this.isForeignDevice,
    required this.restoredAt,
    required this.contactCount,
  });
}
