import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import 'class_common.dart';
import 'device_links.dart';
import '../../core/offline.dart';
import '../../core/img.dart';

/// Everyone enrolled in the section (boys first, then girls, alphabetical), live. Search, photos, details, absences in this subject.
class ClassStudentsTab extends StatefulWidget {
  final String sectionId, subjectId; final bool isAdviser;
  const ClassStudentsTab({super.key, required this.sectionId, required this.subjectId, this.isAdviser = false});
  @override
  State<ClassStudentsTab> createState() => _ClassStudentsState();
}

class _ClassStudentsState extends State<ClassStudentsTab> {
  final search = TextEditingController();
  Map<String, dynamic>? section;
  String? adviserName;
  final photos = <String, String?>{};
  Map<String, int> absences = {};
  int free = 10;

  @override
  void initState() { super.initState(); _loadExtras(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> _loadExtras() async {
    try {
      final yid = await currentYearId();
      final sec = await sb.from('sections').select('id,name,grade_level,homeroom,adviser_id').eq('id', widget.sectionId).single();
      String? adv;
      if (sec['adviser_id'] != null) { final a = await sb.from('teacher_names').select('first_name,last_name').eq('id', sec['adviser_id']).maybeSingle(); if (a != null) { adv = '${a['first_name']} ${a['last_name']}'; } }
      final base = <String, Object>{'section_id': widget.sectionId, 'subject_id': widget.subjectId, 'school_year_id': yid};
      final r = await Future.wait<Rows>([sb.from('class_attendance').select('student_id').match({...base, 'status': 'A'}), sb.from('class_policy').select().match(base)]);
      final ab = <String, int>{};
      for (final a in r[0]) { final k = a['student_id'] as String; ab[k] = (ab[k] ?? 0) + 1; }
      if (mounted) setState(() { section = sec; adviserName = adv; absences = ab; free = r[1].isEmpty ? 10 : r[1].first['free_absences'] as int; });
    } catch (e) { toastError(e); }
  }

  Future<void> _ensurePhotos(List<String> ids) async {
    final need = ids.where((i) => !photos.containsKey(i)).toList();
    if (need.isEmpty) return;
    for (final i in need) { photos[i] = null; }
    try {
      final r = await sb.from('profiles').select('id,photo_url').inFilter('id', need);
      if (mounted) setState(() { for (final p in r) { photos[p['id'] as String] = p['photo_url'] as String?; } });
    } catch (_) {}
  }

  Future<void> _claim() async {
    try { await Api.post('/api/sections/${widget.sectionId}/claim'); toast('You are now the adviser of this section'); await _loadExtras(); } catch (e) { toastError(e); }
  }

  String _name(Map<String, dynamic> x) => '${x['last_name']}, ${x['first_name']}${(x['middle_name'] ?? '').toString().isEmpty ? '' : ' ${x['middle_name']}'}';

  void _details(Map<String, dynamic> x) {
    final a = absences[x['id']] ?? 0;
    Widget row(IconData i, String k, String v) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(i, size: 20), title: Text(k), subtitle: Text(v.isEmpty ? '—' : v));
    showDialog(context: context, builder: (c2) => AlertDialog(
      title: Row(children: [
        CircleAvatar(radius: 24, backgroundImage: photos[x['id']] != null ? CachedNetImage(photos[x['id']]!) : null, child: photos[x['id']] == null ? Text('${x['first_name']}'.isEmpty ? '?' : '${x['first_name']}'[0]) : null),
        const SizedBox(width: 12), Expanded(child: Text(_name(x), style: const TextStyle(fontSize: 17))),
      ]),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.badge, size: 20), title: const Text('Student ID'), subtitle: SelectableText('${x['student_no']}'),
            trailing: IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () { Clipboard.setData(ClipboardData(text: '${x['student_no']}')); toast('ID copied'); })),
        row(Icons.person, 'Sex · Age', '${x['sex'] == 'M' ? 'Male' : x['sex'] == 'F' ? 'Female' : ''}${x['age'] != null ? ' · ${x['age']} years' : ''}'),
        row(Icons.cake, 'Birthdate', '${x['birthdate'] ?? ''}'),
        row(Icons.home, 'Address', '${x['address'] ?? ''}'),
        row(Icons.family_restroom, 'Parent / guardian', '${x['guardian_name'] ?? ''}${(x['guardian_contact'] ?? '').toString().isEmpty ? '' : '  ·  ${x['guardian_contact']}'}'),
        ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_busy, size: 20), title: const Text('Absences in this subject'), subtitle: Text('$a of $free allowed'), trailing: standingChip(a, free)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Close'))],
    ));
  }

  // ---- adviser only: manage who is in the section
  Future<String?> _prompt(String title, String label, {String initial = ''}) {
    final t = TextEditingController(text: initial);
    return showDialog<String>(context: context, builder: (c2) => AlertDialog(
      title: Text(title), content: TextField(controller: t, autofocus: true, decoration: InputDecoration(labelText: label)),
      actions: [TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c2, t.text.trim()), child: const Text('OK'))]));
  }

  Future<void> _addStudent() async {
    final id = await _prompt('Add a student', 'Student ID (e.g. 202627-48213)');
    if (id == null || id.isEmpty) { return; }
    try { await Api.post('/api/sections/${widget.sectionId}/students', {'student_no': id}); toast('Student added to the section'); } catch (e) { toastError(e); }
  }

  Future<void> _menu(Map<String, dynamic> x, String v) async {
    try {
      if (v == 'device') { await linkDeviceDialog(context, studentId: x['id'] as String, studentName: _name(x)); }
      else if (v == 'address') {
        final a = await _prompt('Edit address', 'Address', initial: '${x['address'] ?? ''}');
        if (a != null) { await Api.patch('/api/students/${x['id']}', {'address': a}); toast('Address updated'); }
      } else if (v == 'remove') {
        final ok = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(title: const Text('Remove from section?'), content: Text('${_name(x)} will no longer be in this section. Their grades and attendance are kept.'),
            actions: [TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('Remove'))]));
        if (ok == true) { await Api.delete('/api/sections/${widget.sectionId}/students/${x['id']}'); toast('Removed from the section'); }
      }
    } catch (e) { toastError(e); }
  }

  Widget _header(int total, int shown) {
    final myId = sb.auth.currentUser?.id;
    final adviserId = section?['adviser_id'];
    return Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (section != null && adviserId == null) Card(color: Colors.amber.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Icon(Icons.info_outline), const SizedBox(width: 10),
        const Expanded(child: Text('This section has no adviser yet. The adviser can add students and take homeroom attendance.')),
        const SizedBox(width: 8), FilledButton.tonal(onPressed: _claim, child: const Text('Become adviser')),
      ]))),
      Row(children: [
        Expanded(child: Text(section == null ? '' : 'Grade ${section!['grade_level']} · ${section!['name']}${(section!['homeroom'] ?? '').toString().isEmpty ? '' : ' · Room ${section!['homeroom']}'}', style: Theme.of(context).textTheme.titleSmall)),
        if (adviserId != null) Chip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.school, size: 16), label: Text(adviserId == myId ? 'You are the adviser' : 'Adviser: ${adviserName ?? ''}', style: const TextStyle(fontSize: 12))),
      ]),
      if (widget.isAdviser) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(onPressed: _addStudent, icon: const Icon(Icons.person_add), label: const Text('Add student by ID')))),
      const SizedBox(height: 8),
      TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder(),
          hintText: 'Search $total student${total == 1 ? '' : 's'} by name or ID', suffixIcon: search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(search.clear)))),
      const SizedBox(height: 4),
      if (search.text.isNotEmpty) Text('$shown of $total shown', style: const TextStyle(fontSize: 12)),
    ]));
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: liveStream('students|section_id=${widget.sectionId}', () => sb.from('students').stream(primaryKey: ['id']).eq('section_id', widget.sectionId)),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final all = s.data!.where((x) => x['status'] == 'enrolled').toList()
            ..sort((a, b) { final g = '${b['sex']}'.compareTo('${a['sex']}'); return g != 0 ? g : '${a['last_name']} ${a['first_name']}'.compareTo('${b['last_name']} ${b['first_name']}'); });
          _ensurePhotos([for (final x in all) x['id'] as String]);
          final q = search.text.trim().toLowerCase();
          final list = q.isEmpty ? all : all.where((x) => '${_name(x)} ${x['first_name']} ${x['last_name']} ${x['student_no']}'.toLowerCase().contains(q)).toList();
          return Column(children: [
            _header(all.length, list.length),
            Expanded(child: all.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No students in this section yet. Students choose their section when they sign up, or the adviser adds them by Student ID.', textAlign: TextAlign.center)))
                : list.isEmpty ? const Center(child: Text('No student matches your search'))
                : ListView.separated(
                    itemCount: list.length, separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final x = list[i]; final a = absences[x['id']] ?? 0; final photo = photos[x['id']];
                      return ListTile(
                        leading: CircleAvatar(backgroundImage: photo != null ? CachedNetImage(photo) : null, child: photo == null ? Text('${x['first_name']}'.isEmpty ? '?' : '${x['first_name']}'[0]) : null),
                        title: Text(_name(x)), subtitle: Text('ID ${x['student_no']}  ·  ${x['sex'] == 'M' ? 'Male' : 'Female'}${x['age'] != null ? '  ·  ${x['age']} yrs' : ''}'),
                        trailing: widget.isAdviser
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                if (a > 0) standingChip(a, free),
                                PopupMenuButton<String>(onSelected: (v) => _menu(x, v), itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'device', child: Text('Link device ID')), PopupMenuItem(value: 'address', child: Text('Edit address')), PopupMenuItem(value: 'remove', child: Text('Remove from section'))]),
                              ])
                            : (a == 0 ? null : standingChip(a, free)),
                        onTap: () => _details(x),
                      );
                    })),
          ]);
        });
}
