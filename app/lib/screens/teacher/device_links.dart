import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';

/// Attach a device ID that already exists on the fingerprint terminal to a student (the school Student ID stays as is).
Future<void> linkDeviceDialog(BuildContext context, {required String studentId, required String studentName}) async {
  final r = await Future.wait<List<Map<String, dynamic>>>([
    sb.from('device_people').select().order('biometric_id'),
    sb.from('students').select('biometric_id').not('biometric_id', 'is', null),
    sb.from('teachers').select('biometric_id').not('biometric_id', 'is', null),
  ]);
  final used = {...r[1].map((x) => x['biometric_id']), ...r[2].map((x) => x['biometric_id'])};
  final free = r[0].where((d) => !used.contains(d['biometric_id'])).toList();
  if (!context.mounted) return;
  final pick = await showDialog<int>(context: context, builder: (c2) => SimpleDialog(
    title: Text('Device ID for $studentName'),
    children: [
      if (free.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No unassigned device IDs. Plug in the USB so the terminal\'s people are imported first.')),
      for (final d in free) SimpleDialogOption(onPressed: () => Navigator.pop(c2, d['biometric_id'] as int), child: Text('ID ${d['biometric_id']}  ·  ${d['name'] ?? '(no name)'}${d['dept_no'] != null ? '  ·  dept ${d['dept_no']}' : ''}')),
    ],
  ));
  if (pick == null) return;
  try { await Api.post('/api/device/link', {'biometric_id': pick, 'kind': 'student', 'id': studentId}); toast('Linked device ID $pick to $studentName. Earlier punches were attached.'); } catch (e) { toast('$e'); }
}

/// Count of terminal IDs nobody has claimed yet (shown on the USB tab).
class UnlinkedDeviceCount extends StatelessWidget {
  const UnlinkedDeviceCount({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('device_people').stream(primaryKey: ['biometric_id']),
        builder: (c, s) => FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: Future.wait<List<Map<String, dynamic>>>([sb.from('students').select('biometric_id').not('biometric_id', 'is', null), sb.from('teachers').select('biometric_id').not('biometric_id', 'is', null)]),
          builder: (c, m) {
            if (!s.hasData || !m.hasData) return const SizedBox();
            final used = {...m.data![0].map((x) => x['biometric_id']), ...m.data![1].map((x) => x['biometric_id'])};
            final n = s.data!.where((d) => !used.contains(d['biometric_id'])).length;
            return n == 0 ? const SizedBox() : Card(color: Colors.amber.shade50, child: ListTile(leading: const Icon(Icons.fingerprint), title: Text('$n device ID${n == 1 ? '' : 's'} on the terminal not linked yet'), subtitle: const Text('Open a student in the advisory list and tap the fingerprint icon to link their existing device ID.')));
          }),
      );
}
