import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../core/streams.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/keep_alive.dart';
import '../../widgets/shared.dart';
import '../profile_screen.dart';

/// Parent app: hamburger menu with one entry per linked child. Sign out is at the bottom of the Profile screen.
class ParentHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const ParentHome({super.key, required this.profile});
  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  List<Map<String, dynamic>> links = [];
  final kids = <String, Map<String, dynamic>>{};
  bool loaded = false;
  StreamSubscription<dynamic>? _links, _kids;
  late final Stream<int> unread = unreadStream();
  final idCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _links = sb.from('parent_links').stream(primaryKey: ['id']).eq('parent_id', sb.auth.currentUser!.id).listen((rows) { if (mounted) { setState(() { links = rows; loaded = true; }); } });
    // Row-level security only returns students whose link was approved, so this is exactly "my children" (live).
    _kids = sb.from('students').stream(primaryKey: ['id']).listen((rows) { if (mounted) { setState(() { kids..clear()..addAll({for (final r in rows) r['id'] as String: r}); }); } });
  }
  @override
  void dispose() { _links?.cancel(); _kids?.cancel(); idCtl.dispose(); super.dispose(); }

  Future<void> _bind() async {
    try {
      await Api.post('/api/parent/bind', {'student_no': idCtl.text});
      idCtl.clear();
      if (mounted) { Navigator.pop(context); toast('Request sent. A teacher will review it.'); }
    } catch (e) { toastError(e); }
  }

  void _dialog() => showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Link your child'),
      content: TextField(controller: idCtl, autofocus: true, decoration: const InputDecoration(labelText: 'Student ID (e.g. 202627-48213)')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _bind, child: const Text('Send request'))]));

  @override
  Widget build(BuildContext c) {
    if (!loaded) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
    final approved = links.where((l) => l['status'] == 'approved').toList()..sort((a, b) => '${a['student_name']}'.compareTo('${b['student_name']}'));
    final pending = links.where((l) => l['status'] == 'pending').length;
    String nameOf(Map<String, dynamic> l) => '${kids[l['student_id']]?['first_name'] ?? '${l['student_name'] ?? 'Child'}'.split(' ').first}';
    return StreamBuilder<int>(
      stream: unread, initialData: 0,
      builder: (c, u) => HamburgerShell(
        header: DrawerProfileHeader(name: '${widget.profile['full_name']}', photo: widget.profile['photo_url'] as String?, line1: 'Parent / Guardian', line2: '${widget.profile['email'] ?? ''}'),
        entries: [
          const ShellHeading('My children'),
          for (final l in approved) ShellItem(
            id: 'kid:${l['student_id']}', label: nameOf(l), icon: Icons.child_care,
            leading: CircleAvatar(radius: 14, child: Text(nameOf(l).isEmpty ? '?' : nameOf(l)[0].toUpperCase())),
            build: () => _ChildPage(student: kids[l['student_id']], link: l),
          ),
          if (approved.isEmpty) const ShellHeading('No linked child yet'),
          ShellAction('Link a child', Icons.person_add, _dialog),
          const ShellHeading('Account'),
          ShellItem(id: 'requests', label: 'Requests', icon: Icons.link, badge: pending, build: () => _Requests(links: links)),
          ShellItem(id: 'alerts', label: 'Notifications', icon: Icons.notifications, badge: u.data ?? 0, build: () => const NotificationsView()),
          ShellItem(id: 'profile', label: 'Profile', icon: Icons.person, build: () => const ProfileTab()),
        ],
      ),
    );
  }
}

class _ChildPage extends StatelessWidget {
  final Map<String, dynamic>? student; final Map<String, dynamic> link;
  const _ChildPage({required this.student, required this.link});
  @override
  Widget build(BuildContext c) {
    final s = student;
    if (s == null) { return const Center(child: CircularProgressIndicator()); }
    final id = s['id'] as String;
    return DefaultTabController(length: 3, child: Column(children: [
      ListTile(dense: true, leading: const Icon(Icons.badge), title: Text('${s['first_name']} ${s['last_name']}'), subtitle: Text('Student ID ${s['student_no']}  ·  Grade ${s['grade_level']}')),
      const TabBar(tabs: [Tab(text: 'Attendance'), Tab(text: 'Grades'), Tab(text: 'Schedule')]),
      Expanded(child: TabBarView(children: [
        KeepAlive(child: AttendanceView(id)), KeepAlive(child: GradesView(id)), KeepAlive(child: ScheduleView(s['section_id'] as String?)),
      ])),
    ]));
  }
}

class _Requests extends StatelessWidget {
  final List<Map<String, dynamic>> links;
  const _Requests({required this.links});
  @override
  Widget build(BuildContext c) {
    if (links.isEmpty) { return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Open the menu and choose "Link a child", then enter your child\'s Student ID. A teacher approves the link.', textAlign: TextAlign.center))); }
    return ListView(children: [for (final l in links) ListTile(
      leading: const Icon(Icons.child_care),
      title: Text('${l['student_name'] ?? 'Student'}'), subtitle: Text('${l['student_no'] ?? ''}${l['status'] == 'pending' ? '  ·  waiting for a teacher' : l['status'] == 'rejected' ? '  ·  declined' : ''}'),
      trailing: Chip(label: Text('${l['status']}'), backgroundColor: l['status'] == 'approved' ? Colors.green.shade100 : l['status'] == 'pending' ? Colors.amber.shade100 : Colors.red.shade100),
    )]);
  }
}
