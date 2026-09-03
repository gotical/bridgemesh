import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Локальные уведомления Android (без интернета, без сервера).
class LocalNotify {
  static const _channelMessageId = 'bm_msg';
  static const _channelMessageName = 'Сообщения';
  static const _channelSosId = 'bm_sos';
  static const _channelSosName = 'SOS и тревога';
  static const _channelSystemId = 'bm_system';
  static const _channelSystemName = 'Система';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    try {
      await _plugin.initialize(settings);
    } catch (e) {
      debugPrint('LocalNotify init failed: $e');
    }
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelMessageId,
            _channelMessageName,
            description: 'Личные и групповые сообщения',
            importance: Importance.high,
            enableVibration: true,
          ),
        );
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelSosId,
            _channelSosName,
            description: 'Экстренные уведомления',
            importance: Importance.max,
            enableVibration: true,
          ),
        );
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelSystemId,
            _channelSystemName,
            description: 'Состояние mesh-сети',
            importance: Importance.low,
          ),
        );
        await androidImpl.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('LocalNotify channels failed: $e');
    }
    _ready = true;
  }

  static Future<void> message({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _show(
      androidId: _channelMessageId,
      androidName: _channelMessageName,
      id: id,
      title: title,
      body: body,
      payload: payload,
      importance: Importance.high,
    );
  }

  static Future<void> alert({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _show(
      androidId: _channelSosId,
      androidName: _channelSosName,
      id: id,
      title: title,
      body: body,
      payload: payload,
      importance: Importance.max,
    );
  }

  static Future<void> system({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _show(
      androidId: _channelSystemId,
      androidName: _channelSystemName,
      id: id,
      title: title,
      body: body,
      payload: payload,
      importance: Importance.low,
    );
  }

  static Future<void> _show({
    required String androidId,
    required String androidName,
    required int id,
    required String title,
    required String body,
    String? payload,
    required Importance importance,
  }) async {
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          androidId,
          androidName,
          channelDescription: 'BridgeMesh',
          importance: importance,
          priority: importance == Importance.max
              ? Priority.max
              : importance == Importance.high
                  ? Priority.high
                  : Priority.low,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
          playSound: true,
          category: AndroidNotificationCategory.message,
        ),
      );
      await _plugin.show(id, title, body, details, payload: payload);
    } catch (e) {
      debugPrint('LocalNotify show failed: $e');
    }
  }
}
