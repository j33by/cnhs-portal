import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';

/// Biometric device IDs belong to STUDENTS only. Attach a device ID that already exists on the terminal to a student
/// (the school Student ID stays as it is).
Future<void> linkDeviceDialog(BuildContext context, {required String studentId, required String studentName}) async {
  final r = await Future.wait<List<Map<String, dynamic>>>([
    sb.from('device_people').select().eq('ignored', false).order('biometric_id'),
    sb.from('students').select('biometric_id').not('biometric_id', 'is', null),
  ]);
  final used = {...r[1].map((x) => x['biometric_id'])};
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
  try { await Api.post('/api/device/link', {'biometric_id': pick, 'id': studentId}); toast('Linked device ID $pick to $studentName. Earlier punches were attached.'); } catch (e) { toast('$e'); }
}

/// Terminal IDs that no student owns yet (shown on the USB tab). Teachers and staff on the terminal can be ignored.
class UnlinkedDeviceCount extends StatelessWidget {
  const UnlinkedDeviceCount({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('device_people').stream(primaryKey: ['biometric_id']),
        builder: (c, s) => FutureBuilder<List<Map<String, dynamic>>>(
          future: sb.from('students').select('biometric_id').not('biometric_id', 'is', null),
          builder: (c, m) {
            if (!s.hasData || !m.hasData) return const SizedBox();
            final used = {...m.data!.map((x) => x['biometric_id'])};
            final open = s.data!.where((d) => d['ignored'] != true && !used.contains(d['biometric_id'])).toList()..sort((a, b) => (a['biometric_id'] as int).compareTo(b['biometric_id'] as int));
            if (open.isEmpty) return const SizedBox();
            return Card(color: Colors.amber.shade50, child: ExpansionTile(
              leading: const Icon(Icons.fingerprint),
              title: Text('${open.length} device ID${open.length == 1 ? '' : 's'} on the terminal not linked to a student'),
              subtitle: const Text('Link a student with the fingerprint icon in the advisory list. Ignore IDs of teachers or staff.', style: TextStyle(fontSize: 12)),
              children: [for (final d in open) ListTile(dense: true, title: Text('ID ${d['biometric_id']}  ·  ${d['name'] ?? '(no name)'}'),
                  trailing: TextButton(onPressed: () async { try { await Api.post('/api/device/ignore', {'biometric_id': d['biometric_id'], 'ignored': true}); } catch (e) { toast('$e'); } }, child: const Text('Ignore')))],
            ));
          }),
      );
}
