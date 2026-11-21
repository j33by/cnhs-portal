import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'offline.dart';

/// Subject and teacher names, loaded once and kept live, so screens can show names without re-querying on every rebuild.
class Lookup extends ChangeNotifier {
  Lookup._();
  static final i = Lookup._();

  final subjects = <String, String>{};
  final teachers = <String, String>{};
  StreamSubscription<dynamic>? _sub;
  bool _started = false, _refreshing = false;
  final _missed = <String>{};

  void start() {
    if (_started) return;
    _started = true;
    refreshTeachers();
    _sub = liveStream('subjects', () => sb.from('subjects').stream(primaryKey: ['id'])).listen((rows) {
      subjects..clear()..addAll({for (final r in rows) r['id'] as String: '${r['name']}'});
      notifyListeners();
    }, onError: (_) {});
  }

  void stop() {
    _sub?.cancel(); _sub = null; _started = false;
    subjects.clear(); teachers.clear(); _missed.clear();
  }

  Future<void> refreshTeachers() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final r = await cachedRows('teacher_names', () => sb.from('teacher_names').select('id,first_name,last_name'), fast: true);
      teachers..clear()..addAll({for (final x in r) x['id'] as String: '${x['first_name']} ${x['last_name']}'});
      notifyListeners();
    } catch (_) {}
    _refreshing = false;
  }

  String subject(String? id) => id == null ? 'Class' : (subjects[id] ?? 'Class');

  /// Unknown teacher id (a new teacher joined): fetch once, show "TBA" until it arrives.
  String teacher(String? id) {
    if (id == null) return 'TBA';
    final n = teachers[id];
    if (n != null) return n;
    if (_missed.add(id)) { Future.microtask(refreshTeachers); }
    return 'TBA';
  }
}
