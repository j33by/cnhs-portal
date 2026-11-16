import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/streams.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/shared.dart';
import '../profile_screen.dart';

/// Student app: hamburger menu. Sign out is at the bottom of the Profile screen.
class StudentHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StudentHome({super.key, required this.profile});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  Map<String, dynamic>? st;
  String? sectionLabel, _sectionFor;
  StreamSubscription<dynamic>? _sub;
  late final Stream<int> unread = unreadStream();

  @override
  void initState() {
    super.initState();
    _sub = sb.from('students').stream(primaryKey: ['id']).eq('id', widget.profile['id']).listen((rows) {
      if (rows.isEmpty || !mounted) { return; }
      setState(() => st = rows.first);
      _loadSection();
    });
  }
  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  Future<void> _loadSection() async {
    final id = st?['section_id'] as String?;
    if (id == _sectionFor) { return; }
    _sectionFor = id;
    if (id == null) { if (mounted) { setState(() => sectionLabel = null); } return; }
    try {
      final s = await sb.from('sections').select('name,grade_level').eq('id', id).single();
      if (mounted) { setState(() => sectionLabel = 'Grade ${s['grade_level']} · ${s['name']}'); }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final s = st;
    if (s == null) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
    final id = s['id'] as String;
    return StreamBuilder<int>(
      stream: unread, initialData: 0,
      builder: (c, u) => HamburgerShell(
        initialId: 'attendance',
        header: DrawerProfileHeader(name: '${widget.profile['full_name']}', photo: widget.profile['photo_url'] as String?, line1: 'Student ID ${s['student_no']}', line2: sectionLabel ?? 'Waiting for your adviser to add you to a section'),
        entries: [
          ShellItem(id: 'attendance', label: 'Attendance', icon: Icons.how_to_reg, build: () => AttendanceView(id)),
          ShellItem(id: 'grades', label: 'Grades', icon: Icons.grade, build: () => GradesView(id)),
          ShellItem(id: 'schedule', label: 'Schedule', icon: Icons.calendar_month, build: () => ScheduleView(s['section_id'] as String?)),
          ShellItem(id: 'alerts', label: 'Notifications', icon: Icons.notifications, badge: u.data ?? 0, build: () => const NotificationsView()),
          ShellItem(id: 'profile', label: 'Profile', icon: Icons.person, build: () => const ProfileTab()),
        ],
      ),
    );
  }
}
