import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';
import 'config.dart';
import 'messenger.dart';

/// Android phone push (FCM). Windows builds swap this file for push_stub.dart (see workflow).
class Push {
  static bool _ready = false, _registered = false;
  static Future<void> init() async {
    if (!Platform.isAndroid || Config.fbApiKey.isEmpty) return;
    try {
      await Firebase.initializeApp(options: const FirebaseOptions(apiKey: Config.fbApiKey, appId: Config.fbAppId, messagingSenderId: Config.fbSenderId, projectId: Config.fbProjectId));
      _ready = true;
    } catch (_) {}
  }
  static Future<void> register() async {
    if (!_ready || _registered) return;
    _registered = true;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await Api.post('/api/device-token', {'token': t});
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => Api.post('/api/device-token', {'token': t}));
      FirebaseMessaging.onMessage.listen((m) { final n = m.notification; if (n != null) toast('${n.title ?? ''}  ${n.body ?? ''}'.trim()); });
    } catch (_) {}
  }
}
