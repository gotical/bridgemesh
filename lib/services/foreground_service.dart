import 'package:flutter/services.dart';

/// Обёртка для Android-foreground-сервиса. Не даёт системе убить
/// mesh-приложение при сворачивании экрана.
class ForegroundService {
  static const _ch = MethodChannel('bridge_mesh/foreground');

  /// Запустить сервис. Уведомление появится в шторке.
  static Future<bool> start() async {
    try {
      final r = await _ch.invokeMethod<bool>('start');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Остановить сервис (например, при выходе из приложения или
  /// когда пользователь полностью отключил mesh).
  static Future<bool> stop() async {
    try {
      final r = await _ch.invokeMethod<bool>('stop');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }
}
