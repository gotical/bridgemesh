import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Сервис сверки номера телефона с именем.
///
/// В BridgeMesh нет сервера и нет передачи контактов на сторону —
/// только локальная сверка последних 7 цифр номера.
///
/// Пользователь может либо:
///   • Разрешить чтение системных контактов (через нативный
///     канал, реализованный в MainActivity).
///   • Ввести «привязки» вручную в разделе «Люди».
///
/// Если узел в mesh прислал свой номер в визитке — мы ищем
/// соответствующее имя в локальной карте.
class PhoneBookService {
  static const _kManualKey = 'bm_phonebook_manual';
  final Map<String, String> _byNumber = {};
  bool _loaded = false;

  /// Загружает ручные привязки (номер → имя).
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kManualKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map>();
        for (final m in list) {
          final phone = m['p']?.toString() ?? '';
          final name = m['n']?.toString() ?? '';
          if (phone.isEmpty || name.isEmpty) continue;
          _byNumber[phone] = name;
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _byNumber.entries
        .map((e) => {'p': e.key, 'n': e.value})
        .toList();
    await prefs.setString(_kManualKey, jsonEncode(list));
  }

  /// Возвращает имя по последним 7 цифрам номера, либо null.
  Future<String?> nameFor(String phoneTail) async {
    await load();
    if (phoneTail.isEmpty) return null;
    return _byNumber[phoneTail];
  }

  /// Добавить привязку вручную.
  Future<void> putManual(String phone, String name) async {
    await load();
    final tail = _normalize(phone);
    if (tail.length >= 7) {
      _byNumber[tail.substring(tail.length - 7)] = name;
      await save();
    }
  }

  /// Удалить привязку.
  Future<void> remove(String phoneTail) async {
    await load();
    _byNumber.remove(phoneTail);
    await save();
  }

  /// Все привязки (последние 7 цифр → имя).
  Future<Map<String, String>> all() async {
    await load();
    return Map.unmodifiable(_byNumber);
  }

  String _normalize(String phone) =>
      phone.replaceAll(RegExp(r'[^\d]'), '');
}
