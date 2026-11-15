import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../core/messenger.dart';
import '../widgets/avatar_picker.dart';

class _Field {
  final String key, label; final bool req, multiline; final TextInputType? type;
  const _Field(this.key, this.label, {this.req = false, this.multiline = false, this.type});
}

/// Profile tab used by students, teachers and parents: shows the ID, and lets the person view and edit their own details.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? prof, row;
  bool editing = false, saving = false;
  final ctl = <String, TextEditingController>{};
  String sex = 'M';
  Set<int> grades = {};
  final formKey = GlobalKey<FormState>();

  String get role => (prof?['role'] ?? '') as String;

  List<_Field> get fields {
    switch (role) {
      case 'student':
        return const [
          _Field('first_name', 'First name', req: true), _Field('middle_name', 'Middle name'), _Field('last_name', 'Last name', req: true),
          _Field('age', 'Age', req: true, type: TextInputType.number), _Field('birthdate', 'Birthdate (YYYY-MM-DD)'),
          _Field('address', 'Address', req: true, multiline: true), _Field('lrn', 'LRN (12 digits)', type: TextInputType.number),
          _Field('guardian_name', 'Parent / guardian name'), _Field('guardian_contact', 'Guardian contact', type: TextInputType.phone),
        ];
      case 'teacher':
        return const [
          _Field('first_name', 'First name', req: true), _Field('last_name', 'Last name', req: true), _Field('birthdate', 'Birthdate (YYYY-MM-DD)'),
          _Field('address', 'Address', multiline: true), _Field('contact_no', 'Contact number', type: TextInputType.phone),
        ];
      default:
        return const [_Field('full_name', 'Full name', req: true), _Field('contact_no', 'Contact number', type: TextInputType.phone)];
    }
  }

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { for (final c in ctl.values) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    try {
      final uid = sb.auth.currentUser!.id;
      final p = await sb.from('profiles').select().eq('id', uid).single();
      Map<String, dynamic>? r;
      if (p['role'] == 'student') { r = await sb.from('students').select('*, sections(name,grade_level)').eq('id', uid).single(); }
      else if (p['role'] == 'teacher') { r = await sb.from('teachers').select().eq('id', uid).single(); }
      prof = p; row = r;
      _fill();
    } catch (e) { toast('$e'); }
    if (mounted) setState(() {});
  }

  void _fill() {
    for (final c in ctl.values) { c.dispose(); }
    ctl.clear();
    final src = role == 'parent' ? prof! : row!;
    for (final f in fields) { ctl[f.key] = TextEditingController(text: '${src[f.key] ?? ''}'); }
    sex = (row?['sex'] ?? 'M') as String;
    grades = {for (final g in (row?['grade_levels'] as List? ?? [])) g as int};
  }

  Future<void> _photo(String url) async {
    try { await Api.patch('/api/me', {'photo_url': url}); prof!['photo_url'] = url; toast('Photo updated'); } catch (e) { toast('$e'); }
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    final body = <String, dynamic>{for (final f in fields) f.key: ctl[f.key]!.text.trim()};
    if (role == 'student') { body['sex'] = sex; body['age'] = int.tryParse('${body['age']}'); }
    if (role == 'teacher') {
      if (grades.isEmpty) { toast('Pick at least one grade level'); return; }
      body['grade_levels'] = (grades.toList()..sort());
    }
    setState(() => saving = true);
    try { await Api.patch('/api/me', body); toast('Profile saved'); editing = false; await _load(); } catch (e) { toast('$e'); }
    if (mounted) setState(() => saving = false);
  }

  Widget _info(IconData icon, String label, String value) => ListTile(dense: true, leading: Icon(icon), title: Text(label), subtitle: Text(value.isEmpty ? '—' : value));

  @override
  Widget build(BuildContext c) {
    if (prof == null) return const Center(child: CircularProgressIndicator());
    final id = role == 'student' ? row!['student_no'] : role == 'teacher' ? row!['teacher_no'] : null;
    final sec = row?['sections'];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(key: formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AvatarPicker(url: prof!['photo_url'] as String?, onUploaded: _photo)),
        const SizedBox(height: 8),
        Center(child: Text('${prof!['full_name']}', style: Theme.of(c).textTheme.titleLarge)),
        Center(child: Text(role == 'student' ? 'Student' : role == 'teacher' ? 'Teacher' : 'Parent / Guardian')),
        const SizedBox(height: 12),
        if (id != null) Card(child: ListTile(
          leading: const Icon(Icons.badge, size: 32),
          title: Text(role == 'student' ? 'Student ID' : 'Teacher ID'),
          subtitle: SelectableText('$id', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1)),
          trailing: IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy', onPressed: () { Clipboard.setData(ClipboardData(text: '$id')); toast('ID copied'); }),
        )),
        Card(child: Column(children: [
          _info(Icons.email, 'Google account', '${prof!['email'] ?? ''}'),
          if (role == 'student') _info(Icons.class_, 'Grade & section', sec == null ? 'Grade ${row!['grade_level']} · waiting for your adviser to add you' : 'Grade ${sec['grade_level']} · ${sec['name']}'),
          if (role == 'student') _info(Icons.fingerprint, 'Biometric device ID', '${row!['biometric_id'] ?? 'not assigned'}'),
        ])),
        const SizedBox(height: 12),
        Row(children: [
          Text('My details', style: Theme.of(c).textTheme.titleMedium), const Spacer(),
          if (!editing) OutlinedButton.icon(onPressed: () => setState(() => editing = true), icon: const Icon(Icons.edit), label: const Text('Edit'))
          else ...[
            TextButton(onPressed: saving ? null : () { setState(() { editing = false; _fill(); }); }, child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: saving ? null : _save, child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
          ],
        ]),
        const SizedBox(height: 12),
        for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
          controller: ctl[f.key], enabled: editing, keyboardType: f.type, maxLines: f.multiline ? 2 : 1,
          decoration: InputDecoration(labelText: f.label + (f.req ? ' *' : ''), border: const OutlineInputBorder()),
          validator: (v) => f.req && (v == null || v.trim().isEmpty) ? 'Required' : null,
        )),
        if (role == 'student') Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Sex'),
          for (final s in const [['M', 'Male'], ['F', 'Female']]) ChoiceChip(label: Text(s[1]), selected: sex == s[0], onSelected: editing ? (_) => setState(() => sex = s[0]) : null),
        ]),
        if (role == 'teacher') ...[
          Text('Grade levels you handle (up to 5)', style: Theme.of(c).textTheme.titleSmall),
          Wrap(spacing: 6, children: [for (var g = 7; g <= 12; g++) FilterChip(label: Text('Grade $g'), selected: grades.contains(g),
            onSelected: editing ? (on) => setState(() { if (on && grades.length < 5) { grades.add(g); } else { grades.remove(g); } }) : null)]),
          const SizedBox(height: 8),
          const Text('Your subjects are edited in the Subjects tab.', style: TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(onPressed: () => sb.auth.signOut(), icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ])),
    );
  }
}
