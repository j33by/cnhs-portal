import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import 'class_common.dart';

/// Term grades for the class (0-100). Release sends them to students and notifies parents.
class GradesTab extends StatefulWidget {
  final String sectionId, subjectId; final int initialTerm;
  const GradesTab({super.key, required this.sectionId, required this.subjectId, this.initialTerm = 1});
  @override State<GradesTab> createState() => _GradesState();
}

class _GradesState extends State<GradesTab> {
  late int term = widget.initialTerm;
  Rows studs = [];
  final ctl = <String, TextEditingController>{};
  bool released = false, loading = true;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { for (final c in ctl.values) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final yid = await currentYearId();
      final r = await Future.wait<Rows>([
        loadStudents(widget.sectionId),
        sb.from('grades').select('student_id,grade,released').match({'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'school_year_id': yid, 'term': term}),
      ]);
      studs = r[0];
      final g = {for (final x in r[1]) x['student_id'] as String: x};
      released = r[1].any((x) => x['released'] == true);
      for (final c in ctl.values) { c.dispose(); }
      ctl.clear();
      for (final s in studs) { final v = g[s['id']]?['grade']; ctl[s['id'] as String] = TextEditingController(text: v == null ? '' : fmtNum(v as num)); }
    } catch (e) { toastError(e); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final list = <Map<String, dynamic>>[];
    for (final s in studs) {
      final t = ctl[s['id']]!.text.trim();
      if (t.isEmpty) { list.add({'student_id': s['id'], 'grade': null}); continue; }
      final v = double.tryParse(t);
      if (v == null || v < 0 || v > 100) { toast('Grades must be numbers from 0 to 100. Check ${s['last_name']}.'); return; }
      list.add({'student_id': s['id'], 'grade': v});
    }
    try { await Api.post('/api/grades', {'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'term': term, 'grades': list}); toast('Grades saved'); await _load(); } catch (e) { toastError(e); }
  }

  Future<void> _release() async {
    try { await Api.post('/api/grades/release', {'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'term': term, 'released': !released}); toast(released ? 'Grades hidden from students' : 'Released. Students and parents were notified.'); await _load(); } catch (e) { toastError(e); }
  }

  @override
  Widget build(BuildContext c) => Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          DropdownButton<int>(value: term, items: [for (var t = 1; t <= 4; t++) DropdownMenuItem(value: t, child: Text('Term $t'))], onChanged: (v) { if (v != null) { setState(() => term = v); _load(); } }),
          const SizedBox(width: 8), Chip(label: Text(released ? 'Released' : 'Not released'), backgroundColor: released ? Colors.green.shade100 : Colors.grey.shade300),
        ])),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : studs.isEmpty ? const Center(child: Text('No students in this section yet'))
            : ListView(children: [for (final s in studs) ListTile(title: Text('${s['last_name']}, ${s['first_name']}'), subtitle: Text('${s['student_no']}'),
                trailing: SizedBox(width: 80, child: TextField(controller: ctl[s['id']], enabled: !released, keyboardType: const TextInputType.numberWithOptions(decimal: true), textAlign: TextAlign.center, decoration: const InputDecoration(hintText: '—'))))])),
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: released || studs.isEmpty ? null : _save, child: const Text('Save grades'))), const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: studs.isEmpty ? null : _release, child: Text(released ? 'Unrelease' : 'Release & notify'))),
        ])),
      ]);
}
