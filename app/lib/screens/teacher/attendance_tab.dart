import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/calc.dart';
import '../../core/messenger.dart';
import '../../widgets/shared.dart';
import 'class_common.dart';

/// Subject attendance: one column per date, tap a box to cycle P -> A -> L -> E. Includes the absence rule + standing.
class AttendanceTab extends StatefulWidget {
  final String sectionId, subjectId;
  const AttendanceTab({super.key, required this.sectionId, required this.subjectId});
  @override State<AttendanceTab> createState() => _AttState();
}

class _AttState extends State<AttendanceTab> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Rows studs = [];
  List<String> dates = [];
  final st = <String, String>{}, rm = <String, String>{};      // key: "date|studentId"
  Map<String, int> abs = {};
  int free = 10; bool apply = false, loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final yid = await currentYearId();
      final base = <String, Object>{'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'school_year_id': yid};
      final from = ymd.format(month), to = ymd.format(DateTime(month.year, month.month + 1, 0));
      final r = await Future.wait<Rows>([
        loadStudents(widget.sectionId),
        sb.from('class_attendance').select('student_id,att_date,status,remarks').match(base).gte('att_date', from).lte('att_date', to).order('att_date'),
        sb.from('class_attendance').select('student_id').match({...base, 'status': 'A'}),
        sb.from('class_policy').select().match(base),
      ]);
      studs = r[0]; st.clear(); rm.clear();
      final ds = <String>{};
      for (final a in r[1]) { final d = a['att_date'] as String; ds.add(d); st['$d|${a['student_id']}'] = a['status'] as String; if (a['remarks'] != null) { rm['$d|${a['student_id']}'] = a['remarks'] as String; } }
      dates = ds.toList()..sort();
      abs = {};
      for (final a in r[2]) { final k = a['student_id'] as String; abs[k] = (abs[k] ?? 0) + 1; }
      free = r[3].isEmpty ? 10 : r[3].first['free_absences'] as int;
      apply = r[3].isEmpty ? false : r[3].first['apply_to_record'] as bool;
    } catch (e) { toast('$e'); }
    if (mounted) setState(() => loading = false);
  }

  static const _cycle = {'': 'P', 'P': 'A', 'A': 'L', 'L': 'E', 'E': 'P'};

  Future<void> _addDate() async {
    final today = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: today.weekday > 5 ? today.subtract(Duration(days: today.weekday - 5)) : today,
        firstDate: DateTime(today.year - 1), lastDate: today, selectableDayPredicate: (x) => x.weekday <= 5, helpText: 'Class date (Mon - Fri)');
    if (d == null) return;
    final k = ymd.format(d);
    if (dates.contains(k)) { toast('That date already has a column'); return; }
    setState(() { dates = [...dates, k]..sort(); });
  }

  Future<void> _removeDate(String d) async {
    final saved = studs.any((s) => st['$d|${s['id']}'] != null) ;
    try {
      if (saved) { await Api.delete('/api/class-attendance?section_id=${widget.sectionId}&subject_id=${widget.subjectId}&date=$d'); await _load(); }
      else { setState(() => dates = dates.where((x) => x != d).toList()); }
    } catch (e) { toast('$e'); }
  }

  Future<void> _save() async {
    final payload = [for (final d in dates) {'date': d, 'entries': [for (final s in studs) if ((st['$d|${s['id']}'] ?? '').isNotEmpty) {'student_id': s['id'], 'status': st['$d|${s['id']}'], 'remarks': rm['$d|${s['id']}'] ?? ''}]}];
    try {
      final r = await Api.post('/api/class-attendance', {'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'dates': payload});
      toast('Attendance saved (${r['saved']} marks)${(r['dropped'] ?? 0) > 0 ? '. ${r['dropped']} student(s) exceeded the absence limit and were marked Dropped.' : ''}');
      await _load();
    } catch (e) { toast('$e'); }
  }

  Future<void> _remark(String d, Map<String, dynamic> s) async {
    final t = TextEditingController(text: rm['$d|${s['id']}'] ?? '');
    final v = await showDialog<String>(context: context, builder: (c2) => AlertDialog(title: Text('Remark · ${s['first_name']}'), content: TextField(controller: t, maxLength: 120, decoration: const InputDecoration(hintText: 'Optional note for this day')),
        actions: [TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c2, t.text.trim()), child: const Text('Done'))]));
    if (v != null) { setState(() { rm['$d|${s['id']}'] = v; }); }
  }

  Future<void> _policy() async {
    final f = TextEditingController(text: '$free'); var ap = apply;
    await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (c2, set) => AlertDialog(title: const Text('Absence rule for this class'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: f, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Allowed absences for the school year')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Mark students Dropped when they go over'), value: ap, onChanged: (v) => set(() => ap = v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Cancel')), FilledButton(onPressed: () async {
        Navigator.pop(c2);
        try { await Api.put('/api/class-policy', {'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'free_absences': int.tryParse(f.text), 'apply_to_record': ap}); await _load(); } catch (e) { toast('$e'); }
      }, child: const Text('Save'))])));
  }

  Widget _cell(String d, Map<String, dynamic> s) {
    final k = '$d|${s['id']}'; final v = st[k] ?? ''; final col = v.isEmpty ? Colors.grey : kStatus[v]![1] as Color;
    return InkWell(
      onTap: () => setState(() => st[k] = _cycle[v]!), onLongPress: () => _remark(d, s),
      child: Container(width: 38, height: 34, alignment: Alignment.center, decoration: BoxDecoration(color: col.withOpacity(.15), border: Border.all(color: col, width: (rm[k] ?? '').isNotEmpty ? 2.5 : 1), borderRadius: BorderRadius.circular(6)),
          child: Text(v.isEmpty ? '·' : v, style: TextStyle(color: col, fontWeight: FontWeight.bold))),
    );
  }

  Widget _table() => SingleChildScrollView(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
        columnSpacing: 10, headingRowHeight: 74, dataRowMinHeight: 42, dataRowMaxHeight: 46,
        columns: [
          const DataColumn(label: Text('Student')),
          for (final d in dates) DataColumn(label: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(DateFormat('EEE').format(DateTime.parse(d)), style: const TextStyle(fontSize: 10)), Text(DateFormat('MMM d').format(DateTime.parse(d)), style: const TextStyle(fontWeight: FontWeight.bold)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              InkWell(onTap: () => setState(() { for (final s in studs) { st['$d|${s['id']}'] = 'P'; } }), child: const Padding(padding: EdgeInsets.all(3), child: Text('All P', style: TextStyle(fontSize: 11, color: Colors.green)))),
              InkWell(onTap: () => _removeDate(d), child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: Colors.red)))])])),
          const DataColumn(label: Text('Year abs.')),
          const DataColumn(label: Text('Standing')),
        ],
        rows: [for (final s in studs) DataRow(cells: [
          DataCell(Text('${s['last_name']}, ${s['first_name']}')),
          for (final d in dates) DataCell(_cell(d, s)),
          DataCell(Text('${abs[s['id']] ?? 0} / $free')),
          DataCell(standingChip(abs[s['id']] ?? 0, free)),
        ])],
      )));

  @override
  Widget build(BuildContext c) {
    final warn = studs.where((s) => standingOf(abs[s['id']] ?? 0, free) == 'warning').length;
    final over = studs.where((s) => standingOf(abs[s['id']] ?? 0, free) == 'dropped').length;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { setState(() => month = DateTime(month.year, month.month - 1)); _load(); }),
        Text(DateFormat('MMMM yyyy').format(month), style: Theme.of(c).textTheme.titleMedium),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: month.year == DateTime.now().year && month.month == DateTime.now().month ? null : () { setState(() => month = DateTime(month.year, month.month + 1)); _load(); }),
        const Spacer(),
        IconButton(icon: const Icon(Icons.rule), tooltip: 'Absence rule', onPressed: _policy),
        IconButton(icon: const Icon(Icons.add_box), tooltip: 'Add date', onPressed: _addDate),
        FilledButton(onPressed: dates.isEmpty ? null : _save, child: const Text('Save')),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Align(alignment: Alignment.centerLeft, child: Text('Allowed absences: $free   ·   On warning: $warn   ·   Over limit: $over   ·   Tap = P/A/L/E, long-press = remark', style: const TextStyle(fontSize: 11)))),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator())
          : studs.isEmpty ? const Center(child: Text('No students in this section yet'))
          : dates.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No attendance this month. Tap the + button to add a date column.', textAlign: TextAlign.center)))
          : _table()),
    ]);
  }
}
