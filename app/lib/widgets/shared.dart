import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/lookup.dart';

const kDays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const kStatus = {'P': ['Present', Colors.green], 'A': ['Absent', Colors.red], 'L': ['Late', Colors.orange], 'E': ['Excused', Colors.blueGrey]};
String t12(String? t) { if (t == null) return '—'; final p = t.split(':'); final h = int.parse(p[0]); return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}'; }

/// Realtime attendance of ONE student (used by student app, parent tabs, teacher view).
class AttendanceView extends StatelessWidget {
  final String studentId; const AttendanceView(this.studentId, {super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('daily_attendance').stream(primaryKey: ['student_id', 'att_date']).eq('student_id', studentId).order('att_date', ascending: false),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final rows = s.data!; if (rows.isEmpty) return const Center(child: Text('No attendance recorded yet'));
          final n = (String k) => rows.where((r) => r['status'] == k).length;
          return ListView(children: [
            Padding(padding: const EdgeInsets.all(12), child: Row(children: [for (final k in ['P', 'L', 'A', 'E']) Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Text('${n(k)}', style: TextStyle(fontSize: 24, color: kStatus[k]![1] as Color, fontWeight: FontWeight.bold)), Text(kStatus[k]![0] as String, style: const TextStyle(fontSize: 12))]))))])),
            for (final r in rows) ListTile(
              leading: CircleAvatar(backgroundColor: (kStatus[r['status']]![1] as Color).withValues(alpha: .15), child: Text(r['status'], style: TextStyle(color: kStatus[r['status']]![1] as Color, fontWeight: FontWeight.bold))),
              title: Text(DateFormat('EEE, MMM d, y').format(DateTime.parse(r['att_date']))),
              subtitle: Text(r['status'] == 'A' ? 'No time-in' : 'In ${t12(r['time_in'])}   Out ${t12(r['time_out'])}')),
          ]);
        });
}

/// Realtime released grades of one student, grouped by subject (4 terms + final). Subject names come from the shared cache.
class GradesView extends StatelessWidget {
  final String studentId; const GradesView(this.studentId, {super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('grades').stream(primaryKey: ['id']).eq('student_id', studentId),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final rows = s.data!.where((g) => g['released'] == true).toList();
          if (rows.isEmpty) return const Center(child: Text('No grades released yet'));
          return ListenableBuilder(listenable: Lookup.i, builder: (c, _) {
            final by = <String, Map<int, num>>{};
            for (final g in rows) { (by[Lookup.i.subject(g['subject_id'] as String?)] ??= {})[g['term'] as int] = g['grade'] as num; }
            return ListView(children: [for (final e in by.entries) Card(child: ListTile(title: Text(e.key),
                subtitle: Text([for (var t = 1; t <= 4; t++) 'Q$t: ${e.value[t] ?? '—'}'].join('   ')),
                trailing: e.value.length == 4 ? Text((e.value.values.reduce((a, b) => a + b) / 4).toStringAsFixed(0), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)) : const Text('—')))]);
          });
        });
}

/// Weekly schedule of a section with subject + teacher (live).
class ScheduleView extends StatelessWidget {
  final String? sectionId; const ScheduleView(this.sectionId, {super.key});
  @override
  Widget build(BuildContext c) {
    if (sectionId == null) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Not in a section yet. The schedule appears once an adviser adds the student.', textAlign: TextAlign.center)));
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: sb.from('schedules').stream(primaryKey: ['id']).eq('section_id', sectionId!).order('start_time'),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) return const Center(child: Text('No classes scheduled yet'));
        return ListenableBuilder(listenable: Lookup.i, builder: (c, _) => ListView(children: [for (var d = 1; d <= 5; d++) ...[
          if (s.data!.any((r) => r['day_of_week'] == d)) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(kDays[d], style: Theme.of(c).textTheme.titleMedium)),
          for (final r in s.data!.where((r) => r['day_of_week'] == d)) ListTile(dense: true, title: Text(Lookup.i.subject(r['subject_id'] as String?)),
              subtitle: Text('${t12(r['start_time'])} – ${t12(r['end_time'])}  ·  ${Lookup.i.teacher(r['teacher_id'] as String?)}${r['room'] != null ? '  ·  ${r['room']}' : ''}')),
        ]]));
      });
  }
}

/// Realtime notification inbox. Unread ones are bold; opening this screen marks them read after a few seconds.
class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});
  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  late final Stream<List<Map<String, dynamic>>> _stream = sb.from('notifications').stream(primaryKey: ['id'])
      .eq('user_id', sb.auth.currentUser!.id).order('created_at', ascending: false);
  Timer? _t;
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  void _scheduleRead() {
    if (_t != null) return;
    _t = Timer(const Duration(seconds: 3), () { _t = null; Api.post('/api/notifications/read').catchError((_) {}); });
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const Center(child: Text('No notifications'));
          final unread = s.data!.where((n) => n['read'] != true).length;
          if (unread > 0 && TickerMode.of(c)) { _scheduleRead(); }              // TickerMode is off while this tab is hidden
          return ListView(children: [for (final n in s.data!) ListTile(
              tileColor: n['read'] == true ? null : Theme.of(c).colorScheme.primaryContainer.withValues(alpha: .35),
              leading: Icon(n['kind'] == 'attendance' ? Icons.how_to_reg : n['kind'] == 'grades' ? Icons.grade : n['kind'] == 'bind' ? Icons.link : Icons.notifications),
              title: Text(n['title'], style: TextStyle(fontWeight: n['read'] == true ? FontWeight.normal : FontWeight.bold)), subtitle: Text(n['body']),
              trailing: Text(DateFormat('MMM d\nh:mm a').format(DateTime.parse(n['created_at']).toLocal()), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11)))]);
        });
}

class ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> p; final String sub; const ProfileHeader(this.p, this.sub, {super.key});
  @override
  Widget build(BuildContext c) => ListTile(leading: CircleAvatar(backgroundImage: p['photo_url'] != null ? NetworkImage(p['photo_url']) : null, child: p['photo_url'] == null ? const Icon(Icons.person) : null), title: Text(p['full_name']), subtitle: Text(sub));
}
