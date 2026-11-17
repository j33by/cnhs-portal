import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../core/messenger.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/ui.dart';

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
      if (p['role'] == 'student') {
        r = await sb.from('students').select().eq('id', uid).single();
        if (r['section_id'] != null) { r['sections'] = await sb.from('sections').select('name,grade_level').eq('id', r['section_id']).maybeSingle(); }
      }
      else if (p['role'] == 'teacher') { r = await sb.from('teachers').select().eq('id', uid).single(); }
      prof = p; row = r;
      _fill();
    } catch (e) { toastError(e); }
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
    try { await Api.patch('/api/me', {'photo_url': url}); prof!['photo_url'] = url; toast('Photo updated'); } catch (e) { toastError(e); }
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
    try { await Api.patch('/api/me', body); toast('Profile saved'); editing = false; await _load(); } catch (e) { toastError(e); }
    if (mounted) setState(() => saving = false);
  }

  Widget _info(IconData icon, String label, String value) => ListTile(dense: true, leading: Icon(icon), title: Text(label, style: const TextStyle(fontSize: 12.5)), subtitle: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)));

  Widget _hero(BuildContext c, String? id) {
    final cs = Theme.of(c).colorScheme, name = '${prof!['full_name']}';
    return Container(
      width: double.infinity, padding: const EdgeInsets.fromLTRB(16, 22, 16, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary, Color.lerp(cs.primary, Colors.black, .35)!]),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: AvatarPicker(url: prof!['photo_url'] as String?, onUploaded: _photo)),
        const SizedBox(height: 12),
        Text(name, textAlign: TextAlign.center, style: TextStyle(color: cs.onPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Pill(role == 'student' ? 'Student' : role == 'teacher' ? 'Teacher' : 'Parent / Guardian', Colors.white, icon: Icons.verified_user),
        if (id != null) ...[
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () { Clipboard.setData(ClipboardData(text: '$id')); toast('ID copied'); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.badge, size: 16, color: cs.onPrimary), const SizedBox(width: 6),
                Text('${role == 'student' ? 'Student' : 'Teacher'} ID  $id', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600, letterSpacing: .5)),
                const SizedBox(width: 6), Icon(Icons.copy, size: 14, color: cs.onPrimary.withValues(alpha: .8)),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text('Tap the photo to change it', style: TextStyle(color: cs.onPrimary.withValues(alpha: .75), fontSize: 11.5)),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    if (prof == null) return const Center(child: CircularProgressIndicator());
    final id = role == 'student' ? row!['student_no'] : role == 'teacher' ? row!['teacher_no'] : null;
    final sec = row?['sections'];
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      _hero(c, id as String?),
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Form(key: formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SoftCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: [
            _info(Icons.email_outlined, 'Google account', '${prof!['email'] ?? ''}'),
            if (role == 'student') _info(Icons.class_outlined, 'Grade & section', sec == null ? 'Grade ${row!['grade_level']} · waiting for your adviser to add you' : 'Grade ${sec['grade_level']} · ${sec['name']}'),
            if (role == 'student') _info(Icons.fingerprint, 'Biometric device ID', '${row!['biometric_id'] ?? 'not assigned'}'),
          ])),
          const SizedBox(height: 18),
          SectionTitle('My details', icon: Icons.person_outline, trailing: !editing
              ? OutlinedButton.icon(onPressed: () => setState(() => editing = true), icon: const Icon(Icons.edit, size: 18), label: const Text('Edit'))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: saving ? null : () { setState(() { editing = false; _fill(); }); }, child: const Text('Cancel')),
                  const SizedBox(width: 4),
                  FilledButton(onPressed: saving ? null : _save, child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
                ])),
          SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [for (var g = 7; g <= 12; g++) FilterChip(label: Text('Grade $g'), selected: grades.contains(g),
                onSelected: editing ? (on) => setState(() { if (on && grades.length < 5) { grades.add(g); } else { grades.remove(g); } }) : null)]),
              const SizedBox(height: 8),
              const Text('Your subjects are edited in the Subjects tab.', style: TextStyle(fontSize: 12)),
            ],
          ])),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: Colors.red.shade700, side: BorderSide(color: Colors.red.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => sb.auth.signOut(), icon: const Icon(Icons.logout), label: const Text('Sign out')),
        ]))))),
    ]);
  }
}
