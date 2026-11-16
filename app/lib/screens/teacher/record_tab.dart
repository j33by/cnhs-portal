import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/calc.dart';
import '../../core/messenger.dart';
import 'class_common.dart';

/// Class record: columns (quiz, seatwork, project...) x students, weighted percent, copy to term grade.
class RecordTab extends StatefulWidget {
  final String sectionId, subjectId; final int initialTerm;
  const RecordTab({super.key, required this.sectionId, required this.subjectId, this.initialTerm = 1});
  @override State<RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends State<RecordTab> {
  late int term = widget.initialTerm;
  Rows cols = [], studs = [];
  Map<String, Map<String, double>> scores = {};
  Map<String, int> absences = {};
  int free = 10;
  final ctl = <String, TextEditingController>{};
  bool loading = true, tr = true;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { for (final c in ctl.values) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final yid = await currentYearId();
      final base = <String, Object>{'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'school_year_id': yid};
      final r = await Future.wait<Rows>([
        sb.from('record_columns').select().match({...base, 'term': term, 'is_deleted': false}).order('col_date').order('created_at'),
        loadStudents(widget.sectionId),
        sb.from('class_attendance').select('student_id').match({...base, 'status': 'A'}),
        sb.from('class_policy').select().match(base),
      ]);
      cols = r[0]; studs = r[1];
      absences = {};
      for (final a in r[2]) { final k = a['student_id'] as String; absences[k] = (absences[k] ?? 0) + 1; }
      free = r[3].isEmpty ? 10 : r[3].first['free_absences'] as int;
      scores = {};
      if (cols.isNotEmpty) {
        final sc = await sb.from('record_scores').select().inFilter('column_id', cols.map((c) => c['id']).toList());
        for (final s in sc) { (scores[s['column_id'] as String] ??= {})[s['student_id'] as String] = (s['score'] as num).toDouble(); }
      }
      for (final c in ctl.values) { c.dispose(); }
      ctl.clear();
      for (final c in cols) { for (final s in studs) { final v = scores[c['id']]?[s['id']]; ctl['${c['id']}|${s['id']}'] = TextEditingController(text: v == null ? '' : fmtNum(v)); } }
    } catch (e) { toastError(e); }
    if (mounted) setState(() => loading = false);
  }

  double? _pct(String sid) {
    final live = <String, Map<String, double>>{};
    for (final c in cols) { final v = double.tryParse(ctl['${c['id']}|$sid']?.text.trim() ?? ''); if (v != null) { (live[c['id'] as String] ??= {})[sid] = v; } }
    return recPercent(cols, live, sid);
  }

  Future<void> _save() async {
    final changes = <Map<String, dynamic>>[];
    for (final c in cols) {
      for (final s in studs) {
        final t = ctl['${c['id']}|${s['id']}']!.text.trim(); final old = scores[c['id']]?[s['id']];
        if (t.isEmpty) { if (old != null) { changes.add({'column_id': c['id'], 'student_id': s['id'], 'score': null}); } continue; }
        final v = double.tryParse(t);
        if (v == null || v < 0 || v > (c['max_score'] as num)) { toast('Scores must be between 0 and ${fmtNum(c['max_score'] as num)} (${c['title']}). Nothing was saved.'); return; }
        if (old == null || (old - v).abs() > 0.001) { changes.add({'column_id': c['id'], 'student_id': s['id'], 'score': v}); }
      }
    }
    if (changes.isEmpty) { toast('No changes to save'); return; }
    try {
      await Api.put('/api/record/scores', {'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'term': term, 'scores': changes});
      toast('${changes.length} score change(s) saved'); await _load();
    } catch (e) { toastError(e); }
  }

  Future<void> _push() async {
    try {
      final r = await Api.post('/api/record/push-grade', {'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'term': term, 'transmute': tr});
      toast('Copied to Term $term grades (${r['saved']} students)');
    } catch (e) { toastError(e); }
  }

  Future<void> _colDialog([Map<String, dynamic>? col]) async {
    final title = TextEditingController(text: col?['title'] ?? '');
    final max = TextEditingController(text: col == null ? '20' : fmtNum(col['max_score'] as num));
    final w = TextEditingController(text: col == null ? '1' : fmtNum(col['weight'] as num));
    var date = col == null ? DateTime.now() : DateTime.parse(col['col_date'] as String);
    await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (c2, set) => AlertDialog(
      title: Text(col == null ? 'Add column' : 'Edit column'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, children: [for (final t in const ['Quiz', 'Seatwork', 'Project', 'Recitation', 'Performance Task', 'Exam']) ActionChip(label: Text(t), onPressed: () => title.text = t)]),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Column title')),
        ListTile(contentPadding: EdgeInsets.zero, title: Text(ymd.format(date)), trailing: const Icon(Icons.calendar_today), onTap: () async {
          final d = await showDatePicker(context: c2, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d != null) { set(() => date = d); } }),
        TextField(controller: max, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Highest possible score')),
        TextField(controller: w, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (0.1 - 10)')),
      ])),
      actions: [
        if (col != null) TextButton(onPressed: () async { Navigator.pop(c2); try { await Api.delete('/api/record/columns/${col['id']}'); await _load(); } catch (e) { toastError(e); } }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          Navigator.pop(c2);
          final body = <String, dynamic>{'title': title.text, 'col_date': ymd.format(date), 'max_score': double.tryParse(max.text), 'weight': double.tryParse(w.text)};
          try {
            if (col == null) { await Api.post('/api/record/columns', {...body, 'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'term': term}); }
            else { await Api.patch('/api/record/columns/${col['id']}', body); }
            await _load();
          } catch (e) { toastError(e); }
        }, child: const Text('Save')),
      ],
    )));
  }

  Widget _table() => SingleChildScrollView(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
        columnSpacing: 14, headingRowHeight: 64, dataRowMinHeight: 44, dataRowMaxHeight: 48,
        columns: [
          const DataColumn(label: Text('Student')),
          for (final c in cols) DataColumn(label: InkWell(onTap: () => _colDialog(c), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${(c['col_date'] as String).substring(5)} · /${fmtNum(c['max_score'] as num)}${(c['weight'] as num) != 1 ? ' ×${fmtNum(c['weight'] as num)}' : ''}', style: const TextStyle(fontSize: 10))]))),
          const DataColumn(label: Text('Percent')),
          const DataColumn(label: Text('Absences')),
        ],
        rows: [for (final s in studs) DataRow(cells: [
          DataCell(Text('${s['last_name']}, ${s['first_name']}')),
          for (final c in cols) DataCell(SizedBox(width: 60, child: TextField(controller: ctl['${c['id']}|${s['id']}'], keyboardType: const TextInputType.numberWithOptions(decimal: true), textAlign: TextAlign.center, decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: '–'), onChanged: (_) => setState(() {})))),
          DataCell(Text(_pct(s['id'] as String)?.toStringAsFixed(2) ?? '–', style: const TextStyle(fontWeight: FontWeight.bold))),
          DataCell(Row(children: [Text('${absences[s['id']] ?? 0}/$free '), standingChip(absences[s['id']] ?? 0, free)])),
        ])],
      )));

  @override
  Widget build(BuildContext c) => Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          DropdownButton<int>(value: term, items: [for (var t = 1; t <= 4; t++) DropdownMenuItem(value: t, child: Text('Term $t'))], onChanged: (v) { if (v != null) { setState(() => term = v); _load(); } }),
          const Spacer(),
          IconButton(icon: const Icon(Icons.add_box), tooltip: 'Add column', onPressed: cols.length >= 15 ? null : () => _colDialog()),
          FilledButton(onPressed: cols.isEmpty ? null : _save, child: const Text('Save scores')),
        ])),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator())
            : studs.isEmpty ? const Center(child: Text('No students in this section yet'))
            : cols.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No columns yet. Tap the + button to add one, for example "Quiz 1".', textAlign: TextAlign.center)))
            : _table()),
        if (cols.isNotEmpty && studs.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          const Text('Transmute 60→75'), Switch(value: tr, onChanged: (v) => setState(() => tr = v)),
          const Spacer(), OutlinedButton(onPressed: _push, child: Text('Copy to Term $term grades')),
        ])),
      ]);
}
