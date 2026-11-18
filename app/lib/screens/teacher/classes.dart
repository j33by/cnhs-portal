import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../widgets/keep_alive.dart';
import '../../widgets/shared.dart';
import '../../core/teacher_data.dart';
import '../../widgets/colors.dart';
import 'add_class.dart';
import 'advisory.dart';
import 'attendance_tab.dart';
import 'my_subjects.dart';
import 'class_common.dart';
import 'class_schedule_tab.dart';
import 'class_students_tab.dart';
import 'grades_tab.dart';
import 'homeroom_tab.dart';
import 'record_tab.dart';

String classKey(Map<String, dynamic> c) => c['kind'] == 'advisory' ? '${c['section_id']}|advisory' : '${c['section_id']}|${c['subject_id']}';
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
  try { await Api.delete('/api/classes/$sectionId/$subjectId'); toast('Class removed'); return true; } catch (e) { toastError(e); return false; }
}

/// Classes tab: my advisory sections (amber) and my subject classes together.
/// Phones: one list that opens each card. Desktop / tablets: list on the left, the open class on the right.
class MyClasses extends StatefulWidget {
  final String teacherId;
  const MyClasses({super.key, required this.teacherId});
  @override
  State<MyClasses> createState() => _MyClassesState();
}

class _MyClassesState extends State<MyClasses> {
  Map<String, dynamic>? selected;

  Map<String, dynamic> _sectionMap(Map<String, dynamic> a) => {'id': a['section_id'], 'grade_level': a['grade'], 'name': a['section']};

  Widget _screenFor(Map<String, dynamic> x, {Key? key, VoidCallback? onRemoved}) => x['kind'] == 'advisory'
      ? SectionScreen(key: key, section: _sectionMap(x))
      : ClassScreen.from(x, key: key, onRemoved: onRemoved);

  void _open(Map<String, dynamic> x, bool wide) {
    if (wide) { setState(() => selected = x); return; }
    Navigator.push(context, MaterialPageRoute(builder: (_) => _screenFor(x)));
  }

  Future<void> _add(bool wide) async {
    final r = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => const AddClassScreen()));
    if (r == null) { return; }
    await TeacherData.i.reload();
    final list = r['advisory_only'] == true ? TeacherData.i.advisories : TeacherData.i.classes;
    for (final x in list) {
      if (x['section_id'] == r['section_id'] && (r['advisory_only'] == true || x['subject_id'] == r['subject_id'])) { if (mounted) { _open(x, wide); } break; }
    }
  }

  Widget _badge(String text, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: .6)));

  // Advisory card: amber, section first.
  Widget _advisoryCard(Map<String, dynamic> a, bool wide) {
    final sel = wide && selected != null && classKey(selected!) == classKey(a);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final room = (a['room'] ?? '').toString();
    return Card(
      elevation: 0, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: dark ? advisoryColor.shade900.withValues(alpha: .3) : advisoryColor.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: sel ? Theme.of(context).colorScheme.primary : advisoryColor.shade600, width: sel ? 2.5 : 1.3)),
      child: InkWell(borderRadius: BorderRadius.circular(18), onTap: () => _open(a, wide), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        CircleAvatar(radius: 26, backgroundColor: advisoryColor.shade700, child: const Icon(Icons.star_rounded, color: Colors.white, size: 28)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_badge('ADVISORY', advisoryColor.shade800)]),
          const SizedBox(height: 4),
          Text('Grade ${a['grade']} · ${a['section']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Homeroom${room.isEmpty ? '' : ' · $room'} · ${a['count']} student${a['count'] == 1 ? '' : 's'}', style: const TextStyle(fontSize: 13)),
        ])),
        const Icon(Icons.chevron_right),
      ]))),
    );
  }

  // Subject class card: section first, subject beneath, accent colour by subject.
  Widget _classCard(Map<String, dynamic> x, bool wide) {
    final sel = wide && selected != null && classKey(selected!) == classKey(x);
    final col = subjectColor('${x['subject']}'), room = (x['room'] ?? '').toString();
    return Card(
      elevation: 0, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: sel ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor.withValues(alpha: .5), width: sel ? 2.5 : 1)),
      child: InkWell(onTap: () => _open(x, wide), child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 7, color: col),
        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 4, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Grade ${x['grade']} · ${x['section']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            if (x['adviser'] == true) Padding(padding: const EdgeInsets.only(right: 4), child: Tooltip(message: 'You are the adviser of this section', child: Icon(Icons.star_rounded, color: advisoryColor.shade700, size: 22))),
          ]),
          const SizedBox(height: 4),
          Row(children: [Icon(Icons.menu_book, size: 16, color: col), const SizedBox(width: 6), Expanded(child: Text('${x['subject']}', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: col)))]),
          const SizedBox(height: 4),
          Text('${x['count']} student${x['count'] == 1 ? '' : 's'}${room.isEmpty ? '' : ' · Room $room'}', style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(scheduleSummary(x['slots'] as List), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ]))),
        PopupMenuButton<String>(
          onSelected: (v) async { if (v == 'remove') { await removeClass(context, x['section_id'], x['subject_id'], classTitle(x)); } },
          itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove class'))],
        ),
      ]))),
    );
  }

  void _openSubjects() => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('My subjects')), body: const MySubjects())));
  Widget _subjectsButton() => FilledButton.tonalIcon(
        onPressed: _openSubjects, icon: const Icon(Icons.library_books_outlined, size: 18), label: const Text('My subjects'),
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)));

  Widget _heading(String t, IconData i) => Padding(padding: const EdgeInsets.fromLTRB(18, 14, 12, 2), child: Row(children: [Icon(i, size: 18), const SizedBox(width: 6), Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))]));

  Widget _list(bool wide) {
    final d = TeacherData.i;
    if (!d.loaded) { return const Center(child: CircularProgressIndicator()); }
    if (d.classes.isEmpty && d.advisories.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.menu_book, size: 64), const SizedBox(height: 12),
        Text('No classes yet', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8),
        const Text('Add a class to choose the grade level, section, subject and schedule you teach. If you are the adviser of a section, tick "I\'m the adviser" and it appears here in amber.', textAlign: TextAlign.center),
        const SizedBox(height: 16), _subjectsButton(), const SizedBox(height: 10), FilledButton.icon(onPressed: () => _add(wide), icon: const Icon(Icons.add), label: const Text('Add class')),
      ])));
    }
    return RefreshIndicator(onRefresh: TeacherData.i.reload, child: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
      if (wide) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 12, 0), child: Row(children: [
        Text('Classes', style: Theme.of(context).textTheme.titleMedium), const Spacer(),
        _subjectsButton(), const SizedBox(width: 8), FilledButton.icon(onPressed: () => _add(wide), icon: const Icon(Icons.add), label: const Text('Add class')),
      ])),
      if (d.advisories.isNotEmpty) ...[_heading('My advisory', Icons.star_rounded), for (final a in d.advisories) _advisoryCard(a, wide)],
      if (d.classes.isNotEmpty) ...[_heading('Subject classes', Icons.menu_book), for (final x in d.classes) _classCard(x, wide)],
    ]));
  }

  @override
  Widget build(BuildContext c) => LayoutBuilder(builder: (c, box) {
        final wide = box.maxWidth >= 900;
        return ListenableBuilder(listenable: TeacherData.i, builder: (c, _) {
          final d = TeacherData.i;
          if (selected != null && ![...d.classes, ...d.advisories].any((o) => classKey(o) == classKey(selected!))) { selected = null; }
          final empty = d.classes.isEmpty && d.advisories.isEmpty;
          return Scaffold(
            floatingActionButton: wide || empty ? null : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [_subjectsButton(), const SizedBox(height: 10), FloatingActionButton.extended(onPressed: () => _add(wide), icon: const Icon(Icons.add), label: const Text('Add class'))]),
            body: wide
                ? Row(children: [
                    SizedBox(width: 400, child: _list(wide)), const VerticalDivider(width: 1),
                    Expanded(child: selected == null
                        ? const Center(child: Text('Select a card to open it'))
                        : _screenFor(selected!, key: ValueKey(classKey(selected!)), onRemoved: () => setState(() => selected = null))),
                  ])
                : _list(wide),
          );
        });
      });
}

class ClassScreen extends StatelessWidget {
  final String sectionId, subjectId, title; final int term; final bool isAdviser; final VoidCallback? onRemoved;
  const ClassScreen({super.key, required this.sectionId, required this.subjectId, required this.title, required this.term, this.isAdviser = false, this.onRemoved});
  ClassScreen.from(Map<String, dynamic> c, {super.key, this.onRemoved})
      : sectionId = c['section_id'] as String, subjectId = c['subject_id'] as String, title = classTitle(c), term = (c['term'] as int?) ?? 1, isAdviser = c['adviser'] == true;

  @override
  Widget build(BuildContext c) => DefaultTabController(
        length: isAdviser ? 6 : 5,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title, style: const TextStyle(fontSize: 16)),
            actions: [PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'remove' && await removeClass(c, sectionId, subjectId, title)) { if (onRemoved != null) { onRemoved!(); } else if (c.mounted) { Navigator.pop(c); } }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove class'))],
            )],
            bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              const Tab(text: 'Students'), const Tab(text: 'Class record'), const Tab(text: 'Attendance'), const Tab(text: 'Grades'), const Tab(text: 'Schedule'),
              if (isAdviser) const Tab(icon: Icon(Icons.star_rounded, size: 18), text: 'Homeroom'),
            ]),
          ),
          body: TabBarView(children: [
            KeepTabAlive(child: ClassStudentsTab(sectionId: sectionId, subjectId: subjectId, isAdviser: isAdviser)),
            KeepTabAlive(child: RecordTab(sectionId: sectionId, subjectId: subjectId, initialTerm: term)),
            KeepTabAlive(child: AttendanceTab(sectionId: sectionId, subjectId: subjectId)),
            KeepTabAlive(child: GradesTab(sectionId: sectionId, subjectId: subjectId, initialTerm: term)),
            KeepTabAlive(child: ClassScheduleTab(sectionId: sectionId, subjectId: subjectId)),
            if (isAdviser) KeepTabAlive(child: HomeroomTab(sectionId: sectionId)),
          ]),
        ),
      );
}
