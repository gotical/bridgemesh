import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис геолокации + определения текущего города.
///
///  1. Запрашивает разрешения.
 ///  2. Получает GPS-координаты.
///  3. Округляет до сетки ~3 км и использует как «slug» города —
///     стабильный ключ комнаты, общий у всех узлов в одной точке.
///  4. Поддерживает таблицу «slug → красивое имя», которая
///     пополняется, когда узлы обмениваются geo-пакетами.
class GeoService extends ChangeNotifier {
  static const _kCityTableKey = 'bm_city_table';
  static const _kSavedLatKey = 'bm_last_lat';
  static const _kSavedLonKey = 'bm_last_lon';
  static const _kSavedSlugKey = 'bm_last_slug';
  static const _kSavedNameKey = 'bm_last_name';

  Position? _position;
  String _currentSlug = 'unknown';
  String _currentName = 'Не определён';
  bool _running = false;
  bool _hasGpsFix = false;
  Timer? _ticker;

  final Map<String, String> _cityTable = {};

  Position? get position => _position;
  String get currentCityName => _currentName;
  String get currentCitySlug => _currentSlug;
  bool get isRunning => _running;
  bool get hasGpsFix => _hasGpsFix;

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
    // Восстанавливаем последний известный город — чтобы пользователь
    // видел название, пока новый GPS-запрос ещё не пришёл.
    final savedLat = prefs.getDouble(_kSavedLatKey);
    final savedLon = prefs.getDouble(_kSavedLonKey);
    final savedSlug = prefs.getString(_kSavedSlugKey);
    final savedName = prefs.getString(_kSavedNameKey);
    if (savedSlug != null && savedName != null) {
      _currentSlug = savedSlug;
      _currentName = savedName;
      _position = (savedLat != null && savedLon != null)
          ? _fakePosition(savedLat, savedLon)
          : null;
      notifyListeners();
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
    _running = true;
    // Первый запуск без тика — он ждёт разрешения.
    unawaited(_tick());
    _ticker = Timer.periodic(period, (_) => _tick());
  }

  void stop() {
    _running = false;
    _ticker?.cancel();
    _ticker = null;
  }

  /// Разовый запрос GPS. Используется по тапу «Уточнить».
  Future<bool> tryDetectNow() async {
    final ok = await requestPermission();
    if (!ok) {
      notifyListeners();
      return false;
    }
    await _tick();
    return _hasGpsFix;
  }

  /// Позволяет вручную задать название текущего города (например,
  /// когда GPS недоступен, но пользователь знает, где он).
  Future<void> setManualCity(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return;
    final slug = 'manual-${cleaned.toLowerCase().replaceAll(RegExp(r"\s+"), "-")}';
    _currentSlug = slug;
    _currentName = cleaned;
    _cityTable[slug] = cleaned;
    await _persistCity();
    await _persist();
    notifyListeners();
  }

  Future<void> _tick() async {
    try {
      _position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _hasGpsFix = true;
      _currentSlug = _slugFor(_position!.latitude, _position!.longitude);
      _currentName = _cityTable[_currentSlug] ?? _defaultName(_currentSlug);
      await _persistCity();
      notifyListeners();
    } catch (_) {
      // GPS недоступен — оставляем последний известный город.
    }
  }

  Future<void> _persistCity() async {
    final prefs = await SharedPreferences.getInstance();
    if (_position != null) {
      await prefs.setDouble(_kSavedLatKey, _position!.latitude);
      await prefs.setDouble(_kSavedLonKey, _position!.longitude);
    }
    await prefs.setString(_kSavedSlugKey, _currentSlug);
    await prefs.setString(_kSavedNameKey, _currentName);
  }

  Position _fakePosition(double lat, double lon) {
    // Используется только для восстановления превью в UI.
    // Не отдаётся в роутинг.
    final t = DateTime.now().millisecondsSinceEpoch.toDouble();
    return Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.fromMillisecondsSinceEpoch(t.toInt()),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  /// Грубая привязка координат к slug вида «58.05-38.83» (≈3 км).
  static String _slugFor(double lat, double lon) {
    final rLat = (lat * 100).round() / 100;
    final rLon = (lon * 100).round() / 100;
    return '${rLat.toStringAsFixed(2)}-${rLon.toStringAsFixed(2)}';
  }

  /// Подбирает имя по умолчанию на основе координат.
  String _defaultName(String slug) {
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
    notifyListeners();
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
