import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';

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
              leading: CircleAvatar(backgroundColor: (kStatus[r['status']]![1] as Color).withOpacity(.15), child: Text(r['status'], style: TextStyle(color: kStatus[r['status']]![1] as Color, fontWeight: FontWeight.bold))),
              title: Text(DateFormat('EEE, MMM d, y').format(DateTime.parse(r['att_date']))),
              subtitle: Text(r['status'] == 'A' ? 'No time-in' : 'In ${t12(r['time_in'])}   Out ${t12(r['time_out'])}')),
          ]);
        });
}

/// Realtime released grades of one student, grouped by subject (4 terms + final).
class GradesView extends StatelessWidget {
  final String studentId; const GradesView(this.studentId, {super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('grades').stream(primaryKey: ['id']).eq('student_id', studentId),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final rows = s.data!.where((g) => g['released'] == true).toList(); if (rows.isEmpty) return const Center(child: Text('No grades released yet'));
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: sb.from('subjects').select(), builder: (c, subs) {
              final names = {for (final x in subs.data ?? []) x['id']: x['name']};
              final by = <String, Map<int, num>>{}; for (final g in rows) { (by[names[g['subject_id']] ?? 'Subject'] ??= {})[g['term']] = g['grade']; }
              return ListView(children: [for (final e in by.entries) Card(child: ListTile(title: Text(e.key),
                  subtitle: Text([for (var t = 1; t <= 4; t++) 'Q$t: ${e.value[t] ?? '—'}'].join('   ')),
                  trailing: e.value.length == 4 ? Text((e.value.values.reduce((a, b) => a + b) / 4).toStringAsFixed(0), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)) : const Text('—')))]);
            });
        });
}

/// Weekly schedule of a section with subject + teacher.
class ScheduleView extends StatelessWidget {
  final String? sectionId; const ScheduleView(this.sectionId, {super.key});
  @override
  Widget build(BuildContext c) {
    if (sectionId == null) return const Center(child: Text('You are not in a section yet'));
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: sb.from('schedules').stream(primaryKey: ['id']).eq('section_id', sectionId!).order('start_time'),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: Future.wait<List<Map<String, dynamic>>>([sb.from('subjects').select(), sb.from('teacher_names').select('id,first_name,last_name')]),
          builder: (c, m) {
            final sub = {for (final x in m.data?[0] ?? []) x['id']: x['name']}, tea = {for (final x in m.data?[1] ?? []) x['id']: '${x['first_name']} ${x['last_name']}'};
            return ListView(children: [for (var d = 1; d <= 5; d++) ...[
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(kDays[d], style: Theme.of(c).textTheme.titleMedium)),
              for (final r in s.data!.where((r) => r['day_of_week'] == d)) ListTile(dense: true, title: Text(sub[r['subject_id']] ?? 'Class'),
                  subtitle: Text('${t12(r['start_time'])} – ${t12(r['end_time'])}  ·  ${tea[r['teacher_id']] ?? 'TBA'}${r['room'] != null ? '  ·  ${r['room']}' : ''}')),
            ]]);
          });
      });
  }
}

/// Realtime notification inbox.
class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('notifications').stream(primaryKey: ['id']).eq('user_id', sb.auth.currentUser!.id).order('created_at', ascending: false),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const Center(child: Text('No notifications'));
          return ListView(children: [for (final n in s.data!) ListTile(
              leading: Icon(n['kind'] == 'attendance' ? Icons.how_to_reg : n['kind'] == 'grades' ? Icons.grade : Icons.notifications),
              title: Text(n['title']), subtitle: Text(n['body']), trailing: Text(DateFormat('MMM d\nh:mm a').format(DateTime.parse(n['created_at']).toLocal()), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11)))]);
        });
}

class ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> p; final String sub; const ProfileHeader(this.p, this.sub, {super.key});
  @override
  Widget build(BuildContext c) => ListTile(leading: CircleAvatar(backgroundImage: p['photo_url'] != null ? NetworkImage(p['photo_url']) : null, child: p['photo_url'] == null ? const Icon(Icons.person) : null), title: Text(p['full_name']), subtitle: Text(sub));
}
