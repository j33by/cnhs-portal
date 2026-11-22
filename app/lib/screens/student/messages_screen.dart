import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/chat_data.dart';
import '../../core/messenger.dart';
import '../../core/offline.dart';
import '../../widgets/ui.dart';
import 'chat_view.dart';

/// Messages: Private (one-to-one with classmates) and Group (the whole section). Students of the section only.
class MessagesScreen extends StatefulWidget {
  final int initialTab;                    // 0 = Private, 1 = Group
  const MessagesScreen({super.key, this.initialTab = 0});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with SingleTickerProviderStateMixin {
  late final TabController tc = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  Map<String, dynamic> roster = {};
  String? groupId; bool groupFailed = false;

  StreamSubscription<dynamic>? _live;
  @override
  void initState() { super.initState(); _loadRoster(); _openGroup(); _live = ChatData.assignmentChanges().listen((_) => _loadRoster(), onError: (_) {}); }
  @override
  void dispose() { _live?.cancel(); tc.dispose(); super.dispose(); }

  Future<void> _loadRoster() async { try { final r = await ChatData.roster(); if (mounted) { setState(() => roster = r); } } catch (_) {} }
  Future<void> _openGroup() async {
    try { final id = await ChatData.openGroup(); if (mounted) { setState(() { groupId = id; groupFailed = false; }); } }
    catch (_) { if (mounted) { setState(() => groupFailed = true); } }
  }

  List<Map<String, dynamic>> get _mates => [for (final m in (roster['classmates'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
  List<Map<String, dynamic>> get _teachers => [
        if (roster['adviser'] is Map) Map<String, dynamic>.from(roster['adviser'] as Map),
        for (final t in (roster['subject_teachers'] as List? ?? const [])) Map<String, dynamic>.from(t as Map),
      ];
  Map<String, dynamic>? _person(String id) { for (final m in [..._mates, ..._teachers]) { if (m['id'] == id) { return m; } } return null; }

  Future<void> _open(Map<String, dynamic> p) async => once('open-chat', () async {
    try {
      final id = await ChatData.openPrivate('${p['id']}');
      if (!mounted) { return; }
      pushOnce(context, MaterialPageRoute(builder: (_) => ChatScreen(threadId: id, name: fullName(p), photo: p['photo_url'] as String?)));
    } catch (e) { toastError(e); }
  });

  Future<void> _newMessage() async {
    final others = _mates.where((m) => m['id'] != myUid).toList(), teachers = _teachers;
    final pick = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, showDragHandle: true, builder: (c) => DraggableScrollableSheet(
      expand: false, initialChildSize: .7, maxChildSize: .92, builder: (c, sc) => Column(children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('New message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))),
        Expanded(child: others.isEmpty && teachers.isEmpty ? const Center(child: Text('Nobody to message yet.')) : ListView(controller: sc, children: [
          if (teachers.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 4), child: Text('TEACHERS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6))),
          for (final m in teachers) ListTile(leading: PersonAvatar(url: m['photo_url'] as String?, name: fullName(m)), title: Text(fullName(m)), subtitle: Text(m['id'] == roster['adviser']?['id'] ? 'Adviser' : (m['subjects'] as List? ?? const []).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => Navigator.pop(c, m)),
          if (others.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 4), child: Text('CLASSMATES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6))),
          for (final m in others) ListTile(leading: PersonAvatar(url: m['photo_url'] as String?, name: fullName(m)), title: Text(fullName(m)), onTap: () => Navigator.pop(c, m)),
        ])),
      ])));
    if (pick != null) { _open(pick); }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Messages'), bottom: TabBar(controller: tc, tabs: const [Tab(text: 'Private', icon: Icon(Icons.person_outline, size: 20)), Tab(text: 'Group', icon: Icon(Icons.groups_outlined, size: 20))])),
        floatingActionButton: AnimatedBuilder(animation: tc, builder: (c, _) => tc.index == 0 ? FloatingActionButton.extended(onPressed: _newMessage, icon: const Icon(Icons.edit_outlined), label: const Text('New message')) : const SizedBox.shrink()),
        body: TabBarView(controller: tc, children: [_private(c), _group(c)]),
      );

  Widget _private(BuildContext c) => StreamBuilder<JRows>(stream: ChatData.threads(), builder: (c, ts) => StreamBuilder<JRows>(stream: ChatData.reads(), builder: (c, rs) {
        if (!ts.hasData) { return const Center(child: CircularProgressIndicator()); }
        final read = ChatData.readMap(rs.data ?? const []);
        final list = ts.data!.where((t) => t['kind'] == 'private' && '${t['last_preview'] ?? ''}'.isNotEmpty).toList()
          ..sort((a, b) => '${b['last_message_at']}'.compareTo('${a['last_message_at']}'));
        if (list.isEmpty) {
          return EmptyState(icon: Icons.chat_bubble_outline, title: 'No private messages yet', message: 'Start a conversation with a classmate or a teacher.', action: FilledButton.icon(onPressed: _newMessage, icon: const Icon(Icons.edit_outlined), label: const Text('New message')));
        }
        return ListView.separated(padding: const EdgeInsets.only(bottom: 96), itemCount: list.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 76), itemBuilder: (c, i) {
          final t = list[i], other = '${t['user_a']}' == myUid ? '${t['user_b']}' : '${t['user_a']}', p = _person(other);
          final name = p == null ? 'Classmate' : fullName(p), unread = ChatData.isUnread(t, read);
          final when = DateTime.tryParse('${t['last_message_at']}')?.toLocal();
          final mineLast = t['last_sender_id'] == myUid;
          return ListTile(
            onTap: () => pushOnce(c, MaterialPageRoute(builder: (_) => ChatScreen(threadId: '${t['id']}', name: name, photo: p?['photo_url'] as String?))),
            leading: PersonAvatar(url: p?['photo_url'] as String?, name: name, radius: 24),
            title: Text(name, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text('${mineLast ? 'You: ' : ''}${t['last_preview']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w600 : FontWeight.normal)),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (when != null) Text(_when(when), style: TextStyle(fontSize: 12, color: unread ? Theme.of(c).colorScheme.primary : Theme.of(c).hintColor)),
              if (unread) Container(margin: const EdgeInsets.only(top: 6), width: 10, height: 10, decoration: BoxDecoration(color: Theme.of(c).colorScheme.primary, shape: BoxShape.circle)),
            ]),
          );
        });
      }));

  String _when(DateTime d) {
    final n = DateTime.now();
    if (d.year == n.year && d.month == n.month && d.day == n.day) { return DateFormat.jm().format(d); }
    if (n.difference(d).inDays < 7) { return DateFormat.E().format(d); }
    return DateFormat.MMMd().format(d);
  }

  Widget _group(BuildContext c) {
    final sec = roster['section'] as Map?;
    if (groupId == null) {
      return groupFailed ? EmptyState(icon: Icons.forum_outlined, title: 'Group chat unavailable', message: 'You need to be in a section, and online, to open the group chat.', action: FilledButton(onPressed: _openGroup, child: const Text('Retry'))) : const Center(child: CircularProgressIndicator());
    }
    return Column(children: [
      Container(width: double.infinity, color: Theme.of(c).colorScheme.surfaceContainerLow, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
        Icon(Icons.lock_outline, size: 14, color: Theme.of(c).hintColor), const SizedBox(width: 6),
        Expanded(child: Text('${sec != null ? 'Grade ${sec['grade_level']} · ${sec['name']}' : 'Your section'} · ${_mates.length} members · students only', style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor))),
      ])),
      Expanded(child: ChatView(threadId: groupId!, group: true)),
    ]);
  }
}
