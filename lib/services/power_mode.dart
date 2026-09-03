import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Режим энергопотребления устройства.
///
/// **Обычный**: BLE-скан каждые 4 сек, Wi-Fi broadcast каждые 30 сек.
/// **Эконом**:    BLE-скан каждые 60 сек (только слушаем, не пишем в эфир),
///                Wi-Fi — только приём. Сообщения, пришедшие по mesh,
///                ретранслируются раз в 2 минуты, чтобы не проснуться
///                ради каждого пакета.
enum PowerMode { normal, economy }

/// Сервис режима питания. Singleton через DI, но с глобальным
/// ChangeNotifier-каналом, чтобы транспорты могли подписаться.
class PowerModeService extends ChangeNotifier {
  static const _kKey = 'bm_power_mode';
  PowerMode _mode = PowerMode.normal;
  bool _loaded = false;

  PowerMode get mode => _mode;
  bool get isEconomy => _mode == PowerMode.economy;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    _mode = (raw == 'economy') ? PowerMode.economy : PowerMode.normal;
    _loaded = true;
    notifyListeners();
  }

  Future<void> set(PowerMode m) async {
    if (_mode == m) return;
    _mode = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, m == PowerMode.economy ? 'economy' : 'normal');
    notifyListeners();
  }

  /// Удобство: переключить на эконом (или обратно).
  Future<void> toggle() async {
    await set(_mode == PowerMode.normal ? PowerMode.economy : PowerMode.normal);
  }
}

/// Тайминги транспортов в разных режимах.
class PowerTimings {
  /// Пауза между циклами BLE-сканирования.
  final Duration bleScanGap;

  /// Длительность одного окна BLE-сканирования.
  final Duration bleScanWindow;

  /// Wi-Fi: интервал между broadcast UDP hello.
  final Duration wifiHelloGap;

  /// Интервал store-and-forward ретрансляции.
  final Duration rebroadcastGap;

  /// Строим тайминги из текущего режима.
  factory PowerTimings.of(PowerMode mode) {
    if (mode == PowerMode.economy) {
      return const PowerTimings(
        bleScanGap: Duration(seconds: 60),
        bleScanWindow: Duration(seconds: 2),
        wifiHelloGap: Duration(seconds: 240),
        rebroadcastGap: Duration(minutes: 2),
      );
    }
    return const PowerTimings(
      bleScanGap: Duration(seconds: 4),
      bleScanWindow: Duration(seconds: 4),
      wifiHelloGap: Duration(seconds: 30),
      rebroadcastGap: Duration(seconds: 45),
    );
  }

  const PowerTimings({
    required this.bleScanGap,
    required this.bleScanWindow,
    required this.wifiHelloGap,
    required this.rebroadcastGap,
  });
}
