import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../core/teacher_data.dart';
import '../../widgets/colors.dart';
import '../../widgets/status.dart';
import '../../widgets/ui.dart';
import '../../core/offline.dart';

const _reasons = ['Teacher unavailable', 'Meeting / training', 'Holiday / suspension', 'Bad weather', 'School activity', 'Other'];
final _ymd = DateFormat('yyyy-MM-dd');

DateTime _schoolDay(DateTime from) { var d = DateTime(from.year, from.month, from.day); while (d.weekday > 5) { d = d.add(const Duration(days: 1)); } return d; }

/// Tell students (and their parents) there is no class in a subject. Choose the date, the subject and which grade levels / sections
/// are affected, or send to all. Every student of those classes gets a notification and is marked "No class" (not absent).
class NoClassTab extends StatefulWidget {
  const NoClassTab({super.key});
  @override
  State<NoClassTab> createState() => _NoClassTabState();
}

class _NoClassTabState extends State<NoClassTab> {
  late DateTime date = _schoolDay(DateTime.now());
  String? subjectFilter;                              // subject_id, null = every subject
  final picked = <String>{};                          // "sectionId|subjectId"
  String reason = _reasons.first;
  final msg = TextEditingController();
  bool sending = false;
  late final Stream<List<Map<String, dynamic>>> _recent = liveStream('class_cancellations|created_by=${myUid}|o|l', () => sb.from('class_cancellations').stream(primaryKey: ['id']).eq('created_by', myUid).order('cancel_date', ascending: false).limit(20));

  @override
  void dispose() { msg.dispose(); super.dispose(); }

  String _key(Map<String, dynamic> c) => '${c['section_id']}|${c['subject_id']}';
  String _dateWord(DateTime d) {
    final n = DateTime.now(), t = DateTime(n.year, n.month, n.day), diff = DateTime(d.year, d.month, d.day).difference(t).inDays;
    return diff == 0 ? 'today' : diff == 1 ? 'tomorrow' : DateFormat('EEEE').format(d);
  }

  Future<void> _pickDate() async {
    final today = _schoolDay(DateTime.now());
    final d = await showDatePicker(context: context, initialDate: date.isBefore(today) ? today : date, firstDate: today, lastDate: today.add(const Duration(days: 60)),
        selectableDayPredicate: (x) => x.weekday <= 5, helpText: 'Date with no class (Mon - Fri)');
    if (d != null) { setState(() => date = d); }
  }

  Map<String, dynamic>? _slotOn(Map<String, dynamic> cls) {
    for (final s in cls['slots'] as List) { if ((s as Map<String, dynamic>)['day_of_week'] == date.weekday) { return s; } }
    return null;
  }

  Future<void> _send(List<Map<String, dynamic>> chosen) async {
    final students = chosen.fold<int>(0, (a, x) => a + (x['count'] as int));
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      icon: Icon(Icons.event_busy, color: stColor('N')),
      title: const Text('Send no-class alert?'),
      content: Text('${chosen.length} class${chosen.length == 1 ? '' : 'es'} · $students students\nNo class ${_dateWord(date)} (${DateFormat('EEE, MMM d').format(date)}).\n\n'
          'Students and their parents are notified, and every student is marked "No class" for that subject, so nobody is counted absent or present.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.send, size: 18), label: const Text('Send'))],
    ));
    if (ok != true) { return; }
    setState(() => sending = true);
    try {
      final r = await Api.post('/api/no-class', {
        'targets': [for (final x in chosen) {'section_id': x['section_id'], 'subject_id': x['subject_id']}],
        'date': _ymd.format(date), 'reason': reason, 'message': msg.text.trim(),
      });
      final skipped = (r['skipped'] ?? 0) as int;
      toast('Sent to ${r['classes']} class${r['classes'] == 1 ? '' : 'es'}: ${r['students']} students marked "No class", ${r['notified']} people notified.${skipped > 0 ? ' $skipped already announced.' : ''}');
      setState(() { picked.clear(); msg.clear(); });
    } catch (e) { toastError(e); }
    if (mounted) { setState(() => sending = false); }
  }

  Future<void> _resume(Map<String, dynamic> n) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Class is on after all?'),
      content: Text('Cancel the no-class notice for ${n['subject_name']} (${n['label']}) on ${DateFormat('EEE, MMM d').format(DateTime.parse('${n['cancel_date']}'))}? Students and parents are told, and the "No class" marks are removed.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Resume class'))],
    ));
    if (ok != true) { return; }
    try { await Api.delete('/api/no-class/${n['id']}'); toast('Class resumed. Students were told.'); } catch (e) { toastError(e); }
  }

  Widget _intro(BuildContext c) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: LinearGradient(colors: [stColor('N'), Color.lerp(stColor('N'), Colors.black, .3)!], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: const Row(children: [
          Icon(Icons.campaign, color: Colors.white, size: 34), SizedBox(width: 12),
          Expanded(child: Text('Tell students there is no class. They are notified (parents too) and marked "No class" instead of absent.', style: TextStyle(color: Colors.white, height: 1.3))),
        ]),
      );

  Widget _dateRow(BuildContext c) {
    final today = DateTime.now(), isWeekday = today.weekday <= 5, next = _schoolDay(DateTime(today.year, today.month, today.day).add(const Duration(days: 1)));
    bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    return Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (isWeekday) ChoiceChip(label: const Text('Today'), selected: same(date, today), onSelected: (_) => setState(() => date = DateTime(today.year, today.month, today.day))),
      ChoiceChip(label: Text(same(next, today.add(const Duration(days: 1))) ? 'Tomorrow' : DateFormat('EEEE').format(next)), selected: same(date, next), onSelected: (_) => setState(() => date = next)),
      ActionChip(avatar: const Icon(Icons.calendar_month, size: 18), label: Text(!same(date, today) && !same(date, next) ? DateFormat('EEE, MMM d').format(date) : 'Pick a date'), onPressed: _pickDate),
    ]);
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: TeacherData.i, builder: (c, _) {
        final all = TeacherData.i.classes;
        if (!TeacherData.i.loaded) { return const Center(child: CircularProgressIndicator()); }
        if (all.isEmpty) { return const EmptyState(icon: Icons.event_busy, title: 'No classes yet', message: 'Add a class in the Classes tab, then you can announce a no-class day here.'); }
        final subjects = <String, String>{for (final x in all) '${x['subject_id']}': '${x['subject']}'};
        final shown = subjectFilter == null ? all : all.where((x) => '${x['subject_id']}' == subjectFilter).toList();
        picked.removeWhere((k) => !all.any((x) => _key(x) == k));
        final chosen = all.where((x) => picked.contains(_key(x))).toList();
        final students = chosen.fold<int>(0, (a, x) => a + (x['count'] as int));
        final byGrade = <int, List<Map<String, dynamic>>>{};
        for (final x in shown) { (byGrade[x['grade'] as int] ??= []).add(x); }
        final grades = byGrade.keys.toList()..sort();
        final allShownPicked = shown.isNotEmpty && shown.every((x) => picked.contains(_key(x)));
        final subjName = chosen.map((x) => '${x['subject']}').toSet();
        final first = chosen.isEmpty ? null : chosen.first;
        final why = [reason, msg.text.trim()].where((x) => x.isNotEmpty).join(' · ');
        return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 32), children: [
          _intro(c),
          const SizedBox(height: 18), const SectionTitle('1 · Which day?', icon: Icons.event),
          _dateRow(c),
          const SizedBox(height: 18), const SectionTitle('2 · Which subject?', icon: Icons.menu_book),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ChoiceChip(label: const Text('All my subjects'), selected: subjectFilter == null, onSelected: (_) => setState(() => subjectFilter = null)),
            for (final e in subjects.entries) ChoiceChip(label: Text(e.value), selected: subjectFilter == e.key, onSelected: (_) => setState(() => subjectFilter = e.key)),
          ]),
          const SizedBox(height: 18),
          SectionTitle('3 · Who is affected?', icon: Icons.groups, trailing: TextButton.icon(
            onPressed: () => setState(() { if (allShownPicked) { for (final x in shown) { picked.remove(_key(x)); } } else { for (final x in shown) { picked.add(_key(x)); } } }),
            icon: Icon(allShownPicked ? Icons.deselect : Icons.select_all, size: 18), label: Text(allShownPicked ? 'Clear' : 'Send to all'))),
          for (final g in grades) ...[
            Builder(builder: (c) {
              final list = byGrade[g]!, n = list.where((x) => picked.contains(_key(x))).length, all2 = n == list.length;
              return Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                Checkbox(tristate: true, value: all2 ? true : n == 0 ? false : null, onChanged: (_) => setState(() { for (final x in list) { if (all2) { picked.remove(_key(x)); } else { picked.add(_key(x)); } } })),
                Text('Grade $g', style: Theme.of(c).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8), Text('whole grade level', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
              ]));
            }),
            for (final x in byGrade[g]!) Builder(builder: (c) {
              final k = _key(x), on = picked.contains(k), slot = _slotOn(x), col = subjectColor('${x['subject']}');
              return Card(
                elevation: 0, margin: const EdgeInsets.only(bottom: 6), clipBehavior: Clip.antiAlias,
                color: on ? stColor('N').withValues(alpha: .1) : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: on ? stColor('N') : Theme.of(c).dividerColor.withValues(alpha: .4), width: on ? 1.5 : 1)),
                child: InkWell(
                  onTap: () => setState(() { if (on) { picked.remove(k); } else { picked.add(k); } }),
                  child: IntrinsicHeight(child: Row(children: [
                    Container(width: 6, color: col),
                    Checkbox(value: on, onChanged: (v) => setState(() { if (v == true) { picked.add(k); } else { picked.remove(k); } })),
                    Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${x['section']} · ${x['subject']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${x['count']} students · ${slot == null ? 'no class scheduled that day' : '${t12('${slot['start_time']}')} – ${t12('${slot['end_time']}')}'}', style: TextStyle(fontSize: 12.5, color: slot == null ? Colors.orange.shade800 : null)),
                    ]))),
                  ])),
                ),
              );
            }),
          ],
          const SizedBox(height: 14), const SectionTitle('4 · Reason', icon: Icons.edit_note),
          Wrap(spacing: 8, runSpacing: 6, children: [for (final r in _reasons) ChoiceChip(label: Text(r), selected: reason == r, onSelected: (_) => setState(() => reason = r))]),
          const SizedBox(height: 10),
          TextField(controller: msg, maxLength: 140, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Message for students (optional)', hintText: 'e.g. Please read Chapter 3 at home', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          SoftCard(color: stColor('N').withValues(alpha: .08), border: stColor('N').withValues(alpha: .35), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: stColor('N').withValues(alpha: .18), child: Icon(Icons.event_busy, color: stColor('N'))), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Preview', style: TextStyle(fontSize: 11.5, color: Theme.of(c).hintColor)),
              Text(subjName.length == 1 ? 'No ${subjName.first} class' : 'No class', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${first == null ? 'Grade · Section' : 'Grade ${first['grade']} · ${first['section']}'}: no class ${_dateWord(date)} (${DateFormat('EEE, MMM d').format(date)}).${why.isEmpty ? '' : ' $why.'} You will not be marked absent.', style: const TextStyle(fontSize: 13)),
            ])),
          ])),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: stColor('N'), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: chosen.isEmpty || sending ? null : () => _send(chosen),
            icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
            label: Text(chosen.isEmpty ? 'Choose at least one class' : 'Send to ${chosen.length} class${chosen.length == 1 ? '' : 'es'} · $students students'),
          ),
          const SizedBox(height: 26), const SectionTitle('Recent no-class notices', icon: Icons.history),
          StreamBuilder<List<Map<String, dynamic>>>(stream: _recent, builder: (c, s) {
            final rows = s.data ?? [], todayKey = _ymd.format(DateTime.now());
            if (rows.isEmpty) { return const SoftCard(child: Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Nothing sent yet')))); }
            return Column(children: [for (final n in rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: SoftCard(child: Row(children: [
              CircleAvatar(backgroundColor: stColor('N').withValues(alpha: .15), child: Icon(Icons.event_busy, color: stColor('N'))), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n['subject_name']} · ${n['label']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${DateFormat('EEE, MMM d').format(DateTime.parse('${n['cancel_date']}'))}${n['reason'] != null ? ' · ${n['reason']}' : ''} · ${n['students'] ?? 0} students', style: const TextStyle(fontSize: 12.5)),
              ])),
              if ('${n['cancel_date']}'.compareTo(todayKey) >= 0) TextButton(onPressed: () => _resume(n), child: const Text('Resume class')) else const Pill('Past', Colors.grey),
            ])))]);
          }),
        ])));
      });
}
