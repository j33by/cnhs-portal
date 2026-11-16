import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../widgets/schedule_blocks.dart';
import 'class_common.dart';

/// A teacher creates a class: grade level + one of their subjects + section/room + schedule.
/// A section or room that already exists for that grade (under anyone's advisory) is picked automatically.
class AddClassScreen extends StatefulWidget {
  const AddClassScreen({super.key});
  @override
  State<AddClassScreen> createState() => _AddClassState();
}

class _AddClassState extends State<AddClassScreen> {
  List<int> myGrades = [];
  List<Map<String, dynamic>> mySubjects = [], sections = [];
  Map<String, int> counts = {};
  Map<String, String> advisers = {};
  int? _yid;
  StreamSubscription<dynamic>? _secSub;
  final sectionFocus = FocusNode();
  bool loading = true, saving = false, roomTouched = false;
  int? grade; String? subjectCode; String? error;
  final sectionCtl = TextEditingController(), roomCtl = TextEditingController();
  List<Map<String, dynamic>> blocks = [];

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _secSub?.cancel(); sectionFocus.dispose(); sectionCtl.dispose(); roomCtl.dispose(); super.dispose(); }

  Future<void> _init() async {
    try {
      final uid = sb.auth.currentUser!.id;
      final t = await sb.from('teachers').select('grade_levels').eq('id', uid).single();
      final s = await sb.from('teacher_subjects').select('code,name').eq('teacher_id', uid).order('code');
      myGrades = [for (final g in (t['grade_levels'] as List)) g as int]..sort();
      mySubjects = s;
      if (myGrades.length == 1) { grade = myGrades.first; await _loadSections(); }
      if (mySubjects.length == 1) { subjectCode = mySubjects.first['code'] as String; }
    } catch (e) { toastError(e); }
    if (mounted) setState(() => loading = false);
  }

  /// Sections of the chosen grade for the current school year. Live: a section created by anyone shows up here immediately.
  Future<void> _loadSections() async {
    _secSub?.cancel(); _secSub = null;
    if (grade == null) { return; }
    try {
      _yid ??= await currentYearId();
      await _refreshSections();
      _secSub = sb.from('sections').stream(primaryKey: ['id']).eq('grade_level', grade!).listen((_) => _refreshSections(), onError: (_) {});
    } catch (e) { toastError(e); }
  }

  Future<void> _refreshSections() async {
    final g = grade, y = _yid;
    if (g == null || y == null) { return; }
    try {
      final r = await sb.from('sections').select('id,name,homeroom,grade_level,adviser_id').eq('school_year_id', y).eq('grade_level', g).order('name');
      final advIds = {for (final x in r) if (x['adviser_id'] != null) x['adviser_id'] as String}.toList();
      final ar = advIds.isEmpty ? <Map<String, dynamic>>[] : await sb.from('teacher_names').select('id,first_name,last_name').inFilter('id', advIds);
      final ids = [for (final x in r) x['id']];
      final st = ids.isEmpty ? <Map<String, dynamic>>[] : await sb.from('students').select('section_id').inFilter('section_id', ids).eq('status', 'enrolled');
      final c = <String, int>{};
      for (final x in st) { final k = x['section_id'] as String; c[k] = (c[k] ?? 0) + 1; }
      if (mounted && grade == g) { setState(() { sections = r; counts = c; advisers = {for (final a in ar) a['id'] as String: '${a['first_name']} ${a['last_name']}'}; }); }
    } catch (e) { toastError(e); }
  }

  /// Typing a section name OR a room that already exists for this grade selects that section.
  Map<String, dynamic>? get matched {
    final t = sectionCtl.text.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final s in sections) {
      if ('${s['name']}'.toLowerCase() == t || (s['homeroom'] != null && '${s['homeroom']}'.toLowerCase() == t)) { return s; }
    }
    return null;
  }

  String _adviser(Map<String, dynamic> s) { final n = advisers[s['adviser_id']]; return n == null ? 'no adviser yet' : 'adviser $n'; }
  String _students(Map<String, dynamic> s) { final n = counts[s['id']] ?? 0; return '$n student${n == 1 ? '' : 's'}'; }

  void _onSectionChanged() {
    final m = matched;
    if (m != null && !roomTouched) { roomCtl.text = '${m['homeroom'] ?? ''}'; }
    setState(() => error = null);
  }

  String? _validate() {
    if (grade == null) return 'Choose the grade level';
    if (subjectCode == null) return 'Choose the subject';
    if (sectionCtl.text.trim().isEmpty) return 'Type or choose the section';
    return validateBlocks(blocks);
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) { setState(() => error = err); return; }
    setState(() { saving = true; error = null; });
    try {
      final name = matched != null ? '${matched!['name']}' : sectionCtl.text.trim();
      final r = await Api.post('/api/classes', {
        'grade_level': grade, 'subject_code': subjectCode, 'section_name': name, 'section_id': matched?['id'],
        'room': roomCtl.text.trim(), 'schedules': blocks,
      });
      toast(r['created_section'] == true ? 'Class added. New section "${r['section_name']}" was created.' : 'Class added to ${r['section_name']} (${r['students']} students).');
      if (mounted) Navigator.pop(context, r);
    } catch (e) { setState(() => error = errorText(e)); }
    if (mounted) setState(() => saving = false);
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Card(child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(title, style: Theme.of(context).textTheme.titleMedium)]),
        const SizedBox(height: 14), ...children,
      ])));

  @override
  Widget build(BuildContext c) {
    final m = matched;
    final subj = mySubjects.where((s) => s['code'] == subjectCode).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Add class')),
      body: loading ? const Center(child: CircularProgressIndicator()) : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (mySubjects.isEmpty || myGrades.isEmpty) Card(color: Colors.amber.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(
              mySubjects.isEmpty ? 'You have no subjects yet. Add them in the Subjects tab first.' : 'You have no grade levels yet. Add them in your Profile first.'))),
          _section('Class', Icons.menu_book, [
            DropdownButtonFormField<int>(
              initialValue: grade, decoration: const InputDecoration(labelText: 'Grade level *', border: OutlineInputBorder()),
              items: [for (final g in myGrades) DropdownMenuItem(value: g, child: Text('Grade $g'))],
              onChanged: (v) { setState(() { grade = v; sections = []; counts = {}; error = null; }); _loadSections(); },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: subjectCode, decoration: const InputDecoration(labelText: 'Subject *', border: OutlineInputBorder()),
              items: [for (final s in mySubjects) DropdownMenuItem(value: s['code'] as String, child: Text('${s['code']} · ${s['name']}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() { subjectCode = v; error = null; }),
            ),
          ]),
          _section('Section and room', Icons.meeting_room, [
            RawAutocomplete<Map<String, dynamic>>(
              textEditingController: sectionCtl, focusNode: sectionFocus,
              displayStringForOption: (o) => '${o['name']}',
              optionsBuilder: (v) {
                if (grade == null) { return const Iterable<Map<String, dynamic>>.empty(); }
                final t = v.text.trim().toLowerCase();
                return sections.where((x) => t.isEmpty || '${x['name']}'.toLowerCase().contains(t) || '${x['homeroom'] ?? ''}'.toLowerCase().contains(t));
              },
              onSelected: (o) { roomTouched = false; _onSectionChanged(); },
              fieldViewBuilder: (ctx, ctl, focus, onSubmit) => TextField(
                controller: ctl, focusNode: focus, textCapitalization: TextCapitalization.words, onChanged: (_) => _onSectionChanged(),
                decoration: InputDecoration(
                  labelText: 'Section or room *', border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.arrow_drop_down),
                  hintText: grade == null ? 'Choose the grade level first' : sections.isEmpty ? 'No section yet. Type a name to create one' : 'Tap to pick an existing section, or type a new one',
                ),
              ),
              optionsViewBuilder: (ctx, onSelected, options) => Align(alignment: Alignment.topLeft, child: Material(
                elevation: 6, borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 260, maxWidth: 640), child: ListView.builder(
                  padding: EdgeInsets.zero, shrinkWrap: true, itemCount: options.length,
                  itemBuilder: (c, i) {
                    final x = options.elementAt(i); final rm = (x['homeroom'] ?? '').toString();
                    return ListTile(dense: true, leading: const Icon(Icons.groups), title: Text('${x['name']}${rm.isEmpty ? '' : ' · Room $rm'}'), subtitle: Text('${_adviser(x)} · ${_students(x)}'), onTap: () => onSelected(x));
                  },
                )),
              )),
            ),
            if (grade != null && sections.isNotEmpty) ...[
              const SizedBox(height: 10), Text('Existing sections in Grade $grade', style: Theme.of(c).textTheme.labelMedium),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [for (final s in sections) ChoiceChip(
                selected: m?['id'] == s['id'],
                label: Text('${s['name']}${(s['homeroom'] ?? '').toString().isEmpty ? '' : ' · Room ${s['homeroom']}'} · ${_students(s)}', style: const TextStyle(fontSize: 12)),
                onSelected: (_) { sectionCtl.text = '${s['name']}'; roomTouched = false; _onSectionChanged(); },
              )]),
            ],
            if (sectionCtl.text.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(m != null ? Icons.check_circle : Icons.add_circle_outline, size: 18, color: m != null ? Colors.green.shade700 : Colors.orange.shade800), const SizedBox(width: 6),
              Expanded(child: Text(m != null ? 'Using the existing section "${m['name']}" (${_adviser(m)}, ${_students(m)}). You will see all its students.'
                  : 'No section or room with this name yet. "${sectionCtl.text.trim()}" will be created as a new section for Grade ${grade ?? ''}.',
                  style: TextStyle(fontSize: 12, color: m != null ? Colors.green.shade800 : Colors.orange.shade800))),
            ])),
            const SizedBox(height: 14),
            TextField(controller: roomCtl, onChanged: (_) => roomTouched = true, decoration: const InputDecoration(labelText: 'Room for this class (optional)', hintText: 'e.g. Room 12', border: OutlineInputBorder())),
          ]),
          _section('Schedule', Icons.schedule, [ScheduleBlocks(onChanged: (b) => blocks = b)]),
          if (subj.isNotEmpty && grade != null && sectionCtl.text.trim().isNotEmpty) _section('Review', Icons.fact_check, [
            Text('${subj.first['name']}', style: Theme.of(c).textTheme.titleSmall),
            Text('Grade $grade · ${m != null ? m['name'] : sectionCtl.text.trim()}${roomCtl.text.trim().isEmpty ? '' : ' · ${roomCtl.text.trim()}'}'),
            const SizedBox(height: 8),
            Text(describeBlocks(blocks).isEmpty ? 'No schedule yet' : describeBlocks(blocks), style: const TextStyle(fontSize: 13)),
          ]),
          if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error))),
          FilledButton.icon(
            onPressed: saving || mySubjects.isEmpty || myGrades.isEmpty ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: const Text('Confirm class'),
          ),
          const SizedBox(height: 24),
        ]),
      ))),
    );
  }
}
