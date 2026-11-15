import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../widgets/shared.dart';

class ParentHome extends StatefulWidget { final Map<String, dynamic> profile; const ParentHome({super.key, required this.profile}); @override State<ParentHome> createState() => _P(); }
class _P extends State<ParentHome> {
  final idCtl = TextEditingController();
  Future<void> _bind() async {
    try { await Api.post('/api/parent/bind', {'student_no': idCtl.text}); idCtl.clear(); if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent. A teacher will review it.'))); } }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  void _dialog() => showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Link your child'),
      content: TextField(controller: idCtl, decoration: const InputDecoration(labelText: 'Student ID (e.g. 202627-48213)')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _bind, child: const Text('Send request'))]));

  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('parent_links').stream(primaryKey: ['id']).eq('parent_id', sb.auth.currentUser!.id),
        builder: (c, s) {
          final links = s.data ?? [];
          final ok = links.where((l) => l['status'] == 'approved').toList(), pending = links.where((l) => l['status'] == 'pending').length;
          return DefaultTabController(length: ok.length + 1, child: Scaffold(
            appBar: AppBar(title: const Text('CNHS Parent'), actions: [
              IconButton(icon: const Icon(Icons.person_add), tooltip: 'Link a child', onPressed: _dialog),
              IconButton(icon: const Icon(Icons.notifications), onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Notifications')), body: const NotificationsView())))),
              IconButton(icon: const Icon(Icons.logout), onPressed: () => sb.auth.signOut())],
              bottom: TabBar(isScrollable: true, tabs: [for (final l in ok) _ChildTab(l['student_id']), const Tab(text: 'Requests')])),   // one tab per child
            body: TabBarView(children: [for (final l in ok) _ChildPage(l['student_id']), _Requests(links, pending)])));
        });
}
class _ChildTab extends StatelessWidget {
  final String id; const _ChildTab(this.id);
  @override Widget build(BuildContext c) => FutureBuilder<Map<String, dynamic>>(future: sb.from('students').select('first_name').eq('id', id).single(), builder: (c, s) => Tab(text: s.data?['first_name'] ?? '…'));
}
class _ChildPage extends StatelessWidget {
  final String id; const _ChildPage(this.id);
  @override
  Widget build(BuildContext c) => DefaultTabController(length: 3, child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Attendance'), Tab(text: 'Grades'), Tab(text: 'Schedule')]),
        Expanded(child: TabBarView(children: [AttendanceView(id), GradesView(id),
          FutureBuilder<Map<String, dynamic>>(future: sb.from('students').select('section_id').eq('id', id).single(), builder: (c, s) => s.hasData ? ScheduleView(s.data!['section_id']) : const SizedBox())]))]));
}
class _Requests extends StatelessWidget {
  final List<Map<String, dynamic>> links; final int pending; const _Requests(this.links, this.pending);
  @override
  Widget build(BuildContext c) => links.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Tap the + icon and enter your child\'s Student ID. A teacher approves the link.', textAlign: TextAlign.center)))
      : ListView(children: [for (final l in links) FutureBuilder<Map<String, dynamic>>(future: sb.from('students').select('first_name,last_name,student_no').eq('id', l['student_id']).single(),
          builder: (c, s) => ListTile(title: Text(s.hasData ? '${s.data!['first_name']} ${s.data!['last_name']}' : '…'), subtitle: Text(s.data?['student_no'] ?? ''),
              trailing: Chip(label: Text(l['status']), backgroundColor: l['status'] == 'approved' ? Colors.green.shade100 : l['status'] == 'pending' ? Colors.amber.shade100 : Colors.red.shade100)))]);
}
