import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'offline.dart';

/// The teacher's classes, advisories and weekly schedule, loaded once and kept live.
/// The Home and Classes tabs both read from here, so nothing is queried twice and nothing flashes on rebuild.
class TeacherData extends ChangeNotifier {
  TeacherData._();
  static final i = TeacherData._();

  List<Map<String, dynamic>> classes = [];      // subject classes I teach (section + subject), each with its slots
  List<Map<String, dynamic>> advisories = [];   // sections where I am the adviser
  List<Map<String, dynamic>> slots = [];        // every weekly slot with its class details (for the dashboard)
  bool loaded = false;
  String? _uid;
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _debounce;

  void start(String uid) {
    if (_uid == uid) { return; }
    stop();
    _uid = uid;
    reload();
    void on(Stream<dynamic> s) => _subs.add(s.listen((_) => _soon(), onError: (_) {}));
    on(liveStream('section_subjects|teacher_id=${uid}', () => sb.from('section_subjects').stream(primaryKey: ['section_id', 'subject_id']).eq('teacher_id', uid)));
    on(liveStream('schedules|teacher_id=${uid}', () => sb.from('schedules').stream(primaryKey: ['id']).eq('teacher_id', uid)));
    on(liveStream('sections|adviser_id=${uid}', () => sb.from('sections').stream(primaryKey: ['id']).eq('adviser_id', uid)));
  }

  void stop() {
    for (final s in _subs) { s.cancel(); }
    _subs.clear(); _debounce?.cancel();
    classes = []; advisories = []; slots = []; loaded = false; _uid = null;
  }

  void _soon() { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 400), reload); }

  Future<void> reload() async {
    final uid = _uid;
    if (uid == null) { return; }
    try {
      final ss = await cachedRows('td:ss', () => sb.from('section_subjects').select('section_id,subject_id').eq('teacher_id', uid));
      final adv = await cachedRows('td:adv', () => sb.from('sections').select('id').eq('adviser_id', uid));
      final advIds = {for (final x in adv) x['id'] as String};
      final secIds = {...advIds, for (final x in ss) x['section_id'] as String}.toList();
      if (secIds.isEmpty) { classes = []; advisories = []; slots = []; loaded = true; notifyListeners(); return; }
      final subIds = {for (final x in ss) x['subject_id'] as String}.toList();
      final r = await Future.wait<List<Map<String, dynamic>>>([
        cachedRows('td:sec', () => sb.from('sections').select('id,grade_level,name,homeroom,grading_term').inFilter('id', secIds)),
        subIds.isEmpty ? Future.value(<Map<String, dynamic>>[]) : cachedRows('td:sub', () => sb.from('subjects').select('id,code,name').inFilter('id', subIds)),
        cachedRows('td:sched', () => sb.from('schedules').select('id,section_id,subject_id,day_of_week,start_time,end_time,room').eq('teacher_id', uid)),
        cachedRows('td:count', () => sb.from('students').select('section_id').inFilter('section_id', secIds).eq('status', 'enrolled')),
      ]);
      final secs = {for (final x in r[0]) x['id'] as String: x}, subs = {for (final x in r[1]) x['id'] as String: x};
      final count = <String, int>{};
      for (final x in r[3]) { final k = x['section_id'] as String; count[k] = (count[k] ?? 0) + 1; }

      final cl = <Map<String, dynamic>>[];
      for (final x in ss) {
        final sec = secs[x['section_id']], sub = subs[x['subject_id']];
        if (sec == null || sub == null) { continue; }
        cl.add({
          'kind': 'class', 'section_id': x['section_id'], 'subject_id': x['subject_id'], 'grade': sec['grade_level'], 'section': sec['name'], 'room': sec['homeroom'],
          'term': sec['grading_term'] ?? 1, 'subject': sub['name'], 'code': sub['code'], 'count': count[x['section_id']] ?? 0, 'adviser': advIds.contains(x['section_id']),
          'slots': r[2].where((s) => s['section_id'] == x['section_id'] && s['subject_id'] == x['subject_id']).toList(),
        });
      }
      cl.sort((a, b) { final g = (a['grade'] as int).compareTo(b['grade'] as int); if (g != 0) { return g; } final s = '${a['section']}'.compareTo('${b['section']}'); return s != 0 ? s : '${a['subject']}'.compareTo('${b['subject']}'); });

      final ad = <Map<String, dynamic>>[];
      for (final id in advIds) {
        final sec = secs[id];
        if (sec == null) { continue; }
        ad.add({'kind': 'advisory', 'section_id': id, 'grade': sec['grade_level'], 'section': sec['name'], 'room': sec['homeroom'], 'term': sec['grading_term'] ?? 1, 'count': count[id] ?? 0});
      }
      ad.sort((a, b) { final g = (a['grade'] as int).compareTo(b['grade'] as int); return g != 0 ? g : '${a['section']}'.compareTo('${b['section']}'); });

      final sl = <Map<String, dynamic>>[];
      for (final c in cl) { for (final s in c['slots'] as List) { sl.add({...(s as Map<String, dynamic>), 'subject': c['subject'], 'grade': c['grade'], 'section': c['section'], 'adviser': c['adviser'], 'cls': c}); } }

      classes = cl; advisories = ad; slots = sl; loaded = true;
      notifyListeners();
    } catch (_) {
      if (!loaded) { loaded = true; notifyListeners(); }
    }
  }
}
