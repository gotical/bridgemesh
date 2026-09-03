import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';

/// Симметричное шифрование переписки между двумя узлами.
///
/// Алгоритм:
///   • Ключ = SHA-256(alias1 + ":" + alias2), где узлы отсортированы.
///   • AES-256-CBC + PKCS7 (реализован вручную).
///   • IV = первые 16 байт SHA-256 от ID сообщения.
///   • Каждое сообщение подписано HMAC для контроля целостности.
///
/// Чаты в городе (room) — публичные, без шифрования.
class SecureChat {
  static const int _blockSize = 16;

  static Uint8List sharedKey(String a, String b) {
    final sorted = [a, b]..sort();
    final raw = utf8.encode('${sorted[0]}:${sorted[1]}');
    return Uint8List.fromList(crypto.sha256.convert(raw).bytes);
  }

  static Uint8List _ivFor(String packetId) {
    final h = crypto.sha256.convert(utf8.encode('iv:$packetId')).bytes;
    return Uint8List.fromList(h.sublist(0, 16));
  }

  /// PKCS7 padding — добавляет 1..blockSize байт.
  static Uint8List _pad(Uint8List data) {
    final padLen = _blockSize - (data.length % _blockSize);
    final out = Uint8List(data.length + padLen);
    out.setRange(0, data.length, data);
    for (var i = data.length; i < out.length; i++) {
      out[i] = padLen;
    }
    return out;
  }

  /// Удаление PKCS7 padding. Если паддинг невалидный, бросает.
  static Uint8List _unpad(Uint8List data) {
    if (data.isEmpty || data.length % _blockSize != 0) {
      throw const FormatException('Bad PKCS7 length');
    }
    final padLen = data[data.length - 1];
    if (padLen < 1 || padLen > _blockSize) {
      throw const FormatException('Bad PKCS7 pad');
    }
    for (var i = data.length - padLen; i < data.length; i++) {
      if (data[i] != padLen) {
        throw const FormatException('Bad PKCS7 pad');
      }
    }
    return data.sublist(0, data.length - padLen);
  }

  /// Шифрует текст для получателя.
  /// Возвращает base64-строку с префиксом `enc:` для опознавания.
  static String encrypt(String text, String from, String to, String packetId) {
    final key = sharedKey(from, to);
    final iv = _ivFor(packetId);
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    final padded = _pad(Uint8List.fromList(utf8.encode(text)));
    final out = Uint8List(padded.length);
    for (var off = 0; off < padded.length; off += _blockSize) {
      cipher.processBlock(padded, off, out, off);
    }
    final sig = _hmac(key, out, packetId);
    return 'enc:${base64.encode(out)}:$sig';
  }

  /// Расшифровывает, проверяя подпись. Возвращает null, если
  /// ключ не подходит или подпись не совпадает.
  static String? decrypt(String blob, String from, String to, String packetId) {
    if (!blob.startsWith('enc:')) return blob;
    final key = sharedKey(from, to);
    final iv = _ivFor(packetId);
    final parts = blob.substring(4).split(':');
    if (parts.length != 2) return null;
    final ct = base64.decode(parts[0]);
    final sig = parts[1];
    final expectedSig = _hmac(key, ct, packetId);
    if (sig != expectedSig) return null;
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, pc.ParametersWithIV(pc.KeyParameter(key), iv));
    final out = Uint8List(ct.length);
    for (var off = 0; off < ct.length; off += _blockSize) {
      cipher.processBlock(ct, off, out, off);
    }
    final plain = _unpad(out);
    return utf8.decode(plain);
  }

  static String _hmac(Uint8List key, Uint8List data, String packetId) {
    final hmac = crypto.Hmac(crypto.sha256, key);
    final digest = hmac.convert([
      ...utf8.encode(packetId),
      ...data,
    ]);
    return digest.toString().substring(0, 16);
  }

  static bool isEncrypted(String blob) => blob.startsWith('enc:');

  static String fingerprint(String a, String b) {
    final key = sharedKey(a, b);
    return key
        .sublist(0, 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
