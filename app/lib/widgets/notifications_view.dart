import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../screens/student/chat_view.dart';
import '../screens/student/messages_screen.dart';
import 'status.dart';
import 'ui.dart';
import '../core/offline.dart';

({IconData icon, Color color}) _look(Map<String, dynamic> n) {
  final data = n['data'] is Map ? n['data'] as Map : const {};
  switch (n['kind']) {
    case 'attendance':
      final st = data['status'] as String?;
      return (icon: st == null ? Icons.how_to_reg : stIcon(st), color: st == null ? Colors.green : stColor(st));
    case 'no_class': return (icon: Icons.event_busy, color: stColor('N'));
    case 'grades': return (icon: Icons.school, color: Colors.indigo);
    case 'bind': return (icon: Icons.link, color: Colors.teal);
    case 'feed': return (icon: Icons.campaign, color: Colors.teal);
    case 'class': return (icon: Icons.alarm, color: Colors.orange);
    case 'chat': return (icon: n['data'] is Map && (n['data'] as Map)['thread_kind'] == 'group' ? Icons.forum : Icons.chat_bubble, color: Colors.deepPurple);
    case 'section': return (icon: Icons.groups, color: Colors.blue);
    default: return (icon: Icons.notifications, color: Colors.blueGrey);
  }
}

/// Realtime notification inbox, grouped by day. Unread ones are highlighted; opening this screen marks them read after a few seconds.
class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});
  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  late final Stream<List<Map<String, dynamic>>> _stream = liveStream('notifications|user_id=${myUid}|o', () => sb.from('notifications').stream(primaryKey: ['id'])
      .eq('user_id', myUid).order('created_at', ascending: false));
  Timer? _t;
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  void _scheduleRead() {
    if (_t != null) return;
    _t = Timer(const Duration(seconds: 3), () { _t = null; Api.post('/api/notifications/read').catchError((_) {}); });
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now(), today = DateTime(now.year, now.month, now.day), day = DateTime(d.year, d.month, d.day), diff = today.difference(day).inDays;
    return diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : DateFormat('EEEE, MMM d').format(d);
  }

  Widget _card(BuildContext c, Map<String, dynamic> n) {
    final look = _look(n), unread = n['read'] != true, cs = Theme.of(c).colorScheme, when = DateTime.parse(n['created_at']).toLocal();
    final card = Padding(padding: const EdgeInsets.only(bottom: 8), child: SoftCard(
      padding: EdgeInsets.zero, color: unread ? cs.primaryContainer.withValues(alpha: .35) : null, border: unread ? cs.primary.withValues(alpha: .5) : null,
      child: Padding(padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 21, backgroundColor: look.color.withValues(alpha: .16), child: Icon(look.icon, color: look.color, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${n['title']}', style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w600, fontSize: 14.5))),
            if (unread) Container(width: 9, height: 9, margin: const EdgeInsets.only(left: 6), decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
          ]),
          const SizedBox(height: 3),
          Text('${n['body']}', style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: 6),
          Text(DateFormat('h:mm a').format(when), style: TextStyle(fontSize: 11.5, color: Theme.of(c).hintColor)),
        ])),
      ])),
    ));
    return n['kind'] == 'chat' ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => openChatAlert(c, n), child: card) : card;
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const EmptyState(icon: Icons.notifications_none, title: 'No notifications yet', message: 'Updates will show up here.');
          final unread = s.data!.where((n) => n['read'] != true).length;
          if (unread > 0 && TickerMode.of(c)) { _scheduleRead(); }              // TickerMode is off while this tab is hidden
          final items = <Widget>[];
          String? last;
          for (final n in s.data!) {
            final label = _dayLabel(DateTime.parse(n['created_at']).toLocal());
            if (label != last) { items.add(Padding(padding: const EdgeInsets.fromLTRB(4, 12, 0, 8), child: Text(label, style: Theme.of(c).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)))); last = label; }
            items.add(_card(c, n));
          }
          return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 28), children: items)));
        },
      );
}

/// Open the chat an alert is about (private chat, or the Group tab).
void openChatAlert(BuildContext c, Map<String, dynamic> n) {
  final d = n['data'] is Map ? n['data'] as Map : const {};
  if (d['thread_kind'] == 'group') { Navigator.push(c, MaterialPageRoute(builder: (_) => const MessagesScreen(initialTab: 1))); }
  else if (d['thread_id'] != null) { Navigator.push(c, MaterialPageRoute(builder: (_) => ChatScreen(threadId: '${d['thread_id']}', name: '${d['sender_name'] ?? 'Chat'}', photo: d['sender_photo'] as String?))); }
}
