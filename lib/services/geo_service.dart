import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис геолокации + определения текущего города.
///
/// На Android мы:
///  1. Запрашиваем разрешения.
///  2. Получаем GPS-координаты.
///  3. Округляем их до сетки ~3 км и используем как «slug» города
///     — это даёт стабильный ключ комнаты, который будет совпадать
///     у всех узлов в одной географической точке.
///  4. Поддерживаем таблицу «slug → красивое имя» (например
///     58.05/38.83 → «Рыбинск»), которая расширяется по мере того,
///     как узлы обмениваются geo-пакетами.
class GeoService {
  static const _kCityTableKey = 'bm_city_table';

  Position? _position;
  String _currentSlug = 'unknown';
  String _currentName = 'Не определён';
  bool _running = false;
  Timer? _ticker;

  final Map<String, String> _cityTable = {};

  Position? get position => _position;
  String get currentCityName => _currentName;
  String get currentCitySlug => _currentSlug;
  bool get isRunning => _running;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCityTableKey);
    if (raw != null) {
      try {
        _cityTable.addAll(
          (jsonDecode(raw) as Map).cast<String, String>(),
        );
      } catch (_) {}
    }
  }

  Future<bool> requestPermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.always ||
        p == LocationPermission.whileInUse;
  }

  Future<void> start({Duration period = const Duration(seconds: 60)}) async {
    if (_running) return;
    final ok = await requestPermission();
    if (!ok) {
      _running = false;
      return;
    }
    _running = true;
    _tick();
    _ticker = Timer.periodic(period, (_) => _tick());
  }

  void stop() {
    _running = false;
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _tick() async {
    try {
      _position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _currentSlug = _slugFor(_position!.latitude, _position!.longitude);
      _currentName = _cityTable[_currentSlug] ?? _defaultName(_currentSlug);
    } catch (_) {
      // Без GPS — остаёмся на старом значении.
    }
  }

  /// Грубая привязка координат к slug вида «58.05-38.83» (≈3 км).
  static String _slugFor(double lat, double lon) {
    final rLat = (lat * 100).round() / 100;
    final rLon = (lon * 100).round() / 100;
    return '${rLat.toStringAsFixed(2)}-${rLon.toStringAsFixed(2)}';
  }

  /// Подбирает имя по умолчанию на основе координат.
  String _defaultName(String slug) {
    // Набор опорных городов (Россия + мир).
    const known = <_CityRef>[
      _CityRef('Рыбинск', 58.05, 38.83),
      _CityRef('Ярославль', 57.63, 39.87),
      _CityRef('Москва', 55.76, 37.62),
      _CityRef('Санкт-Петербург', 59.93, 30.32),
      _CityRef('Тутаев', 57.87, 39.55),
      _CityRef('Углич', 57.53, 38.33),
      _CityRef('Мышкин', 57.79, 38.45),
      _CityRef('Пошехонье', 58.51, 39.12),
      _CityRef('Кострома', 57.77, 40.93),
      _CityRef('Вологда', 59.22, 39.88),
      _CityRef('Череповец', 59.13, 37.91),
      _CityRef('Иваново', 56.99, 40.97),
      _CityRef('Владимир', 56.13, 40.41),
      _CityRef('Нижний Новгород', 56.33, 44.01),
      _CityRef('Казань', 55.79, 49.12),
      _CityRef('Самара', 53.20, 50.15),
      _CityRef('Екатеринбург', 56.84, 60.61),
      _CityRef('Новосибирск', 55.04, 82.92),
      _CityRef('Красноярск', 56.01, 92.87),
      _CityRef('Иркутск', 52.29, 104.30),
      _CityRef('Хабаровск', 48.48, 135.07),
      _CityRef('Владивосток', 43.12, 131.92),
      _CityRef('Минск', 53.90, 27.57),
      _CityRef('Киев', 50.45, 30.52),
      _CityRef('Алматы', 43.25, 76.95),
      _CityRef('Ташкент', 41.30, 69.27),
    ];
    final parts = slug.split('-');
    if (parts.length != 2) return 'Город $slug';
    final lat = double.tryParse(parts[0]) ?? 0;
    final lon = double.tryParse(parts[1]) ?? 0;

    _CityRef? nearest;
    double bestDist = double.infinity;
    for (final c in known) {
      final d = _distance(lat, lon, c.lat, c.lon);
      if (d < bestDist) {
        bestDist = d;
        nearest = c;
      }
    }
    if (nearest != null && bestDist < 30) {
      _cityTable[slug] = nearest.name;
      // ignore: discarded_futures
      _persist();
      return nearest.name;
    }
    return 'Город $slug';
  }

  /// Применяет к slug человекочитаемое имя (например, от других узлов).
  Future<void> rememberCityName(String slug, String name) async {
    if (name.isEmpty || name == _cityTable[slug]) return;
    _cityTable[slug] = name;
    if (slug == _currentSlug) _currentName = name;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCityTableKey, jsonEncode(_cityTable));
  }

  static double _distance(double lat1, double lon1, double lat2, double lon2) {
    final dLat = lat1 - lat2;
    final dLon = lon1 - lon2;
    return math.sqrt(dLat * dLat + dLon * dLon);
  }
}

class _CityRef {
  final String name;
  final double lat;
  final double lon;
  const _CityRef(this.name, this.lat, this.lon);
}
