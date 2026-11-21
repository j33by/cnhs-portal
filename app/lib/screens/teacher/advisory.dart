import 'package:flutter/material.dart';
import '../student/room_screen.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../widgets/shared.dart';
import 'device_links.dart';
import 'homeroom_tab.dart';
import '../../widgets/keep_alive.dart';
import '../../core/offline.dart';

Future<String?> _ask(BuildContext c, String title, String label) async {
  final t = TextEditingController();
  return showDialog<String>(context: c, builder: (_) => AlertDialog(title: Text(title), content: TextField(controller: t, autofocus: true, decoration: InputDecoration(labelText: label)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, t.text.trim()), child: const Text('OK'))]));
}
void _run(BuildContext c, Future<dynamic> f) async { try { await f; } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(errorText(e)))); } }

class SectionScreen extends StatelessWidget {
  final Map<String, dynamic> section; const SectionScreen({super.key, required this.section});
  @override
  Widget build(BuildContext c) => DefaultTabController(length: 3, child: Scaffold(
        appBar: AppBar(title: Text('Advisory · Grade ${section['grade_level']} ${section['name']}'), actions: [IconButton(tooltip: 'Room', icon: const Icon(Icons.meeting_room_outlined), onPressed: () => pushOnce(c, MaterialPageRoute(builder: (_) => RoomScreen(sectionId: '${section['id']}'))))], bottom: const TabBar(tabs: [Tab(text: 'Students'), Tab(text: 'Schedule'), Tab(text: 'Homeroom')])),
        body: TabBarView(children: [KeepTabAlive(child: _Students(section['id'])), KeepTabAlive(child: _Schedule(section['id'])), KeepTabAlive(child: HomeroomTab(sectionId: section['id']))])));
}

class _Students extends StatelessWidget {
  final String sid; const _Students(this.sid);
  @override
  Widget build(BuildContext c) => Scaffold(
        floatingActionButton: FloatingActionButton(child: const Icon(Icons.person_add), onPressed: () async { final id = await _ask(c, 'Add student', 'Student ID'); if (id != null && c.mounted) _run(c, Api.post('/api/sections/$sid/students', {'student_no': id})); }),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: liveStream('students|section_id=${sid}|o', () => sb.from('students').stream(primaryKey: ['id']).eq('section_id', sid).order('last_name')),
          builder: (c, s) => !s.hasData ? const Center(child: CircularProgressIndicator()) : ListView(children: [for (final x in s.data!) ListTile(
            title: Text('${x['last_name']}, ${x['first_name']}'), subtitle: Text('${x['student_no']}  ·  device #${x['biometric_id']}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.fingerprint), tooltip: 'Link existing device ID', onPressed: () => linkDeviceDialog(c, studentId: x['id'], studentName: '${x['first_name']} ${x['last_name']}')),
              IconButton(icon: const Icon(Icons.edit), onPressed: () async { final a = await _ask(c, 'Edit address', 'Address'); if (a != null && c.mounted) _run(c, Api.patch('/api/students/${x['id']}', {'address': a})); }),
              IconButton(icon: const Icon(Icons.person_remove, color: Colors.red), onPressed: () => _run(c, Api.delete('/api/sections/$sid/students/${x['id']}')))]),
            onTap: () => pushOnce(c, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text('${x['first_name']} attendance')), body: AttendanceView(x['id'])))))])),
      );
}

class _Schedule extends StatelessWidget {
  final String sid; const _Schedule(this.sid);
  Future<void> _add(BuildContext c) async {
    final name = TextEditingController(), code = TextEditingController(), room = TextEditingController(), st = TextEditingController(text: '07:50'), en = TextEditingController(text: '08:50');
    int day = 1; String? teacher;
    final teachers = await sb.from('teacher_names').select('id,first_name,last_name,subjects'); if (!c.mounted) return;
    await showDialog(context: c, builder: (_) => StatefulBuilder(builder: (c2, set) {
      final mine = teacher == null ? <dynamic>[] : ((teachers.firstWhere((t) => t['id'] == teacher)['subjects'] as List?) ?? []);
      return AlertDialog(title: const Text('Add class'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Teacher'), items: [for (final t in teachers) DropdownMenuItem(value: t['id'] as String, child: Text('${t['first_name']} ${t['last_name']}', overflow: TextOverflow.ellipsis))], onChanged: (v) => set(() => teacher = v)),
        if (mine.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, children: [for (final s in mine) ActionChip(label: Text('${s['code']} · ${s['name']}'), onPressed: () { name.text = '${s['name']}'; code.text = '${s['code']}'; })])),
        Row(children: [SizedBox(width: 100, child: TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code'))), const SizedBox(width: 8), Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Subject name')))]),
        DropdownButtonFormField<int>(initialValue: day, decoration: const InputDecoration(labelText: 'Day'), items: [for (var d = 1; d <= 6; d++) DropdownMenuItem(value: d, child: Text(kDays[d]))], onChanged: (v) => day = v!),
        Row(children: [Expanded(child: TextField(controller: st, decoration: const InputDecoration(labelText: 'Start HH:MM'))), const SizedBox(width: 8), Expanded(child: TextField(controller: en, decoration: const InputDecoration(labelText: 'End HH:MM')))]),
        TextField(controller: room, decoration: const InputDecoration(labelText: 'Room')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Cancel')), FilledButton(onPressed: () async {
        final nm = name.text.trim(), cd = code.text.trim().toUpperCase().replaceAll(' ', '_');
        if (nm.isEmpty || cd.isEmpty) { ScaffoldMessenger.of(c2).showSnackBar(const SnackBar(content: Text('Type the subject code and name'))); return; }
        Navigator.pop(c2);
        try {
          await Api.post('/api/sections/$sid/subjects', {'code': cd, 'name': nm, 'teacher_id': teacher});
          final sub = await sb.from('subjects').select('id').eq('code', cd).single();
          await Api.post('/api/sections/$sid/schedules', {'subject_id': sub['id'], 'teacher_id': teacher, 'day_of_week': day, 'start_time': st.text, 'end_time': en.text, 'room': room.text.isEmpty ? null : room.text});
        } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(errorText(e)))); }
      }, child: const Text('Save'))]);
    }));
  }
  @override
  Widget build(BuildContext c) => Scaffold(floatingActionButton: FloatingActionButton(child: const Icon(Icons.add), onPressed: () => _add(c)), body: ScheduleView(sid));
}
