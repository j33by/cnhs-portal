import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext, Route;
import 'package:flutter/widgets.dart' show Navigator;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'config.dart';
import 'img.dart';

typedef JRows = List<Map<String, dynamic>>;

/// Who was signed in last. Lets the app open straight into the last data when there is no internet,
/// and sign back in by itself as soon as the connection returns.
class Identity {
  static String? uid, sessionJson;
  static void load(SharedPreferences p) { uid = p.getString('id:uid'); sessionJson = p.getString('id:session'); }
  static Future<void> save(Session s) async {
    uid = s.user.id; sessionJson = jsonEncode(s.toJson());
    await LocalCache._p?.setString('id:uid', uid!); await LocalCache._p?.setString('id:session', sessionJson!);
  }
  static Future<void> clear() async { uid = null; sessionJson = null; await LocalCache._p?.remove('id:uid'); await LocalCache._p?.remove('id:session'); }
}

String? get myUidOrNull => sb.auth.currentUser?.id ?? Identity.uid;
String get myUid => myUidOrNull ?? '';

/// Last data seen on this phone, per signed-in user (JSON in SharedPreferences). Wiped on sign out.
class LocalCache {
  static SharedPreferences? _p;
  static SharedPreferences? get prefs => _p;
  static Future<void> init() async { _p = await SharedPreferences.getInstance(); Identity.load(_p!); }
  static String _k(String key) => 'c:$myUid:$key';
  static void write(String key, Object? v) {
    if (_p == null || myUid.isEmpty || v == null) { return; }
    try { _p!.setString(_k(key), jsonEncode(v)); } catch (_) {}
  }
  static dynamic read(String key) {
    final s = _p?.getString(_k(key));
    if (s == null) { return null; }
    try { return jsonDecode(s); } catch (_) { return null; }
  }
  static JRows? rows(String key) { final v = read(key); return v is List ? [for (final e in v) Map<String, dynamic>.from(e as Map)] : null; }
  static Map<String, dynamic>? row(String key) { final v = read(key); return v is Map ? Map<String, dynamic>.from(v) : null; }
  static Future<void> wipe() async { final p = _p; if (p == null) { return; } for (final k in p.getKeys().where((k) => k.startsWith('c:') || k == 'net:last').toList()) { await p.remove(k); } }
}

/// Is the phone really online? (DNS lookup of the server; checked every few seconds and when the app is opened.)
/// `epoch` goes up every time the connection comes back, which makes every live screen reconnect and refetch.
class Net extends ChangeNotifier {
  Net._();
  static final i = Net._();
  bool online = true, justBack = false;
  int epoch = 0;
  DateTime? lastOnline;
  Timer? _t, _back; DateTime _saved = DateTime.fromMillisecondsSinceEpoch(0); bool _busy = false;

  void start() {
    final s = LocalCache._p?.getString('net:last'); if (s != null) { lastOnline = DateTime.tryParse(s); }
    check(); _t ??= Timer.periodic(const Duration(seconds: 6), (_) => check());
  }

  Future<void> check() async {
    if (_busy) { return; }
    _busy = true;
    bool ok;
    try { final r = await InternetAddress.lookup(Uri.parse(Config.supabaseUrl).host).timeout(const Duration(seconds: 4)); ok = r.isNotEmpty && r.first.rawAddress.isNotEmpty; } catch (_) { ok = false; }
    _busy = false;
    final now = DateTime.now();
    if (ok) { lastOnline = now; if (now.difference(_saved).inSeconds > 60) { _saved = now; LocalCache._p?.setString('net:last', now.toIso8601String()); } }
    if (ok == online) { return; }
    online = ok;
    if (ok) { epoch++; justBack = true; _back?.cancel(); _back = Timer(const Duration(seconds: 4), () { justBack = false; notifyListeners(); }); }
    else { justBack = false; if (lastOnline != null) { LocalCache._p?.setString('net:last', lastOnline!.toIso8601String()); } }
    notifyListeners();
  }
  void suspect() { if (online) { check(); } }
}

/// A realtime table stream that shows the last saved rows first (also with no internet), keeps working while offline,
/// and reconnects + refetches by itself the moment the phone is online again.
Stream<JRows> liveStream(String key, Stream<JRows> Function() build) {
  late final StreamController<JRows> ctl;
  StreamSubscription<dynamic>? sub;
  var seen = 0, hadCache = false;
  void connect() {
    sub?.cancel();
    try {
      sub = build().listen((rows) { LocalCache.write(key, rows); if (!ctl.isClosed) { ctl.add(rows); } },
          onError: (_) { Net.i.suspect(); if (!hadCache && !ctl.isClosed && !Net.i.online) { ctl.add(<Map<String, dynamic>>[]); } });
    } catch (_) {}
  }
  void onNet() { if (Net.i.online && Net.i.epoch != seen) { seen = Net.i.epoch; connect(); } }
  ctl = StreamController<JRows>(
    onListen: () {
      final c = LocalCache.rows(key); hadCache = c != null;
      if (c != null) { ctl.add(c); } else if (!Net.i.online) { ctl.add(<Map<String, dynamic>>[]); }
      seen = Net.i.epoch; Net.i.addListener(onNet); connect();
    },
    onCancel: () { Net.i.removeListener(onNet); sub?.cancel(); },
  );
  return ctl.stream;
}

/// One-off query: online -> fetch (and remember); offline or failed -> the last saved answer.
/// Network first (up to 15 s), the saved copy only when offline or failing.
/// [fast] = saved copy first: if a saved copy exists it is returned at once (screens open instantly) while the fresh data loads in the
/// background; [onFresh] is called when the fresh data differs, so the screen can replace what it showed.
Future<JRows> cachedRows(String key, Future<JRows> Function() fetch, {bool fast = false, void Function(JRows fresh)? onFresh}) async {
  final c = LocalCache.rows(key);
  if (!Net.i.online && c != null) { return c; }
  final f = fetch().timeout(const Duration(seconds: 15)).then((r) { LocalCache.write(key, r); return r; });
  if (fast && c != null) {
    unawaited(f.then((r) { if (jsonEncode(r) != jsonEncode(c)) { onFresh?.call(r); } }).catchError((_) {}));
    return c;
  }
  try { return await f; } catch (e) { if (c != null) { return c; } rethrow; }
}

Future<Map<String, dynamic>?> cachedRow(String key, Future<Map<String, dynamic>?> Function() fetch, {bool fast = false, void Function(Map<String, dynamic> fresh)? onFresh}) async {
  final c = LocalCache.row(key);
  if (!Net.i.online && c != null) { return c; }
  final f = fetch().timeout(const Duration(seconds: 15));
  if (fast && c != null) {
    unawaited(f.then((r) { if (r != null) { LocalCache.write(key, r); if (jsonEncode(r) != jsonEncode(c)) { onFresh?.call(r); } } }).catchError((_) {}));
    return c;
  }
  try {
    final r = await f;
    if (r == null && c != null && sb.auth.currentSession == null) { return c; }   // signed in from memory, session not restored yet
    LocalCache.write(key, r); return r;
  } catch (e) { if (c != null) { return c; } rethrow; }
}

/// Open a screen, but never twice from a double tap or a tap while the first one is still opening.
DateTime _lastPush = DateTime(2000);
Future<T?> pushOnce<T>(BuildContext context, Route<T> route) {
  final now = DateTime.now();
  if (now.difference(_lastPush).inMilliseconds < 900) { return Future.value(null); }
  _lastPush = now;
  return Navigator.push<T>(context, route);
}

/// Run an async action once at a time per [key] (ignores taps while it is still running).
final _running = <String>{};
Future<void> once(String key, Future<void> Function() action) async {
  if (!_running.add(key)) { return; }
  try { await action(); } finally { _running.remove(key); }
}

/// Sign out for real: forget the saved identity and the saved data, even with no internet.
Future<void> appSignOut() async {
  await Identity.clear(); await LocalCache.wipe(); await ImgCache.wipe();
  try { await sb.auth.signOut(scope: SignOutScope.local); } catch (_) {}
}
