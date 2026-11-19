import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/messenger.dart';
import '../core/offline.dart';
import '../core/session.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/subjects_editor.dart';
import '../widgets/ui.dart';

/// First sign-in: who are you -> a short form -> your ID.
class OnboardingScreen extends StatefulWidget { const OnboardingScreen({super.key}); @override State<OnboardingScreen> createState() => _O(); }
class _O extends State<OnboardingScreen> {
  String? role;
  static const _roles = [
    ['student', 'Student', 'See your schedule, attendance and grades', Icons.school_outlined],
    ['parent', 'Parent or guardian', 'Follow your child at school', Icons.family_restroom_outlined],
    ['teacher', 'Teacher', 'Manage classes, attendance and grades', Icons.badge_outlined],
  ];
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          leading: role == null ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => role = null)),
          title: Text(role == null ? 'Welcome' : switch (role) { 'student' => 'Student sign-up', 'teacher' => 'Teacher sign-up', _ => 'Parent sign-up' }),
          actions: [TextButton(onPressed: () => appSignOut(), child: const Text('Sign out'))],
        ),
        body: role == null
            ? Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: ListView(padding: const EdgeInsets.all(20), children: [
                const SizedBox(height: 8),
                Text('Who are you?', style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                for (final r in _roles) Padding(padding: const EdgeInsets.only(bottom: 10), child: SoftCard(
                  onTap: () => setState(() => role = r[0] as String), padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    CircleAvatar(radius: 24, backgroundColor: Theme.of(c).colorScheme.primaryContainer, child: Icon(r[3] as IconData, color: Theme.of(c).colorScheme.primary)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r[1] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), Text(r[2] as String, style: TextStyle(color: Theme.of(c).hintColor, fontSize: 13))])),
                    const Icon(Icons.chevron_right),
                  ]),
                )),
              ])))
            : switch (role) { 'teacher' => const _TeacherForm(), 'student' => const _StudentForm(), _ => const _ParentForm() },
      );
}

mixin _FormHelpers<T extends StatefulWidget> on State<T> {
  final key = GlobalKey<FormState>(); final v = <String, dynamic>{}; bool busy = false;

  InputDecoration deco(String label, {bool optional = false, String? hint}) => InputDecoration(
      labelText: optional ? '$label (optional)' : label, hintText: hint, filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none));

  Widget tf(String k, String label, {bool req = true, TextInputType? type, int max = 1, String? hint}) => Padding(padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(decoration: deco(label, optional: !req, hint: hint), keyboardType: type, maxLines: max, textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
          validator: (s) => req && (s == null || s.trim().isEmpty) ? 'Required' : null, onSaved: (s) => v[k] = (s ?? '').trim()));

  Widget group(BuildContext c, String title, List<Widget> kids) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title, style: Theme.of(c).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))), ...kids]));

  Future<void> submit(String path, {Map<String, dynamic> Function()? fix, bool validate = true}) async {
    if (validate) { if (!key.currentState!.validate()) return; key.currentState!.save(); }
    if (fix != null) v.addAll(fix());
    setState(() => busy = true);
    try {
      final r = await Api.post(path, v);
      final id = r['teacher_no'] ?? r['student_no'];
      if (!mounted) return;
      if (id != null) {
        await showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
          icon: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 40),
          title: const Text("You're registered"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(r['student_no'] != null ? 'Your Student ID' : 'Your Teacher ID', style: TextStyle(color: Theme.of(context).hintColor)), const SizedBox(height: 6),
            SelectableText('$id', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: .5)),
            if (r['placed'] != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text('Placed in ${r['placed']}${(r['extras'] ?? 0) > 0 ? ' · ${r['extras']} subject${r['extras'] == 1 ? '' : 's'} from other sections' : ''}', textAlign: TextAlign.center))
            else if (r['student_no'] != null) const Padding(padding: EdgeInsets.only(top: 14), child: Text('Your teachers will add you to a section.', textAlign: TextAlign.center)),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Continue'))]));
      }
      profileReload.value++;                                    // the gate reloads the profile and opens the right home screen
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)))); }
    if (mounted) setState(() => busy = false);
  }
  Widget submitBtn(VoidCallback f, [String label = 'Register']) => FilledButton(onPressed: busy ? null : f, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(label));

  Widget page(Widget child) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child));
}

// ------------------------------------------------------------------ teacher
class _TeacherForm extends StatefulWidget { const _TeacherForm(); @override State<_TeacherForm> createState() => _TF(); }
class _TF extends State<_TeacherForm> with _FormHelpers {
  List<Map<String, String>> subjects = []; final grades = <int>{};
  @override
  Widget build(BuildContext c) => Form(key: key, child: page(SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AvatarPicker(onUploaded: (u) => v['photo_url'] = u)), const SizedBox(height: 18),
        group(c, 'About you', [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: tf('first_name', 'First name')), const SizedBox(width: 10), Expanded(child: tf('last_name', 'Last name'))]),
          tf('contact_no', 'Contact number', type: TextInputType.phone), tf('address', 'Address', max: 2), tf('birthdate', 'Birthdate', req: false, hint: 'YYYY-MM-DD'),
        ]),
        group(c, 'What you teach', [
          const Text('Subjects (up to 5)', style: TextStyle(fontSize: 13)), const SizedBox(height: 6),
          SubjectsEditor(onChanged: (x) => subjects = x), const SizedBox(height: 14),
          const Text('Grade levels', style: TextStyle(fontSize: 13)), const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [for (var g = 7; g <= 12; g++) FilterChip(label: Text('Grade $g'), selected: grades.contains(g), onSelected: (on) => setState(() { if (on && grades.length < 5) { grades.add(g); } else { grades.remove(g); } }))]),
        ]),
        const SizedBox(height: 6),
        submitBtn(() {
          final filled = subjects.where((s) => (s['code'] ?? '').isNotEmpty || (s['name'] ?? '').isNotEmpty).toList();
          if (filled.isEmpty || filled.any((s) => (s['code'] ?? '').isEmpty || (s['name'] ?? '').isEmpty)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a code and a name for each subject'))); return; }
          if (grades.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick at least one grade level'))); return; }
          submit('/api/onboarding/teacher', fix: () => {'subjects': filled, 'grade_levels': grades.toList()});
        }),
      ]))));
}

// ------------------------------------------------------------------ parent
class _ParentForm extends StatefulWidget { const _ParentForm(); @override State<_ParentForm> createState() => _PF(); }
class _PF extends State<_ParentForm> with _FormHelpers {
  @override
  Widget build(BuildContext c) => Form(key: key, child: page(SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AvatarPicker(onUploaded: (u) => v['photo_url'] = u)), const SizedBox(height: 18),
        tf('full_name', 'Full name'), tf('contact_no', 'Contact number', req: false, type: TextInputType.phone),
        Padding(padding: const EdgeInsets.only(bottom: 18), child: Text("After this, link your child with their Student ID.", style: TextStyle(color: Theme.of(c).hintColor, fontSize: 13))),
        submitBtn(() => submit('/api/onboarding/parent')),
      ]))));
}

// ------------------------------------------------------------------ student: 3 short steps
class _StudentForm extends StatefulWidget { const _StudentForm(); @override State<_StudentForm> createState() => _SF(); }
class _SF extends State<_StudentForm> with _FormHelpers {
  int step = 0, grade = 7; String sex = 'M', mode = 'section';
  final c = <String, TextEditingController>{for (final k in ['first', 'middle', 'last', 'age', 'birth', 'address', 'lrn', 'gname', 'gcontact']) k: TextEditingController()};
  final search = TextEditingController();
  String? sectionId; final picks = <String>{};                       // "sectionId|subjectId"
  List<Map<String, dynamic>> offers = [];                            // one row per class: section + subject + teacher
  final teachers = <String, String>{};
  bool loadingOffers = true;

  @override
  void initState() { super.initState(); _loadOffers(); }
  @override
  void dispose() { for (final x in c.values) { x.dispose(); } search.dispose(); super.dispose(); }

  Future<void> _loadOffers() async {
    setState(() { loadingOffers = true; sectionId = null; picks.clear(); });
    try {
      final y = await cachedRow('year-id-row', () => sb.from('school_years').select('id').eq('is_current', true).maybeSingle());
      final r = await cachedRows('offers|$grade', () => sb.from('section_subjects').select('section_id,subject_id,teacher_id,sections!inner(name,grade_level,school_year_id),subjects(code,name)').eq('sections.grade_level', grade).eq('sections.school_year_id', y!['id']));
      final t = await cachedRows('teacher_names', () => sb.from('teacher_names').select('id,first_name,last_name'));
      teachers..clear()..addAll({for (final x in t) '${x['id']}': '${x['first_name']} ${x['last_name']}'});
      // sections with no subjects yet still need to be listed
      final secs = await cachedRows('secs|$grade', () => sb.from('sections').select('id,name').eq('school_year_id', y!['id']).eq('grade_level', grade).order('name'));
      if (mounted) { setState(() { offers = r; allSections = secs; loadingOffers = false; }); }
    } catch (_) { if (mounted) { setState(() => loadingOffers = false); } }
  }
  List<Map<String, dynamic>> allSections = [];

  List<Map<String, dynamic>> _subjectsOf(String sid) => [for (final o in offers) if (o['section_id'] == sid) o];
  String _secName(Map<String, dynamic> o) => '${(o['sections'] as Map)['name']}';
  String _subName(Map<String, dynamic> o) => '${(o['subjects'] as Map)['name']}';

  Widget _field(String k, String label, {bool optional = false, TextInputType? type, int lines = 1, String? hint}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
      controller: c[k], decoration: deco(label, optional: optional, hint: hint), keyboardType: type, maxLines: lines, textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
      validator: (s) => !optional && (s == null || s.trim().isEmpty) ? 'Required' : null));

  bool _next() {
    if (!(key.currentState?.validate() ?? false)) { return false; }
    setState(() => step++); return true;
  }

  Widget _stepBar(BuildContext x) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Row(children: [
        for (var i = 0; i < 2; i++) ...[
          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: i <= step ? Theme.of(x).colorScheme.primary : Theme.of(x).dividerColor, borderRadius: BorderRadius.circular(4)))),
          if (i < 1) const SizedBox(width: 6),
        ],
      ]));

  Widget _about(BuildContext x) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AvatarPicker(onUploaded: (u) => v['photo_url'] = u)), const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _field('first', 'First name')), const SizedBox(width: 10), Expanded(child: _field('last', 'Last name'))]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _field('age', 'Age', type: TextInputType.number)), const SizedBox(width: 10), Expanded(child: _sexPicker(x))]),
        _field('address', 'Address', lines: 2),
        Theme(data: Theme.of(x).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
          tilePadding: EdgeInsets.zero, title: const Text('More details', style: TextStyle(fontWeight: FontWeight.w600)), childrenPadding: const EdgeInsets.only(top: 4),
          children: [_field('middle', 'Middle name', optional: true), _field('birth', 'Birthdate', optional: true, hint: 'YYYY-MM-DD'), _field('lrn', 'LRN', optional: true, type: TextInputType.number),
            _field('gname', 'Parent or guardian', optional: true), _field('gcontact', 'Guardian contact', optional: true, type: TextInputType.phone)],
        )),
      ]);

  Widget _sexPicker(BuildContext x) => Padding(padding: const EdgeInsets.only(bottom: 12), child: SegmentedButton<String>(
        showSelectedIcon: false, style: const ButtonStyle(visualDensity: VisualDensity.standard),
        segments: const [ButtonSegment(value: 'M', label: Text('Boy')), ButtonSegment(value: 'F', label: Text('Girl'))], selected: {sex}, onSelectionChanged: (s) => setState(() => sex = s.first)));

  Widget _sectionMode(BuildContext x) {
    if (allSections.isEmpty) { return const Padding(padding: EdgeInsets.all(16), child: Text('No sections for this grade yet. Choose "Add me later".')); }
    return Column(children: [for (final s in allSections) () {
      final id = '${s['id']}', on = sectionId == id, subs = _subjectsOf(id);
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: SoftCard(
        onTap: () => setState(() => sectionId = on ? null : id), border: on ? Theme.of(x).colorScheme.primary : null, color: on ? Theme.of(x).colorScheme.primaryContainer.withValues(alpha: .35) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Text(subs.isEmpty ? 'No subjects yet' : '${subs.length} subject${subs.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12.5, color: Theme.of(x).hintColor)),
            const SizedBox(width: 8), Icon(on ? Icons.check_circle : Icons.circle_outlined, color: on ? Theme.of(x).colorScheme.primary : Theme.of(x).hintColor),
          ]),
          if (on && subs.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 6, runSpacing: 6, children: [for (final o in subs) Chip(visualDensity: VisualDensity.compact, label: Text(teachers[o['teacher_id']] == null ? _subName(o) : '${_subName(o)} · ${teachers[o['teacher_id']]}', style: const TextStyle(fontSize: 12)), padding: EdgeInsets.zero)])),
        ]),
      ));
    }()]);
  }

  Widget _subjectMode(BuildContext x) {
    final q = search.text.trim().toLowerCase();
    final shown = offers.where((o) => q.isEmpty || '${_subName(o)} ${(o['subjects'] as Map)['code']} ${_secName(o)} ${teachers[o['teacher_id']] ?? ''}'.toLowerCase().contains(q)).toList()
      ..sort((a, b) { final s = _subName(a).compareTo(_subName(b)); return s != 0 ? s : _secName(a).compareTo(_secName(b)); });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: search, onChanged: (_) => setState(() {}), decoration: deco('Search subject, section or teacher').copyWith(prefixIcon: const Icon(Icons.search), suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(search.clear)))),
      if (picks.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 6, runSpacing: 4, children: [
        for (final p in picks) () { final o = offers.firstWhere((e) => '${e['section_id']}|${e['subject_id']}' == p, orElse: () => {}); if (o.isEmpty) { return const SizedBox.shrink(); }
          return InputChip(visualDensity: VisualDensity.compact, label: Text('${_subName(o)} · ${_secName(o)}', style: const TextStyle(fontSize: 12)), onDeleted: () => setState(() => picks.remove(p))); }(),
      ])),
      const SizedBox(height: 8),
      if (shown.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Center(child: Text(offers.isEmpty ? 'No subjects offered for this grade yet.' : 'No match', style: TextStyle(color: Theme.of(x).hintColor)))),
      for (final o in shown.take(40)) () {
        final id = '${o['section_id']}|${o['subject_id']}', on = picks.contains(id);
        return CheckboxListTile(
          dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.trailing, value: on, onChanged: (_) => setState(() { if (on) { picks.remove(id); } else { picks.add(id); } }),
          title: Text(_subName(o), style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${_secName(o)} · ${teachers[o['teacher_id']] ?? 'Teacher TBA'}'),
        );
      }(),
      if (shown.length > 40) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Keep typing to narrow the list', style: TextStyle(color: Theme.of(x).hintColor, fontSize: 12.5))),
    ]);
  }

  Widget _enroll(BuildContext x) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Grade level', style: Theme.of(x).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [for (var g = 7; g <= 12; g++) ChoiceChip(label: Text('$g'), selected: grade == g, onSelected: (_) { if (grade != g) { grade = g; _loadOffers(); } })]),
        const SizedBox(height: 18),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'section', label: Text('Section')), ButtonSegment(value: 'subjects', label: Text('Subjects')), ButtonSegment(value: 'later', label: Text('Later'))],
          selected: {mode}, onSelectionChanged: (s) => setState(() => mode = s.first)),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(switch (mode) {
          'section' => 'Join a section and get all its subjects.',
          'subjects' => "Pick your subjects. You'll be placed in the section that has most of them.",
          _ => 'Your teachers will add you to a section.',
        }, style: TextStyle(color: Theme.of(x).hintColor, fontSize: 13))),
        if (loadingOffers) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (mode == 'section') _sectionMode(x)
        else if (mode == 'subjects') _subjectMode(x)
        else SoftCard(child: Row(children: [Icon(Icons.schedule, color: Theme.of(x).colorScheme.primary), const SizedBox(width: 12), const Expanded(child: Text('You can still use the app. Your schedule shows up once you are added.'))])),
      ]);

  void _register() {
    if (mode == 'section' && sectionId == null) { toast('Choose a section, or pick "Later"'); return; }
    if (mode == 'subjects' && picks.isEmpty) { toast('Pick at least one subject, or choose "Later"'); return; }
    final age = int.tryParse(c['age']!.text.trim());
    v.addAll({'first_name': c['first']!.text.trim(), 'middle_name': c['middle']!.text.trim(), 'last_name': c['last']!.text.trim(), 'birthdate': c['birth']!.text.trim(), 'address': c['address']!.text.trim(),
      'lrn': c['lrn']!.text.trim(), 'guardian_name': c['gname']!.text.trim(), 'guardian_contact': c['gcontact']!.text.trim()});
    submit('/api/onboarding/student', validate: false, fix: () => {
      'grade_level': grade, 'sex': sex, 'age': age,
      'section_id': mode == 'section' ? sectionId : null,
      'subjects': mode == 'subjects' ? [for (final p in picks) {'section_id': p.split('|')[0], 'subject_id': p.split('|')[1]}] : [],
    }, );
  }

  @override
  Widget build(BuildContext x) => Form(key: key, child: page(Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: _stepBar(x)),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: step == 0 ? _about(x) : _enroll(x))),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Row(children: [
          if (step > 0) Padding(padding: const EdgeInsets.only(right: 10), child: OutlinedButton(onPressed: () => setState(() => step--), style: OutlinedButton.styleFrom(minimumSize: const Size(90, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Text('Back'))),
          Expanded(child: step == 0 ? submitBtn(() { _next(); }, 'Next') : submitBtn(_register)),
        ]))),
      ])));
}
