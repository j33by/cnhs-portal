import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../widgets/schedule_blocks.dart';
import '../../widgets/shared.dart';

/// This subject's schedule in this section. The class teacher can add and remove times.
class ClassScheduleTab extends StatelessWidget {
  final String sectionId, subjectId;
  const ClassScheduleTab({super.key, required this.sectionId, required this.subjectId});

  Future<void> _add(BuildContext c) async {
    var blocks = <Map<String, dynamic>>[]; final room = TextEditingController();
    await showDialog(context: c, builder: (c2) => AlertDialog(
      title: const Text('Add schedule'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ScheduleBlocks(onChanged: (b) => blocks = b),
        TextField(controller: room, decoration: const InputDecoration(labelText: 'Room (optional)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          Navigator.pop(c2);
          try { final r = await Api.post('/api/classes/$sectionId/$subjectId/schedules', {'schedules': blocks, 'room': room.text.trim()}); toast('${r['added']} time slot(s) added'); } catch (e) { toastError(e); }
        }, child: const Text('Save')),
      ],
    ));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: () => _add(c), child: const Icon(Icons.add)),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: sb.from('schedules').stream(primaryKey: ['id']).eq('section_id', sectionId),
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final rows = s.data!.where((x) => x['subject_id'] == subjectId).toList()
              ..sort((a, b) { final d = (a['day_of_week'] as int).compareTo(b['day_of_week'] as int); return d != 0 ? d : '${a['start_time']}'.compareTo('${b['start_time']}'); });
            if (rows.isEmpty) return const Center(child: Text('No schedule yet. Tap + to add one.'));
            return ListView(children: [for (final x in rows) ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(kDays[x['day_of_week'] as int]),
              subtitle: Text('${t12(x['start_time'])} – ${t12(x['end_time'])}${x['room'] != null ? '  ·  ${x['room']}' : ''}'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async {
                try { await Api.delete('/api/schedules/${x['id']}'); } catch (e) { toastError(e); }
              }),
            )]);
          }),
      );
}
