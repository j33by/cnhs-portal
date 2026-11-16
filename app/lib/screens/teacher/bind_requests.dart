import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';

/// Parent link requests waiting for approval (live). Names come with each request, so nothing is looked up per row.
class BindRequests extends StatelessWidget {
  const BindRequests({super.key});

  Future<void> _review(String id, bool approve) async {
    try { await Api.post('/api/bind/$id/review', {'approve': approve}); toast(approve ? 'Approved. The parent can now see this student.' : 'Request declined'); } catch (e) { toastError(e); }
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('parent_links').stream(primaryKey: ['id']).eq('status', 'pending'),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No pending requests. When a parent asks to link a child, it appears here.', textAlign: TextAlign.center)));
          final list = [...s.data!]..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
          return ListView(padding: const EdgeInsets.all(8), children: [for (final l in list) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.family_restroom), const SizedBox(width: 8), Expanded(child: Text('${l['parent_name'] ?? 'A parent'} wants to link to ${l['student_name'] ?? 'a student'}', style: const TextStyle(fontWeight: FontWeight.w600)))]),
            const SizedBox(height: 4),
            Text('${l['parent_email'] ?? ''}  ·  Student ID ${l['student_no'] ?? ''}${l['created_at'] != null ? '  ·  ${DateFormat('MMM d, h:mm a').format(DateTime.parse(l['created_at']).toLocal())}' : ''}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => _review(l['id'], false), child: const Text('Decline')), const SizedBox(width: 8),
              FilledButton(onPressed: () => _review(l['id'], true), child: const Text('Approve')),
            ]),
          ])))]);
        });
}
