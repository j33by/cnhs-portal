import 'package:flutter/material.dart';
import '../../core/api.dart';

class BindRequests extends StatelessWidget {
  const BindRequests({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: sb.from('parent_links').stream(primaryKey: ['id']).eq('status', 'pending'),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const Center(child: Text('No pending requests'));
          return ListView(children: [for (final l in s.data!) FutureBuilder<List<Map<String, dynamic>>>(
              future: Future.wait([sb.from('profiles').select('full_name,email').eq('id', l['parent_id']), sb.from('students').select('first_name,last_name,student_no').eq('id', l['student_id'])]),
              builder: (c, m) { final p = m.data?[0].first, st = m.data?[1].first; if (p == null) return const SizedBox();
                return Card(child: ListTile(title: Text('${p['full_name']} → ${st['first_name']} ${st['last_name']}'), subtitle: Text('${p['email']}  ·  ID ${st['student_no']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => Api.post('/api/bind/${l['id']}/review', {'approve': false})),
                    IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => Api.post('/api/bind/${l['id']}/review', {'approve': true}))]))); })]);
        });
}
