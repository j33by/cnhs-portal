import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../widgets/subjects_editor.dart';

/// The teacher's own subjects: type a name and a code for each (1 to 5).
class MySubjects extends StatefulWidget {
  const MySubjects({super.key});
  @override
  State<MySubjects> createState() => _MySubjectsState();
}

class _MySubjectsState extends State<MySubjects> {
  List<Map<String, String>>? initial;
  List<Map<String, String>> current = [];
  bool saving = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await sb.from('teacher_subjects').select('code,name').eq('teacher_id', sb.auth.currentUser!.id).order('code');
      setState(() => initial = [for (final x in r) {'code': '${x['code']}', 'name': '${x['name']}'}]);
    } catch (e) { toast('$e'); setState(() => initial = []); }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final r = await Api.put('/api/my-subjects', {'subjects': current});
      toast('${r['saved']} subject(s) saved');
      await _load();
    } catch (e) { toast('$e'); }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext c) => initial == null
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
          Text('My subjects', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Type the subjects you teach: a short code and the subject name. You can have up to 5. Advisers see them when assigning you to a class.'),
          const SizedBox(height: 16),
          SubjectsEditor(key: ValueKey(initial.hashCode), initial: initial!, onChanged: (v) => current = v),
          const SizedBox(height: 8),
          FilledButton(onPressed: saving ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: saving ? const CircularProgressIndicator() : const Text('Save subjects')),
        ]);
}
