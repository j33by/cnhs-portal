import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/lookup.dart';
import 'colors.dart';
import 'schedule_widgets.dart';
import 'status.dart';
import 'ui.dart';
import '../core/offline.dart';

final _ymd = DateFormat('yyyy-MM-dd');

Color _rateColor(double p) => p >= .9 ? Colors.green : p >= .8 ? Colors.orange : Colors.red;

/// Realtime school-day attendance of ONE student: summary, month calendar, and a dated list.
/// Used by the student app, the parent app and the teacher's advisory view.
class AttendanceView extends StatefulWidget {
  final String studentId; final String? sectionId; final String? studentName; final bool showSubjects;
  const AttendanceView(this.studentId, {super.key, this.sectionId, this.studentName, this.showSubjects = false});
  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  late final Stream<List<Map<String, dynamic>>> _stream = liveStream('daily_attendance|student_id=${widget.studentId}|o', () => sb.from('daily_attendance').stream(primaryKey: ['student_id', 'att_date']).eq('student_id', widget.studentId).order('att_date', ascending: false));
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? selected = _ymd.format(DateTime.now());

  bool get _isThisMonth => month.year == DateTime.now().year && month.month == DateTime.now().month;

  Widget _stat(String k, int n) => Expanded(child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3), padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: stColor(k).withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text('$n', style: TextStyle(fontSize: 22, color: stColor(k), fontWeight: FontWeight.bold)),
          Text(stLabel(k), style: const TextStyle(fontSize: 11.5)),
        ]),
      ));

  Widget _summary(List<Map<String, dynamic>> rows) {
    int n(String k) => rows.where((r) => r['status'] == k).length;
    final total = rows.length, ok = n('P') + n('L') + n('E'), pct = total == 0 ? 0.0 : ok / total;
    return SoftCard(child: Column(children: [
      Row(children: [
        SizedBox(width: 86, height: 86, child: Stack(alignment: Alignment.center, children: [
          SizedBox(width: 86, height: 86, child: CircularProgressIndicator(value: total == 0 ? 0 : pct, strokeWidth: 9, backgroundColor: _rateColor(pct).withValues(alpha: .15), color: _rateColor(pct), strokeCap: StrokeCap.round)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(total == 0 ? '—' : '${(pct * 100).round()}%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const Text('attended', style: TextStyle(fontSize: 10)),
          ]),
        ])),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('School year attendance', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(total == 0 ? 'No school days recorded yet' : '$ok of $total school days attended', style: const TextStyle(fontSize: 13)),
          if (n('A') > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Pill('${n('A')} absence${n('A') == 1 ? '' : 's'}', Colors.red, icon: Icons.warning_amber_rounded)),
        ])),
      ]),
      const SizedBox(height: 12),
      Row(children: [_stat('P', n('P')), _stat('L', n('L')), _stat('A', n('A')), _stat('E', n('E'))]),
    ]));
  }

  Widget _calendar(Map<String, Map<String, dynamic>> by) {
    final first = DateTime(month.year, month.month, 1), days = DateTime(month.year, month.month + 1, 0).day, lead = first.weekday - 1;
    final rowsN = ((lead + days) / 7).ceil(), todayKey = _ymd.format(DateTime.now()), cs = Theme.of(context).colorScheme;
    Widget cell(int day, int col) {
      if (day < 1 || day > days) { return const SizedBox(height: 46); }
      final key = _ymd.format(DateTime(month.year, month.month, day)), rec = by[key], st = rec?['status'] as String?;
      final isToday = key == todayKey, isSel = key == selected, weekend = col >= 5, color = st == null ? cs.onSurface : stColor(st);
      return GestureDetector(
        onTap: () => setState(() => selected = key),
        child: SizedBox(height: 46, child: Center(child: Container(
          width: 38, height: 38, alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: st == null ? (isSel ? cs.primaryContainer : null) : (isSel ? color : color.withValues(alpha: .16)),
            border: isToday ? Border.all(color: cs.primary, width: 2) : null,
          ),
          child: Text('$day', style: TextStyle(fontWeight: st != null || isToday ? FontWeight.bold : FontWeight.normal, color: st == null ? (weekend ? Theme.of(context).hintColor : null) : (isSel ? Colors.white : color))),
        ))),
      );
    }
    return SoftCard(child: Column(children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Expanded(child: Center(child: Text(DateFormat('MMMM yyyy').format(month), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)))),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: _isThisMonth ? null : () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      Row(children: [for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).hintColor))))]),
      const SizedBox(height: 4),
      for (var r = 0; r < rowsN; r++) Row(children: [for (var k = 0; k < 7; k++) Expanded(child: cell(r * 7 + k - lead + 1, k))]),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 4, alignment: WrapAlignment.center, children: [
        for (final k in const ['P', 'L', 'A', 'E']) Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: stColor(k), shape: BoxShape.circle)), const SizedBox(width: 4), Text(stLabel(k), style: const TextStyle(fontSize: 11.5))]),
      ]),
    ]));
  }

  Widget _detail(Map<String, Map<String, dynamic>> by) {
    final key = selected; if (key == null) { return const SizedBox.shrink(); }
    final rec = by[key], date = DateTime.parse(key), title = DateFormat('EEEE, MMM d, y').format(date);
    if (rec == null) {
      final weekend = date.weekday > 5, future = date.isAfter(DateTime.now());
      return SoftCard(child: Row(children: [
        Icon(weekend ? Icons.weekend : Icons.hourglass_empty, color: Theme.of(context).hintColor), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(weekend ? 'No classes on weekends' : future ? 'This day has not happened yet' : 'No attendance record for this day', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
        ])),
      ]));
    }
    final st = rec['status'] as String, col = stColor(st);
    final remark = '${rec['remarks'] ?? ''}'.trim();
    return SoftCard(color: col.withValues(alpha: .08), border: col.withValues(alpha: .4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(backgroundColor: col.withValues(alpha: .18), child: Icon(stIcon(st), color: col)), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(stLabel(st), style: TextStyle(color: col, fontWeight: FontWeight.bold))])),
        Pill(rec['source'] == 'manual' ? 'Marked by teacher' : 'Fingerprint', col, icon: rec['source'] == 'manual' ? Icons.edit_note : Icons.fingerprint),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _timeBox(Icons.login, 'Time in', st == 'A' && rec['time_in'] == null ? '—' : t12(rec['time_in'] as String?))),
        const SizedBox(width: 8),
        Expanded(child: _timeBox(Icons.logout, 'Time out', t12(rec['time_out'] as String?))),
      ]),
      if (remark.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.notes, size: 16), const SizedBox(width: 6), Expanded(child: Text(remark, style: const TextStyle(fontSize: 13)))])),
    ]));
  }

  Widget _timeBox(IconData i, String k, String v) => Container(
        padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [Icon(i, size: 18), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(fontSize: 11)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))])]),
      );

  Widget _row(Map<String, dynamic> r) {
    final st = r['status'] as String, col = stColor(st), d = DateTime.parse('${r['att_date']}'), sel = selected == '${r['att_date']}';
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: SoftCard(
      padding: EdgeInsets.zero, border: sel ? col : null, onTap: () => setState(() => selected = '${r['att_date']}'),
      child: IntrinsicHeight(child: Row(children: [
        Container(width: 64, color: col.withValues(alpha: .14), padding: const EdgeInsets.symmetric(vertical: 10), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(DateFormat('d').format(d), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: col)),
          Text(DateFormat('EEE').format(d).toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: col)),
        ])),
        Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(DateFormat('MMMM d, y').format(d), style: const TextStyle(fontWeight: FontWeight.w600))), Pill(stLabel(st), col, icon: stIcon(st))]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.login, size: 14, color: Theme.of(context).hintColor), const SizedBox(width: 4), Text(r['time_in'] == null ? 'No time-in' : t12(r['time_in'] as String?), style: const TextStyle(fontSize: 12.5)),
            const SizedBox(width: 14),
            Icon(Icons.logout, size: 14, color: Theme.of(context).hintColor), const SizedBox(width: 4), Text(t12(r['time_out'] as String?), style: const TextStyle(fontSize: 12.5)),
          ]),
        ]))),
      ])),
    ));
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (c, s) {
          if (s.hasError) { return const EmptyState(icon: Icons.cloud_off, title: 'Could not load attendance', message: 'Check your connection and try again.'); }
          if (!s.hasData) { return const Center(child: CircularProgressIndicator()); }
          final rows = s.data!, by = {for (final r in rows) '${r['att_date']}': r};
          final key = DateFormat('yyyy-MM').format(month), monthRows = rows.where((r) => '${r['att_date']}'.startsWith(key)).toList()..sort((a, b) => '${b['att_date']}'.compareTo('${a['att_date']}'));
          return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
            _summary(rows),
            if (widget.showSubjects && widget.sectionId != null) Padding(padding: const EdgeInsets.only(top: 10), child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => SubjectAttendanceScreen(studentId: widget.studentId, sectionId: widget.sectionId, studentName: widget.studentName ?? 'Student'))),
              icon: const Icon(Icons.fact_check_outlined), label: const Text('View attendance by subject'))),
            const SizedBox(height: 16), const SectionTitle('Calendar', icon: Icons.calendar_month),
            _calendar(by), const SizedBox(height: 10), _detail(by),
            const SizedBox(height: 18), SectionTitle('${DateFormat('MMMM').format(month)} records', icon: Icons.list_alt, trailing: Text('${monthRows.length} day${monthRows.length == 1 ? '' : 's'}', style: TextStyle(color: Theme.of(c).hintColor))),
            if (monthRows.isEmpty) const SoftCard(child: Padding(padding: EdgeInsets.all(10), child: Center(child: Text('No attendance recorded this month'))))
            else for (final r in monthRows) _row(r),
          ])));
        },
      );
}

/// Home card: today's school-day status, this month at a glance, shortcuts.
class TodayAttendanceCard extends StatefulWidget {
  final String studentId; final String? sectionId; final String name; final VoidCallback onSeeAll;
  const TodayAttendanceCard({super.key, required this.studentId, required this.sectionId, required this.name, required this.onSeeAll});
  @override
  State<TodayAttendanceCard> createState() => _TodayAttendanceCardState();
}

class _TodayAttendanceCardState extends State<TodayAttendanceCard> {
  late final Stream<List<Map<String, dynamic>>> _stream = liveStream('daily_attendance|student_id=${widget.studentId}', () => sb.from('daily_attendance').stream(primaryKey: ['student_id', 'att_date']).eq('student_id', widget.studentId));

  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(stream: _stream, builder: (c, s) {
        final rows = s.data ?? [], now = DateTime.now(), today = _ymd.format(now), mk = DateFormat('yyyy-MM').format(now);
        final rec = rows.where((r) => '${r['att_date']}' == today).toList(), t = rec.isEmpty ? null : rec.first, st = t?['status'] as String?;
        final month = rows.where((r) => '${r['att_date']}'.startsWith(mk));
        int n(String k) => month.where((r) => r['status'] == k).length;
        final weekend = now.weekday > 5, col = st == null ? Theme.of(c).hintColor : stColor(st);
        final headline = st != null ? stLabel(st) : weekend ? 'No classes today' : 'No record yet';
        final tin = t?['time_in'] as String?, tout = t?['time_out'] as String?;
        final sub = st != null
            ? (st == 'A' && tin == null ? 'No fingerprint punch recorded today' : 'In ${t12(tin)}  ·  Out ${t12(tout)}')
            : weekend ? 'Enjoy your weekend' : 'Waiting for the fingerprint scan';
        return SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 54, height: 54, decoration: BoxDecoration(color: col.withValues(alpha: .15), shape: BoxShape.circle), child: Icon(weekend && st == null ? Icons.weekend : stIcon(st), color: col, size: 28)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Today · ${DateFormat('EEE, MMM d').format(now)}', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
              Text(headline, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: col)),
              Text(sub, style: const TextStyle(fontSize: 13)),
            ])),
          ]),
          const Divider(height: 24),
          Text('${DateFormat('MMMM').format(now)} so far', style: Theme.of(c).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final k in const ['P', 'L', 'A', 'E']) Pill('${n(k)} ${stLabel(k)}', stColor(k), icon: stIcon(k)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.tonalIcon(onPressed: widget.onSeeAll, icon: const Icon(Icons.calendar_month, size: 18), label: const Text('Full attendance'))),
            if (widget.sectionId != null) ...[
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => SubjectAttendanceScreen(studentId: widget.studentId, sectionId: widget.sectionId, studentName: widget.name))),
                icon: const Icon(Icons.fact_check_outlined, size: 18), label: const Text('By subject'))),
            ],
          ]),
        ]));
      });
}

/// Attendance per SUBJECT: what happened in each class today, and the history of every subject.
class SubjectAttendanceScreen extends StatelessWidget {
  final String studentId, studentName; final String? sectionId;
  const SubjectAttendanceScreen({super.key, required this.studentId, required this.sectionId, required this.studentName});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text('$studentName · by subject')),
        body: SubjectAttendanceBody(studentId: studentId, sectionId: sectionId),
      );
}

class SubjectAttendanceBody extends StatefulWidget {
  final String studentId; final String? sectionId;
  const SubjectAttendanceBody({super.key, required this.studentId, required this.sectionId});
  @override
  State<SubjectAttendanceBody> createState() => _SubjectAttendanceBodyState();
}

class _SubjectAttendanceBodyState extends State<SubjectAttendanceBody> {
  late final Stream<List<Map<String, dynamic>>> _stream = liveStream('class_attendance|student_id=${widget.studentId}', () => sb.from('class_attendance').stream(primaryKey: ['student_id', 'subject_id', 'att_date']).eq('student_id', widget.studentId));

  Widget _todayRow(BuildContext c, Map<String, dynamic> slot, Map<String, Map<String, dynamic>> todayBy) {
    final now = DateTime.now(), nowMin = now.hour * 60 + now.minute, a = minOf('${slot['start_time']}'), b = minOf('${slot['end_time']}');
    final row = todayBy['${slot['subject_id']}'];
    String? st = slot['cancelled'] == true ? 'N' : row?['status'] as String?;
    String label; Color col; IconData icon;
    if (st != null) { label = stLabel(st); col = stColor(st); icon = stIcon(st); }
    else if (nowMin < a) { label = 'Upcoming'; col = Colors.grey; icon = Icons.schedule; }
    else if (nowMin < b) { label = 'In session'; col = Colors.blue; icon = Icons.play_circle; }
    else { label = 'Not marked yet'; col = Colors.grey; icon = Icons.hourglass_empty; }
    final sc = subjectColor('${slot['subject']}');
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: SoftCard(padding: EdgeInsets.zero, child: IntrinsicHeight(child: Row(children: [
      Container(width: 6, color: sc),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: SizedBox(width: 64, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(t12('${slot['start_time']}'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text(t12('${slot['end_time']}'), style: TextStyle(fontSize: 11, color: Theme.of(c).hintColor))]))),
      Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${slot['subject']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)), Text('${slot['teacher']}', style: const TextStyle(fontSize: 12.5)),
        if (slot['cancelled'] == true && slot['cancel_reason'] != null) Text('${slot['cancel_reason']}', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
      ]))),
      Padding(padding: const EdgeInsets.only(right: 10), child: Pill(label, col, icon: icon)),
    ]))));
  }

  Widget _subjectCard(BuildContext c, String subjectId, List<Map<String, dynamic>> recs, String teacher) {
    final name = Lookup.i.subject(subjectId), col = subjectColor(name);
    int n(String k) => recs.where((r) => r['status'] == k).length;
    final counted = n('P') + n('L') + n('A') + n('E'), ok = n('P') + n('L') + n('E'), pct = counted == 0 ? null : ok / counted;
    final sorted = [...recs]..sort((a, b) => '${b['att_date']}'.compareTo('${a['att_date']}'));
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: SoftCard(padding: EdgeInsets.zero, child: Theme(
      data: Theme.of(c).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        leading: CircleAvatar(backgroundColor: col.withValues(alpha: .15), child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(color: col, fontWeight: FontWeight.bold))),
        title: Row(children: [Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))), if (pct != null) Text('${(pct * 100).round()}%', style: TextStyle(fontWeight: FontWeight.bold, color: _rateColor(pct)))]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(teacher, style: const TextStyle(fontSize: 12.5)),
          if (pct != null) Padding(padding: const EdgeInsets.only(top: 6), child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: _rateColor(pct).withValues(alpha: .15), color: _rateColor(pct)))),
          Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final k in const ['P', 'L', 'A', 'E', 'N']) if (n(k) > 0) Pill('${n(k)} ${stLabel(k)}', stColor(k)),
            if (recs.isEmpty) const Pill('Nothing marked yet', Colors.grey),
          ])),
        ]),
        children: [
          for (final r in sorted) ListTile(
            dense: true, visualDensity: VisualDensity.compact,
            leading: Icon(stIcon(r['status'] as String?), color: stColor(r['status'] as String?)),
            title: Text(DateFormat('EEE, MMM d, y').format(DateTime.parse('${r['att_date']}'))),
            subtitle: ('${r['remarks'] ?? ''}').trim().isEmpty ? null : Text('${r['remarks']}'),
            trailing: Pill(stLabel(r['status'] as String?), stColor(r['status'] as String?)),
          ),
        ],
      ),
    )));
  }

  @override
  Widget build(BuildContext c) => SectionFeed(sectionId: widget.sectionId, studentId: widget.studentId, builder: (c, slots, loaded) => StreamBuilder<List<Map<String, dynamic>>>(stream: _stream, builder: (c, s) {
        if (!s.hasData || !loaded) { return const Center(child: CircularProgressIndicator()); }
        final rows = s.data!, now = DateTime.now(), today = _ymd.format(now);
        final todayBy = <String, Map<String, dynamic>>{for (final r in rows.where((r) => '${r['att_date']}' == today)) '${r['subject_id']}': r};
        final todaySlots = slots.where((x) => x['day_of_week'] == now.weekday).toList();
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final r in rows) { (groups['${r['subject_id']}'] ??= []).add(r); }
        for (final x in slots) { groups.putIfAbsent('${x['subject_id']}', () => []); }
        final ids = groups.keys.toList()..sort((a, b) => Lookup.i.subject(a).compareTo(Lookup.i.subject(b)));
        String teacherOf(String id) {
          final m = slots.where((x) => '${x['subject_id']}' == id).toList();
          if (m.isNotEmpty) { return '${m.first['teacher']}'; }
          final marked = groups[id]!.map((r) => r['marked_by'] as String?).whereType<String>().toList();
          return marked.isEmpty ? 'Teacher TBA' : Lookup.i.teacher(marked.first);
        }
        final all = rows.where((r) => r['status'] != 'N').toList();
        final okAll = all.where((r) => r['status'] != 'A').length, absAll = all.where((r) => r['status'] == 'A').length;
        return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          SoftCard(child: Row(children: [
            Expanded(child: _big(all.isEmpty ? '—' : '${(okAll / all.length * 100).round()}%', 'Overall in class', all.isEmpty ? Colors.grey : _rateColor(okAll / all.length))),
            Expanded(child: _big('$absAll', 'Class absences', absAll > 0 ? Colors.red : Colors.green)),
            Expanded(child: _big('${rows.where((r) => r['status'] == 'N').length}', 'No-class days', stColor('N'))),
          ])),
          const SizedBox(height: 18), SectionTitle("Today's classes", icon: Icons.today, trailing: Text(DateFormat('EEE, MMM d').format(now), style: TextStyle(color: Theme.of(c).hintColor))),
          if (todaySlots.isEmpty) const SoftCard(child: Padding(padding: EdgeInsets.all(10), child: Center(child: Text('No classes scheduled today'))))
          else for (final x in todaySlots) _todayRow(c, x, todayBy),
          const SizedBox(height: 18), const SectionTitle('Every subject', icon: Icons.menu_book),
          if (ids.isEmpty) const SoftCard(child: Padding(padding: EdgeInsets.all(10), child: Center(child: Text('No subjects yet'))))
          else for (final id in ids) _subjectCard(c, id, groups[id]!, teacherOf(id)),
        ])));
      }));

  Widget _big(String v, String k, Color col) => Column(children: [Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: col)), Text(k, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5))]);
}
