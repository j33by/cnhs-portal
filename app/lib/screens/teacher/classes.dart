import 'package:flutter/material.dart';
import '../../core/api.dart';
import 'attendance_tab.dart';
import 'grades_tab.dart';
import 'record_tab.dart';

/// Subjects this teacher is assigned to teach (the section's adviser assigns them).
class MyClasses extends StatelessWidget {
  final String teacherId;
  const MyClasses({super.key, required this.teacherId});
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('section_subjects').stream(primaryKey: ['section_id', 'subject_id']).eq('teacher_id', teacherId),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No classes yet. A section adviser assigns you to a subject when adding it to the schedule.', textAlign: TextAlign.center)));
          return FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: Future.wait<List<Map<String, dynamic>>>([sb.from('sections').select('id,grade_level,name,grading_term'), sb.from('subjects').select('id,code,name')]),
            builder: (c, m) {
              if (!m.hasData) return const Center(child: CircularProgressIndicator());
              final secs = {for (final x in m.data![0]) x['id']: x}, subs = {for (final x in m.data![1]) x['id']: x};
              return ListView(children: [
                for (final r in s.data!)
                  if (secs[r['section_id']] != null && subs[r['subject_id']] != null)
                    ListTile(
                      leading: const Icon(Icons.menu_book),
                      title: Text(subs[r['subject_id']]!['name']),
                      subtitle: Text('Grade ${secs[r['section_id']]!['grade_level']} - ${secs[r['section_id']]!['name']}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ClassScreen(
                          sectionId: r['section_id'], subjectId: r['subject_id'],
                          title: '${subs[r['subject_id']]!['name']} · Grade ${secs[r['section_id']]!['grade_level']} ${secs[r['section_id']]!['name']}',
                          term: (secs[r['section_id']]!['grading_term'] as int?) ?? 1))),
                    ),
              ]);
            });
        });
}

class ClassScreen extends StatelessWidget {
  final String sectionId, subjectId, title; final int term;
  const ClassScreen({super.key, required this.sectionId, required this.subjectId, required this.title, required this.term});
  @override
  Widget build(BuildContext c) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 16)), bottom: const TabBar(tabs: [Tab(text: 'Class record'), Tab(text: 'Attendance'), Tab(text: 'Grades')])),
          body: TabBarView(children: [
            RecordTab(sectionId: sectionId, subjectId: subjectId, initialTerm: term),
            AttendanceTab(sectionId: sectionId, subjectId: subjectId),
            GradesTab(sectionId: sectionId, subjectId: subjectId, initialTerm: term),
          ]),
        ),
      );
}
