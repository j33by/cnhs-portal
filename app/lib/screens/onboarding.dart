import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/messenger.dart';
import '../core/session.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/subjects_editor.dart';

/// Shown right after the first Google sign-in. Role -> form -> automatic ID.
class OnboardingScreen extends StatefulWidget { const OnboardingScreen({super.key}); @override State<OnboardingScreen> createState() => _O(); }
class _O extends State<OnboardingScreen> {
  String? role;
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Welcome'), actions: [TextButton(onPressed: () => sb.auth.signOut(), child: const Text('Sign out'))]),
        body: role == null
            ? ListView(padding: const EdgeInsets.all(24), children: [
                Text('I am a…', style: Theme.of(c).textTheme.headlineSmall), const SizedBox(height: 16),
                for (final r in const [['teacher', 'Teacher', Icons.badge], ['student', 'Student', Icons.school], ['parent', 'Parent / Guardian', Icons.family_restroom]])
                  Card(child: ListTile(leading: Icon(r[2] as IconData), title: Text(r[1] as String), trailing: const Icon(Icons.chevron_right), onTap: () => setState(() => role = r[0] as String))),
              ])
            : switch (role) { 'teacher' => const _TeacherForm(), 'student' => const _StudentForm(), _ => const _ParentForm() },
      );
}

mixin _FormHelpers<T extends StatefulWidget> on State<T> {
  final key = GlobalKey<FormState>(); final v = <String, dynamic>{}; bool busy = false;
  Widget tf(String k, String label, {bool req = true, TextInputType? type, int max = 1}) => Padding(padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(decoration: InputDecoration(labelText: label + (req ? ' *' : ''), border: const OutlineInputBorder()), keyboardType: type, maxLines: max,
          validator: (s) => req && (s == null || s.trim().isEmpty) ? 'Required' : null, onSaved: (s) => v[k] = (s ?? '').trim()));
  Future<void> submit(String path, {Map<String, dynamic> Function()? fix}) async {
    if (!key.currentState!.validate()) return; key.currentState!.save(); if (fix != null) v.addAll(fix());
    setState(() => busy = true);
    try {
      final r = await Api.post(path, v);
      final id = r['teacher_no'] ?? r['student_no'];
      if (!mounted) return;
      if (id != null) await showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
          title: const Text('You are registered!'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Your ID number:'), const SizedBox(height: 8),
          SelectableText('$id', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), if (r['section_matched'] == false) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Your adviser will add you to your section.'))]),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Continue'))]));
      profileReload.value++;                                    // the gate reloads the profile and opens the right home screen
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)))); }
    if (mounted) setState(() => busy = false);
  }
  Widget submitBtn(VoidCallback f) => FilledButton(onPressed: busy ? null : f, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: busy ? const CircularProgressIndicator() : const Text('Register'));
}

class _TeacherForm extends StatefulWidget { const _TeacherForm(); @override State<_TeacherForm> createState() => _TF(); }
class _TF extends State<_TeacherForm> with _FormHelpers {
  List<Map<String, String>> subjects = []; final grades = <int>{};
  @override
  Widget build(BuildContext c) => Form(key: key, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AvatarPicker(onUploaded: (u) => v['photo_url'] = u)), const SizedBox(height: 16),
        tf('first_name', 'First name'), tf('last_name', 'Last name'), tf('birthdate', 'Birthdate (YYYY-MM-DD)', req: false), tf('address', 'Address', max: 2), tf('contact_no', 'Contact number', type: TextInputType.phone),
        Text('Subjects you handle (up to 5) *', style: Theme.of(c).textTheme.titleSmall), const SizedBox(height: 8),
        SubjectsEditor(onChanged: (x) => subjects = x),
        const SizedBox(height: 12), Text('Grade levels you handle (up to 5) *', style: Theme.of(c).textTheme.titleSmall),
        Wrap(spacing: 6, children: [for (var g = 7; g <= 12; g++) FilterChip(label: Text('Grade $g'), selected: grades.contains(g), onSelected: (on) => setState(() { if (on && grades.length < 5) { grades.add(g); } else { grades.remove(g); } }))]),
        const SizedBox(height: 24),
        submitBtn(() {
          final filled = subjects.where((s) => (s['code'] ?? '').isNotEmpty || (s['name'] ?? '').isNotEmpty).toList();
          if (filled.isEmpty || filled.any((s) => (s['code'] ?? '').isEmpty || (s['name'] ?? '').isEmpty)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type a code and a name for each subject'))); return; }
          if (grades.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick at least one grade level'))); return; }
          submit('/api/onboarding/teacher', fix: () => {'subjects': filled, 'grade_levels': grades.toList()});
        }),
      ])));
}

class _StudentForm extends StatefulWidget { const _StudentForm(); @override State<_StudentForm> createState() => _SF(); }
class _SF extends State<_StudentForm> with _FormHelpers {
  int grade = 7; String sex = 'M'; String? sectionId; List<Map<String, dynamic>> sections = [];
  @override void initState() { super.initState(); _loadSections(); }
  Future<void> _loadSections() async {
    try {
      final y = await sb.from('school_years').select('id').eq('is_current', true).single();
      final r = await sb.from('sections').select('id,name').eq('school_year_id', y['id']).eq('grade_level', grade).order('name');
      if (mounted) setState(() { sections = r; sectionId = null; });
    } catch (_) {}
  }
  @override
  Widget build(BuildContext c) => Form(key: key, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AvatarPicker(onUploaded: (u) => v['photo_url'] = u)), const SizedBox(height: 16),
        tf('first_name', 'First name'), tf('middle_name', 'Middle name', req: false), tf('last_name', 'Last name'),
        tf('age', 'Age', type: TextInputType.number), tf('birthdate', 'Birthdate (YYYY-MM-DD)', req: false), tf('address', 'Address', max: 2), tf('lrn', 'LRN (12 digits)', req: false, type: TextInputType.number),
        DropdownButtonFormField<String>(initialValue: sex, decoration: const InputDecoration(labelText: 'Sex', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'M', child: Text('Male')), DropdownMenuItem(value: 'F', child: Text('Female'))], onChanged: (x) => sex = x!),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(initialValue: grade, decoration: const InputDecoration(labelText: 'Grade level *', border: OutlineInputBorder()), items: [for (var g = 7; g <= 12; g++) DropdownMenuItem(value: g, child: Text('Grade $g'))], onChanged: (x) { grade = x!; _loadSections(); }),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(key: ValueKey('sec$grade-${sections.length}'), initialValue: sectionId, decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
          items: [const DropdownMenuItem<String?>(value: null, child: Text('Not sure yet (my adviser will add me)')), for (final s in sections) DropdownMenuItem<String?>(value: s['id'] as String, child: Text('${s['name']}'))], onChanged: (x) => sectionId = x),
        const SizedBox(height: 12),
        tf('guardian_name', 'Parent / guardian name', req: false), tf('guardian_contact', 'Guardian contact', req: false, type: TextInputType.phone),
        const SizedBox(height: 12), submitBtn(() => submit('/api/onboarding/student', fix: () => {'grade_level': grade, 'sex': sex, 'section_id': sectionId, 'age': int.tryParse('${v['age'] ?? ''}')})),
      ])));
}

class _ParentForm extends StatefulWidget { const _ParentForm(); @override State<_ParentForm> createState() => _PF(); }
class _PF extends State<_ParentForm> with _FormHelpers {
  @override
  Widget build(BuildContext c) => Form(key: key, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AvatarPicker(onUploaded: (u) => v['photo_url'] = u)), const SizedBox(height: 16),
        tf('full_name', 'Your full name'), tf('contact_no', 'Contact number', req: false, type: TextInputType.phone),
        const Text('After registering you can request to link your son or daughter using their Student ID.'), const SizedBox(height: 16),
        submitBtn(() => submit('/api/onboarding/parent')),
      ])));
}
