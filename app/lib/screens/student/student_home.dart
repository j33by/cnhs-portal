import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../widgets/shared.dart';

class StudentHome extends StatelessWidget {
  final Map<String, dynamic> profile; const StudentHome({super.key, required this.profile});
  @override
  Widget build(BuildContext c) => FutureBuilder<Map<String, dynamic>>(
        future: sb.from('students').select('*, sections(name,grade_level)').eq('id', profile['id']).single(),
        builder: (c, s) {
          if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final st = s.data!;
          return DefaultTabController(length: 5, child: Scaffold(
            appBar: AppBar(title: const Text('CNHS'), actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => sb.auth.signOut())],
              bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Me'), Tab(text: 'Attendance'), Tab(text: 'Grades'), Tab(text: 'Schedule'), Tab(text: 'Alerts')])),
            body: TabBarView(children: [
              ListView(children: [ProfileHeader(profile, 'Student ID ${st['student_no']}'), ListTile(title: const Text('Grade & section'), subtitle: Text(st['sections'] == null ? 'Grade ${st['grade_level']} - waiting for adviser to add you' : 'Grade ${st['sections']['grade_level']} - ${st['sections']['name']}')),
                ListTile(title: const Text('Address'), subtitle: Text(st['address'] ?? '—')), ListTile(title: const Text('Age'), subtitle: Text('${st['age'] ?? '—'}'))]),
              AttendanceView(st['id']), GradesView(st['id']), ScheduleView(st['section_id']), const NotificationsView(),
            ])));
        });
}
