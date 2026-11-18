import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/lookup.dart';
import 'ui.dart';
import '../core/offline.dart';

String _fmt(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
String _honor(double avg, bool noFail) => !noFail ? '' : avg >= 98 ? 'With Highest Honors' : avg >= 95 ? 'With High Honors' : avg >= 90 ? 'With Honors' : '';
String _descriptor(num g) => g >= 90 ? 'Outstanding' : g >= 85 ? 'Very Satisfactory' : g >= 80 ? 'Satisfactory' : g >= 75 ? 'Fairly Satisfactory' : 'Did Not Meet Expectations';

/// Released grades laid out like a printed report card: learning areas x 4 quarters, final grade, remarks, general average.
class GradesView extends StatefulWidget {
  final String studentId; final String? name, studentNo, classLabel;
  const GradesView(this.studentId, {super.key, this.name, this.studentNo, this.classLabel});
  @override
  State<GradesView> createState() => _GradesViewState();
}

class _GradesViewState extends State<GradesView> {
  late final Stream<List<Map<String, dynamic>>> _stream = liveStream('grades|student_id=${widget.studentId}', () => sb.from('grades').stream(primaryKey: ['id']).eq('student_id', widget.studentId));
  String? year;

  @override
  void initState() { super.initState(); _loadYear(); }
  Future<void> _loadYear() async {
    try {
      final y = await cachedRow('year', () => sb.from('school_years').select('label').eq('is_current', true).maybeSingle());
      if (mounted && y != null) { setState(() => year = '${y['label']}'); }
    } catch (_) {}
  }

  Widget _cell(BuildContext c, String text, {bool head = false, bool bold = false, Color? color, TextAlign align = TextAlign.center, double size = 13}) => Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: head ? 9 : 11),
        child: Text(text, textAlign: align, style: TextStyle(fontSize: head ? 11.5 : size, fontWeight: head || bold ? FontWeight.bold : FontWeight.normal, color: color, letterSpacing: head ? .3 : 0)),
      );

  Widget _banner(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      width: double.infinity, padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary, Color.lerp(cs.primary, Colors.black, .35)!]),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(Icons.school, color: cs.primary, size: 28)),
        const SizedBox(height: 8),
        Text('Calape National High School', textAlign: TextAlign.center, style: TextStyle(color: cs.onPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('REPORT CARD', style: TextStyle(color: cs.onPrimary.withValues(alpha: .9), letterSpacing: 3, fontSize: 12, fontWeight: FontWeight.w600)),
        if (year != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text('School Year $year', style: TextStyle(color: cs.onPrimary.withValues(alpha: .85), fontSize: 12.5))),
      ]),
    );
  }

  Widget _info(BuildContext c) {
    Widget line(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text(k, style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]));
    return Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(children: [
      line("Learner's name", widget.name ?? '—'), line('Student ID', widget.studentNo ?? '—'), line('Grade & section', widget.classLabel ?? '—'),
    ]));
  }

  Widget _table(BuildContext c, Map<String, Map<int, num>> by, bool wide) {
    final cs = Theme.of(c).colorScheme, line = cs.outline.withValues(alpha: .55);
    final names = by.keys.toList()..sort();
    final finals = <String, double>{};
    for (final n in names) { if (by[n]!.length == 4) { finals[n] = by[n]!.values.reduce((a, b) => a + b) / 4; } }
    double? termAvg(int t) { final v = [for (final n in names) if (by[n]![t] != null) by[n]![t]!.toDouble()]; return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length; }
    final general = finals.isEmpty ? null : finals.values.reduce((a, b) => a + b) / finals.length;
    Color gc(num g) => g < 75 ? Colors.red.shade700 : g >= 90 ? Colors.green.shade700 : cs.onSurface;
    final head = BoxDecoration(color: cs.primaryContainer);
    return Table(
      border: TableBorder.all(color: line, width: .8),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {0: const FlexColumnWidth(), for (var i = 1; i <= 4; i++) i: FixedColumnWidth(wide ? 58 : 38), 5: FixedColumnWidth(wide ? 66 : 48), if (wide) 6: const FixedColumnWidth(92)},
      children: [
        TableRow(decoration: head, children: [
          _cell(c, 'LEARNING AREAS', head: true, align: TextAlign.left), for (var i = 1; i <= 4; i++) _cell(c, 'Q$i', head: true), _cell(c, 'FINAL', head: true), if (wide) _cell(c, 'REMARKS', head: true),
        ]),
        for (final n in names) TableRow(children: [
          _cell(c, n, align: TextAlign.left, bold: true, size: 13.5),
          for (var t = 1; t <= 4; t++) _cell(c, by[n]![t] == null ? '—' : _fmt(by[n]![t]!), color: by[n]![t] == null ? Theme.of(c).hintColor : gc(by[n]![t]!)),
          _cell(c, finals[n] == null ? '—' : finals[n]!.round().toString(), bold: true, size: 14, color: finals[n] == null ? Theme.of(c).hintColor : gc(finals[n]!)),
          if (wide) _cell(c, finals[n] == null ? 'In progress' : finals[n]! >= 75 ? 'Passed' : 'Failed', size: 12, bold: finals[n] != null, color: finals[n] == null ? Theme.of(c).hintColor : finals[n]! >= 75 ? Colors.green.shade700 : Colors.red.shade700),
        ]),
        TableRow(decoration: BoxDecoration(color: cs.primary.withValues(alpha: .08)), children: [
          _cell(c, 'GENERAL AVERAGE', head: true, align: TextAlign.left),
          for (var t = 1; t <= 4; t++) _cell(c, termAvg(t) == null ? '—' : termAvg(t)!.round().toString(), bold: true),
          _cell(c, general == null ? '—' : general.round().toString(), bold: true, size: 15, color: general == null ? null : gc(general)),
          if (wide) _cell(c, general == null ? '' : general >= 75 ? 'Passed' : 'Failed', bold: true, size: 12, color: general == null ? null : gc(general)),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (c, s) {
          if (s.hasError) { return const EmptyState(icon: Icons.cloud_off, title: 'Could not load grades', message: 'Check your connection and try again.'); }
          if (!s.hasData) { return const Center(child: CircularProgressIndicator()); }
          final rows = s.data!.where((g) => g['released'] == true).toList();
          if (rows.isEmpty) { return const EmptyState(icon: Icons.menu_book_outlined, title: 'No grades released yet', message: 'Your report card appears here as soon as your teachers release the grades.'); }
          return ListenableBuilder(listenable: Lookup.i, builder: (c, _) {
            final by = <String, Map<int, num>>{};
            for (final g in rows) { (by[Lookup.i.subject(g['subject_id'] as String?)] ??= {})[g['term'] as int] = g['grade'] as num; }
            final finals = [for (final e in by.entries) if (e.value.length == 4) e.value.values.reduce((a, b) => a + b) / 4];
            final general = finals.isEmpty ? null : finals.reduce((a, b) => a + b) / finals.length;
            final allDone = finals.length == by.length, noFail = finals.every((f) => f >= 75), honor = general == null || !allDone ? '' : _honor(general, noFail);
            final cs = Theme.of(c).colorScheme;
            return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 32), children: [
              Container(
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.primary, width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 14, offset: const Offset(0, 4))]),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(builder: (c, box) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _banner(c), _info(c), const Divider(height: 1),
                  Padding(padding: const EdgeInsets.all(12), child: _table(c, by, box.maxWidth >= 470)),
                  if (honor.isNotEmpty) Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12), padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: .2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade700)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.workspace_premium, color: Colors.amber.shade800), const SizedBox(width: 8), Text(honor, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900))]),
                  ),
                  if (!allDone) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text('A final grade is shown once all four quarters of a subject are released.', style: TextStyle(fontSize: 12))),
                ])),
              ),
              const SizedBox(height: 14),
              SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Grading scale', style: Theme.of(c).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final x in const [[90, 'Outstanding', '90 – 100'], [85, 'Very Satisfactory', '85 – 89'], [80, 'Satisfactory', '80 – 84'], [75, 'Fairly Satisfactory', '75 – 79'], [0, 'Did Not Meet Expectations', 'Below 75']])
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                    SizedBox(width: 70, child: Text('${x[2]}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))), Text('${x[1]}', style: const TextStyle(fontSize: 12.5)),
                  ])),
                if (general != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Your general average is ${general.round()} (${_descriptor(general.round())}).', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ])),
            ])));
          });
        },
      );
}
