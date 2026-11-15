import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../widgets/shared.dart';
import 'add_class.dart';
import 'attendance_tab.dart';
import 'class_common.dart';
import 'class_schedule_tab.dart';
import 'class_students_tab.dart';
import 'grades_tab.dart';
import 'record_tab.dart';

String classKey(Map<String, dynamic> c) => '${c['section_id']}|${c['subject_id']}';
String classTitle(Map<String, dynamic> c) => '${c['subject']} · Grade ${c['grade']} ${c['section']}';

/// "Mon · Wed · Fri  7:30 AM–8:30 AM  ·  Room 12", one line per distinct time.
String scheduleSummary(List<dynamic> slots) {
  if (slots.isEmpty) return 'No schedule yet';
  final groups = <String, List<int>>{};
  for (final s in slots) { (groups['${s['start_time']}|${s['end_time']}|${s['room'] ?? ''}'] ??= []).add(s['day_of_week'] as int); }
  final keys = groups.keys.toList()..sort();
  return keys.map((k) {
    final p = k.split('|'); final d = groups[k]!..sort();
    return '${d.map((x) => kDays[x].substring(0, 3)).join(' · ')}  ${t12(p[0])}–${t12(p[1])}${p[2].isEmpty ? '' : '  ·  ${p[2]}'}';
  }).join('\n');
}

/// Stop teaching a class (grades, attendance and class record stay saved).
Future<bool> removeClass(BuildContext c, String sectionId, String subjectId, String label) async {
  final ok = await showDialog<bool>(context: c, builder: (c2) => AlertDialog(
    title: const Text('Remove this class?'),
    content: Text('$label will leave your classes and its schedule will be deleted. Grades, attendance and class record data are kept.'),
    actions: [TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('Remove'))]));
  if (ok != true) return false;
  try { await Api.delete('/api/classes/$sectionId/$subjectId'); toast('Class removed'); return true; } catch (e) { toast('$e'); return false; }
}

/// The teacher's classes. Phones: a list that opens each class. Desktop / tablets: list on the left, class on the right.
class MyClasses extends StatefulWidget {
  final String teacherId;
  const MyClasses({super.key, required this.teacherId});
  @override
  State<MyClasses> createState() => _MyClassesState();
}

class _MyClassesState extends State<MyClasses> {
  List<Map<String, dynamic>>? items;
  Map<String, dynamic>? selected;
  StreamSubscription<dynamic>? _a, _b;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reload();
    _a = sb.from('section_subjects').stream(primaryKey: ['section_id', 'subject_id']).eq('teacher_id', widget.teacherId).listen((_) => _soon(), onError: (_) {});
    _b = sb.from('schedules').stream(primaryKey: ['id']).eq('teacher_id', widget.teacherId).listen((_) => _soon(), onError: (_) {});
  }
  @override
  void dispose() { _a?.cancel(); _b?.cancel(); _debounce?.cancel(); super.dispose(); }
  void _soon() { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 400), _reload); }

  Future<void> _reload() async {
    try {
      final ss = await sb.from('section_subjects').select('section_id,subject_id').eq('teacher_id', widget.teacherId);
      if (ss.isEmpty) { if (mounted) setState(() { items = []; selected = null; }); return; }
      final secIds = {for (final x in ss) x['section_id'] as String}.toList(), subIds = {for (final x in ss) x['subject_id'] as String}.toList();
      final r = await Future.wait<Rows>([
        sb.from('sections').select('id,grade_level,name,homeroom,grading_term').inFilter('id', secIds),
        sb.from('subjects').select('id,code,name').inFilter('id', subIds),
        sb.from('schedules').select('section_id,subject_id,day_of_week,start_time,end_time,room').eq('teacher_id', widget.teacherId),
        sb.from('students').select('section_id').inFilter('section_id', secIds).eq('status', 'enrolled'),
      ]);
      final secs = {for (final x in r[0]) x['id']: x}, subs = {for (final x in r[1]) x['id']: x};
      final count = <String, int>{};
      for (final x in r[3]) { final k = x['section_id'] as String; count[k] = (count[k] ?? 0) + 1; }
      final out = <Map<String, dynamic>>[];
      for (final x in ss) {
        final sec = secs[x['section_id']], sub = subs[x['subject_id']];
        if (sec == null || sub == null) continue;
        out.add({
          'section_id': x['section_id'], 'subject_id': x['subject_id'], 'grade': sec['grade_level'], 'section': sec['name'], 'room': sec['homeroom'],
          'term': sec['grading_term'] ?? 1, 'subject': sub['name'], 'code': sub['code'], 'count': count[x['section_id']] ?? 0,
          'slots': r[2].where((s) => s['section_id'] == x['section_id'] && s['subject_id'] == x['subject_id']).toList(),
        });
      }
      out.sort((a, b) { final g = (a['grade'] as int).compareTo(b['grade'] as int); if (g != 0) return g; final s = '${a['section']}'.compareTo('${b['section']}'); return s != 0 ? s : '${a['subject']}'.compareTo('${b['subject']}'); });
      if (!mounted) return;
      setState(() { items = out; if (selected != null && !out.any((o) => classKey(o) == classKey(selected!))) { selected = null; } });
    } catch (e) { toast('$e'); if (mounted) setState(() => items ??= []); }
  }

  void _open(Map<String, dynamic> cls, bool wide) {
    if (wide) { setState(() => selected = cls); return; }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ClassScreen.from(cls)));
  }

  Future<void> _add(bool wide) async {
    final r = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => const AddClassScreen()));
    if (r == null) return;
    await _reload();
    for (final x in items ?? <Map<String, dynamic>>[]) {
      if (x['section_id'] == r['section_id'] && x['subject_id'] == r['subject_id']) { if (mounted) { _open(x, wide); } break; }
    }
  }

  Widget _tile(Map<String, dynamic> x, bool wide) {
    final sel = wide && selected != null && classKey(selected!) == classKey(x);
    final room = (x['room'] ?? '').toString();
    return Card(
      color: sel ? Theme.of(context).colorScheme.primaryContainer : null,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(child: Text('${x['grade']}')),
        title: Text('${x['subject']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${x['section']}${room.isEmpty ? '' : ' · Room $room'} · ${x['count']} student${x['count'] == 1 ? '' : 's'}'),
          const SizedBox(height: 2), Text(scheduleSummary(x['slots'] as List), style: const TextStyle(fontSize: 12)),
        ]),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async { if (v == 'remove' && await removeClass(context, x['section_id'], x['subject_id'], classTitle(x))) { await _reload(); } },
          itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove class'))],
        ),
        onTap: () => _open(x, wide),
      ),
    );
  }

  Widget _list(bool wide) {
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items!.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.menu_book, size: 64), const SizedBox(height: 12),
        Text('No classes yet', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8),
        const Text('Add a class to choose the grade level, subject, section and schedule you teach. You will then see its students and can take attendance, keep a class record and enter grades.', textAlign: TextAlign.center),
        const SizedBox(height: 16), FilledButton.icon(onPressed: () => _add(wide), icon: const Icon(Icons.add), label: const Text('Add class')),
      ])));
    }
    return RefreshIndicator(onRefresh: _reload, child: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
      if (wide) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 12, 4), child: Row(children: [
        Text('My classes (${items!.length})', style: Theme.of(context).textTheme.titleMedium), const Spacer(),
        FilledButton.icon(onPressed: () => _add(wide), icon: const Icon(Icons.add), label: const Text('Add class')),
      ])),
      for (final x in items!) _tile(x, wide),
    ]));
  }

  @override
  Widget build(BuildContext c) => LayoutBuilder(builder: (c, box) {
        final wide = box.maxWidth >= 900;
        return Scaffold(
          floatingActionButton: wide || (items?.isEmpty ?? true) ? null : FloatingActionButton.extended(onPressed: () => _add(wide), icon: const Icon(Icons.add), label: const Text('Add class')),
          body: wide
              ? Row(children: [
                  SizedBox(width: 400, child: _list(wide)), const VerticalDivider(width: 1),
                  Expanded(child: selected == null
                      ? const Center(child: Text('Select a class to see its students, attendance, class record and grades'))
                      : ClassScreen.from(selected!, key: ValueKey(classKey(selected!)), onRemoved: () { setState(() => selected = null); _reload(); })),
                ])
              : _list(wide),
        );
      });
}

class ClassScreen extends StatelessWidget {
  final String sectionId, subjectId, title; final int term; final VoidCallback? onRemoved;
  const ClassScreen({super.key, required this.sectionId, required this.subjectId, required this.title, required this.term, this.onRemoved});
  ClassScreen.from(Map<String, dynamic> c, {super.key, this.onRemoved})
      : sectionId = c['section_id'] as String, subjectId = c['subject_id'] as String, title = classTitle(c), term = (c['term'] as int?) ?? 1;

  @override
  Widget build(BuildContext c) => DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title, style: const TextStyle(fontSize: 16)),
            actions: [PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'remove' && await removeClass(c, sectionId, subjectId, title)) { if (onRemoved != null) { onRemoved!(); } else if (c.mounted) { Navigator.pop(c); } }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove class'))],
            )],
            bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Students'), Tab(text: 'Class record'), Tab(text: 'Attendance'), Tab(text: 'Grades'), Tab(text: 'Schedule')]),
          ),
          body: TabBarView(children: [
            ClassStudentsTab(sectionId: sectionId, subjectId: subjectId),
            RecordTab(sectionId: sectionId, subjectId: subjectId, initialTerm: term),
            AttendanceTab(sectionId: sectionId, subjectId: subjectId),
            GradesTab(sectionId: sectionId, subjectId: subjectId, initialTerm: term),
            ClassScheduleTab(sectionId: sectionId, subjectId: subjectId),
          ]),
        ),
      );
}
