import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api.dart';

class Push {
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _done = false;
  static Future<void> register() async {
    if (_done || !Platform.isAndroid) return; _done = true;
    try {
      await _local.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await FirebaseMessaging.instance.requestPermission();
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await Api.post('/api/device-token', {'token': t});
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => Api.post('/api/device-token', {'token': t}));
      FirebaseMessaging.onMessage.listen((m) {                 // foreground banner
        final n = m.notification; if (n == null) return;
        _local.show(n.hashCode, n.title, n.body, const NotificationDetails(android: AndroidNotificationDetails('attendance', 'Attendance', importance: Importance.high, priority: Priority.high)));
      });
    } catch (_) {}
  }
}
