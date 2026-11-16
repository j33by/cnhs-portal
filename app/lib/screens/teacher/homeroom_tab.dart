import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../widgets/shared.dart';
import 'class_common.dart';

/// Adviser's daily attendance. Shows biometric time in/out and lets the adviser correct or mark manually
/// (a manual mark always wins over the fingerprint terminal).
class HomeroomTab extends StatefulWidget {
  final String sectionId;
  const HomeroomTab({super.key, required this.sectionId});
  @override State<HomeroomTab> createState() => _HomeroomState();
}

class _HomeroomState extends State<HomeroomTab> {
  DateTime date = DateTime.now();
  Rows studs = [];
  final st = <String, String>{}, src = <String, String>{}, tin = <String, String?>{}, tout = <String, String?>{};
  bool loading = true;

  @override void initState() { super.initState(); if (date.weekday > 5) { date = date.subtract(Duration(days: date.weekday - 5)); } _load(); }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final r = await Future.wait<Rows>([loadStudents(widget.sectionId), sb.from('daily_attendance').select().eq('section_id', widget.sectionId).eq('att_date', ymd.format(date))]);
      studs = r[0]; st.clear(); src.clear(); tin.clear(); tout.clear();
      for (final a in r[1]) { final k = a['student_id'] as String; st[k] = a['status'] as String; src[k] = a['source'] as String? ?? ''; tin[k] = a['time_in'] as String?; tout[k] = a['time_out'] as String?; }
    } catch (e) { toastError(e); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(DateTime.now().year - 1), lastDate: DateTime.now(), selectableDayPredicate: (x) => x.weekday <= 5);
    if (d != null) { setState(() => date = d); _load(); }
  }

  Future<void> _save() async {
    final entries = [for (final s in studs) if ((st[s['id']] ?? '').isNotEmpty) {'student_id': s['id'], 'status': st[s['id']]}];
    try { final r = await Api.post('/api/attendance/homeroom', {'section_id': widget.sectionId, 'date': ymd.format(date), 'entries': entries}); toast('Attendance saved (${r['saved']} students)'); await _load(); } catch (e) { toastError(e); }
  }

  @override
  Widget build(BuildContext c) => Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.calendar_today, size: 16), label: Text(ymd.format(date))),
          const Spacer(),
          TextButton(onPressed: () => setState(() { for (final s in studs) { if ((st[s['id']] ?? '').isEmpty) { st[s['id'] as String] = 'P'; } } }), child: const Text('Mark rest present')),
          FilledButton(onPressed: studs.isEmpty ? null : _save, child: const Text('Save')),
        ])),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : studs.isEmpty ? const Center(child: Text('No students in this section yet'))
            : ListView(children: [for (final s in studs) ListTile(
                title: Text('${s['last_name']}, ${s['first_name']}'),
                subtitle: Text(src[s['id']] == null ? 'Not recorded' : '${src[s['id']] == 'manual' ? 'Marked by adviser' : 'Fingerprint'}  ·  In ${t12(tin[s['id']])}  Out ${t12(tout[s['id']])}', style: const TextStyle(fontSize: 12)),
                trailing: SegmentedButton<String>(
                  showSelectedIcon: false, emptySelectionAllowed: true, style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [ButtonSegment(value: 'P', label: Text('P')), ButtonSegment(value: 'A', label: Text('A')), ButtonSegment(value: 'L', label: Text('L')), ButtonSegment(value: 'E', label: Text('E'))],
                  selected: (st[s['id']] ?? '').isEmpty ? <String>{} : {st[s['id']]!},
                  onSelectionChanged: (v) => setState(() { st[s['id'] as String] = v.isEmpty ? '' : v.first; }),
                ))])),
      ]);
}
