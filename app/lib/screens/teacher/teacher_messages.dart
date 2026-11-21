import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/chat_data.dart';
import '../../core/messenger.dart';
import '../../core/offline.dart';
import '../../widgets/ui.dart';
import '../student/chat_view.dart';
import '../student/room_screen.dart';

/// Loads the teacher directory (colleagues + my sections) and keeps it fresh when assignments change.
mixin _Directory<T extends StatefulWidget> on State<T> {
  Map<String, dynamic> dir = {}; bool dirLoaded = false; StreamSubscription<dynamic>? _ds;
  List<Map<String, dynamic>> get people => [for (final p in (dir['people'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
  List<Map<String, dynamic>> get sections => [for (final p in (dir['sections'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
  Future<void> loadDir() async { try { final d = await ChatData.directory(onFresh: (f) { if (mounted) { setState(() => dir = f); } }); if (mounted) { setState(() { dir = d; dirLoaded = true; }); } } catch (_) { if (mounted) { setState(() => dirLoaded = true); } } }
  void watchDir() { loadDir(); _ds = ChatData.assignmentChanges().listen((_) => loadDir(), onError: (_) {}); }
  void unwatchDir() { _ds?.cancel(); }
  List<Map<String, dynamic>> get students => [for (final p in (dir['students'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
  String sectionLabel(Map<String, dynamic> s) => 'Grade ${s['grade_level']} · ${s['name']}';
}

/// Teachers: Messages with a Private tab (colleagues who share a section) and a Group tab (one teachers-only chat per section).
class TeacherMessagesScreen extends StatefulWidget {
  final int initialTab;
  const TeacherMessagesScreen({super.key, this.initialTab = 0});
  @override
  State<TeacherMessagesScreen> createState() => _TeacherMessagesState();
}

class _TeacherMessagesState extends State<TeacherMessagesScreen> with SingleTickerProviderStateMixin, _Directory<TeacherMessagesScreen> {
  late final TabController tc = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  @override
  void initState() { super.initState(); watchDir(); }
  @override
  void dispose() { unwatchDir(); tc.dispose(); super.dispose(); }

  Map<String, dynamic>? _person(String id) { for (final p in [...people, ...students]) { if (p['id'] == id) { return p; } } return null; }

  Future<void> _open(Map<String, dynamic> p) async => once('open-chat', () async {
    try {
      final id = await ChatData.openPrivate('${p['id']}');
      if (!mounted) { return; }
      pushOnce(context, MaterialPageRoute(builder: (_) => ChatScreen(threadId: id, name: fullName(p), photo: p['photo_url'] as String?)));
    } catch (e) { toastError(e); }
  });

  Future<void> _openStaff(Map<String, dynamic> s) async => once('open-chat', () async {
    try {
      final id = await ChatData.openStaff('${s['id']}');
      if (!mounted) { return; }
      pushOnce(context, MaterialPageRoute(builder: (_) => StaffGroupScreen(threadId: id, title: '${sectionLabel(s)} · Teachers')));
    } catch (e) { toastError(e); }
  });

  Future<void> _newMessage() async {
    final pick = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, showDragHandle: true, builder: (c) => _PersonPicker(people: people, students: students, sections: sections));
    if (pick != null) { _open(pick); }
  }

  String _when(DateTime d) {
    final n = DateTime.now();
    if (d.year == n.year && d.month == n.month && d.day == n.day) { return DateFormat.jm().format(d); }
    if (n.difference(d).inDays < 7) { return DateFormat.E().format(d); }
    return DateFormat.MMMd().format(d);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Messages'), bottom: TabBar(controller: tc, tabs: const [Tab(text: 'Private', icon: Icon(Icons.person_outline, size: 20)), Tab(text: 'Group', icon: Icon(Icons.groups_outlined, size: 20))])),
        floatingActionButton: AnimatedBuilder(animation: tc, builder: (c, _) => tc.index == 0 ? FloatingActionButton.extended(onPressed: _newMessage, icon: const Icon(Icons.edit_outlined), label: const Text('New message')) : const SizedBox.shrink()),
        body: TabBarView(controller: tc, children: [_private(c), _groups(c)]),
      );

  Widget _private(BuildContext c) => StreamBuilder<JRows>(stream: ChatData.threads(), builder: (c, ts) => StreamBuilder<JRows>(stream: ChatData.reads(), builder: (c, rs) {
        if (!ts.hasData) { return const Center(child: CircularProgressIndicator()); }
        final read = ChatData.readMap(rs.data ?? const []);
        final list = ts.data!.where((t) => t['kind'] == 'private' && '${t['last_preview'] ?? ''}'.isNotEmpty).toList()..sort((a, b) => '${b['last_message_at']}'.compareTo('${a['last_message_at']}'));
        if (list.isEmpty) {
          return EmptyState(icon: Icons.chat_bubble_outline, title: 'No private messages yet', message: 'Message a teacher or one of your students.', action: FilledButton.icon(onPressed: _newMessage, icon: const Icon(Icons.edit_outlined), label: const Text('New message')));
        }
        return ListView.separated(padding: const EdgeInsets.only(bottom: 96), itemCount: list.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 76), itemBuilder: (c, i) {
          final t = list[i], other = '${t['user_a']}' == myUid ? '${t['user_b']}' : '${t['user_a']}', p = _person(other);
          final name = p == null ? 'Teacher' : fullName(p), unread = ChatData.isUnread(t, read), when = DateTime.tryParse('${t['last_message_at']}')?.toLocal();
          return ListTile(
            onTap: () => pushOnce(c, MaterialPageRoute(builder: (_) => ChatScreen(threadId: '${t['id']}', name: name, photo: p?['photo_url'] as String?))),
            leading: PersonAvatar(url: p?['photo_url'] as String?, name: name, radius: 24),
            title: Text(name, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text('${t['last_sender_id'] == myUid ? 'You: ' : ''}${t['last_preview']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w600 : FontWeight.normal)),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (when != null) Text(_when(when), style: TextStyle(fontSize: 12, color: unread ? Theme.of(c).colorScheme.primary : Theme.of(c).hintColor)),
              if (unread) Container(margin: const EdgeInsets.only(top: 6), width: 10, height: 10, decoration: BoxDecoration(color: Theme.of(c).colorScheme.primary, shape: BoxShape.circle)),
            ]),
          );
        });
      }));

  Widget _groups(BuildContext c) => StreamBuilder<JRows>(stream: ChatData.threads(), builder: (c, ts) => StreamBuilder<JRows>(stream: ChatData.reads(), builder: (c, rs) {
        if (!dirLoaded) { return const Center(child: CircularProgressIndicator()); }
        final secs = sections;
        if (secs.isEmpty) { return const EmptyState(icon: Icons.groups_outlined, title: 'No sections yet', message: 'You get a group chat for every section you advise or teach.'); }
        final read = ChatData.readMap(rs.data ?? const []);
        Map<String, dynamic>? thread(String sid) { for (final t in ts.data ?? const <Map<String, dynamic>>[]) { if (t['kind'] == 'staff' && '${t['section_id']}' == sid) { return t; } } return null; }
        return RefreshIndicator(onRefresh: loadDir, child: ListView.separated(padding: const EdgeInsets.only(bottom: 24), itemCount: secs.length + 1, separatorBuilder: (_, __) => const Divider(height: 1, indent: 76), itemBuilder: (c, i) {
          if (i == 0) {
            return Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 8), child: Row(children: [Icon(Icons.lock_outline, size: 14, color: Theme.of(c).hintColor), const SizedBox(width: 6), Expanded(child: Text('Teachers only. Students and parents cannot see these chats.', style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor)))]));
          }
          final s = secs[i - 1], t = thread('${s['id']}'), unread = t != null && ChatData.isUnread(t, read);
          final prev = t == null ? '' : '${t['last_preview'] ?? ''}';
          return ListTile(
            onTap: () => _openStaff(s),
            leading: CircleAvatar(radius: 24, backgroundColor: Theme.of(c).colorScheme.primaryContainer, child: Icon(Icons.groups, color: Theme.of(c).colorScheme.primary)),
            title: Text('${sectionLabel(s)} · Teachers', style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text(prev.isEmpty ? '${s['members']} teachers${s['adviser'] == true ? ' · you are the adviser' : ''}' : '${t!['last_sender_id'] == myUid ? 'You: ' : ''}$prev', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w600 : FontWeight.normal)),
            trailing: unread ? Container(width: 10, height: 10, decoration: BoxDecoration(color: Theme.of(c).colorScheme.primary, shape: BoxShape.circle)) : null,
          );
        }));
      }));
}

/// The teachers-only chat of one section.
class StaffGroupScreen extends StatelessWidget {
  final String threadId, title;
  const StaffGroupScreen({super.key, required this.threadId, required this.title});
  @override
  Widget build(BuildContext c) => Scaffold(appBar: AppBar(title: Text(title)), body: ChatView(threadId: threadId, group: true));
}

/// Teachers: pick one of my sections to open its Room (people + voice messages).
class TeacherRoomsScreen extends StatefulWidget {
  const TeacherRoomsScreen({super.key});
  @override
  State<TeacherRoomsScreen> createState() => _TeacherRoomsState();
}

class _TeacherRoomsState extends State<TeacherRoomsScreen> with _Directory<TeacherRoomsScreen> {
  @override
  void initState() { super.initState(); watchDir(); }
  @override
  void dispose() { unwatchDir(); super.dispose(); }
  @override
  Widget build(BuildContext c) {
    final secs = sections, cs = Theme.of(c).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Rooms')),
      body: !dirLoaded ? const Center(child: CircularProgressIndicator())
          : secs.isEmpty ? const EmptyState(icon: Icons.meeting_room_outlined, title: 'No rooms yet', message: 'You get a room for every section you advise or teach.')
          : RefreshIndicator(onRefresh: loadDir, child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final s in secs) Padding(padding: const EdgeInsets.only(bottom: 10), child: SoftCard(child: InkWell(
                borderRadius: BorderRadius.circular(16), onTap: () => pushOnce(c, MaterialPageRoute(builder: (_) => RoomScreen(sectionId: '${s['id']}'))),
                child: Row(children: [
                  CircleAvatar(radius: 22, backgroundColor: cs.primaryContainer, child: Icon(Icons.meeting_room_outlined, color: cs.primary)), const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sectionLabel(s), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(s['adviser'] == true ? 'You are the adviser' : 'Subject teacher', style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor)),
                  ])),
                  const Icon(Icons.chevron_right),
                ])))),
            ])),
    );
  }
}

/// "New message" sheet: search, then teachers and students (students grouped by section).
class _PersonPicker extends StatefulWidget {
  final List<Map<String, dynamic>> people, students, sections;
  const _PersonPicker({required this.people, required this.students, required this.sections});
  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  String q = '';
  bool _hit(Map<String, dynamic> p) => q.isEmpty || fullName(p).toLowerCase().contains(q);
  @override
  Widget build(BuildContext c) {
    final teachers = widget.people.where(_hit).toList();
    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 4), child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: Theme.of(c).hintColor)));
    final rows = <Widget>[];
    if (teachers.isNotEmpty) { rows.add(head('TEACHERS')); for (final m in teachers) { rows.add(ListTile(leading: PersonAvatar(url: m['photo_url'] as String?, name: fullName(m)), title: Text(fullName(m)), onTap: () => Navigator.pop(c, m))); } }
    for (final s in widget.sections) {
      final st = widget.students.where((x) => x['section_id'] == s['id'] && _hit(x)).toList();
      if (st.isEmpty) { continue; }
      rows.add(head('GRADE ${s['grade_level']} · ${'${s['name']}'.toUpperCase()}  (${st.length})'));
      for (final m in st) { rows.add(ListTile(leading: PersonAvatar(url: m['photo_url'] as String?, name: fullName(m)), title: Text(fullName(m)), onTap: () => Navigator.pop(c, m))); }
    }
    return DraggableScrollableSheet(expand: false, initialChildSize: .8, maxChildSize: .95, builder: (c, sc) => Column(children: [
      const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('New message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: TextField(onChanged: (v) => setState(() => q = v.trim().toLowerCase()), decoration: InputDecoration(hintText: 'Search teachers or students', prefixIcon: const Icon(Icons.search, size: 20), isDense: true, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
      Expanded(child: rows.isEmpty ? Center(child: Text(q.isEmpty ? 'Nobody to message yet.' : 'No match.', style: TextStyle(color: Theme.of(c).hintColor))) : ListView(controller: sc, children: rows)),
    ]));
  }
}
