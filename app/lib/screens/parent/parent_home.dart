import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../core/streams.dart';
import '../../widgets/family_home.dart';
import '../../widgets/family_shell.dart';
import '../../widgets/feed_view.dart';
import '../../widgets/shared.dart';
import '../../widgets/ui.dart';
import '../profile_screen.dart';
import '../../core/offline.dart';

/// Parent app: Home, Attendance, Grades, Alerts, Profile. With more than one child a switcher sits above the child's tabs.
class ParentHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const ParentHome({super.key, required this.profile});
  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  List<Map<String, dynamic>> links = [];
  final kids = <String, Map<String, dynamic>>{};
  final sectionLabels = <String, String>{};
  bool loaded = false;
  String? selectedKid;
  StreamSubscription<dynamic>? _links, _kids;
  late final Stream<int> unread = unreadStream();
  final idCtl = TextEditingController();
  final nav = ValueNotifier<String>('home');

  @override
  void initState() {
    super.initState();
    _links = liveStream('parent_links|parent_id=${myUid}', () => sb.from('parent_links').stream(primaryKey: ['id']).eq('parent_id', myUid)).listen((rows) { if (mounted) { setState(() { links = rows; loaded = true; }); } });
    // Row-level security only returns students whose link was approved, so this is exactly "my children" (live).
    _kids = liveStream('students', () => sb.from('students').stream(primaryKey: ['id'])).listen((rows) {
      if (!mounted) { return; }
      setState(() { kids..clear()..addAll({for (final r in rows) r['id'] as String: r}); });
      for (final r in rows) { _ensureSection(r['section_id'] as String?); }
    });
  }
  @override
  void dispose() { _links?.cancel(); _kids?.cancel(); idCtl.dispose(); nav.dispose(); super.dispose(); }

  Future<void> _ensureSection(String? id) async {
    if (id == null || sectionLabels.containsKey(id)) { return; }
    sectionLabels[id] = '';
    try {
      final s = (await cachedRow('section|$id', () => sb.from('sections').select('name,grade_level').eq('id', id).maybeSingle()))!;
      if (mounted) { setState(() => sectionLabels[id] = 'Grade ${s['grade_level']} · ${s['name']}'); }
    } catch (_) { sectionLabels.remove(id); }
  }

  Future<String?> _kidPhoto(String id) async {
    try { final p = await cachedRow('kidphoto|$id', () => sb.from('kid_photos').select('photo_url').eq('id', id).maybeSingle()); return p?['photo_url'] as String?; } catch (_) { return null; }
  }

  Future<void> _bind() async {
    try {
      await Api.post('/api/parent/bind', {'student_no': idCtl.text});
      idCtl.clear();
      if (mounted) { Navigator.pop(context); toast('Request sent. A teacher will review it.'); }
    } catch (e) { toastError(e); }
  }

  void _dialog() => showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Link your child'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Enter your child\'s Student ID. A teacher approves the link before you can see anything.', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        TextField(controller: idCtl, autofocus: true, decoration: const InputDecoration(labelText: 'Student ID (e.g. 202627-48213)', border: OutlineInputBorder())),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _bind, child: const Text('Send request'))]));

  Widget _requests(List<Map<String, dynamic>> list) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Link requests', icon: Icons.link),
        for (final l in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: SoftCard(child: Row(children: [
          const CircleAvatar(child: Icon(Icons.child_care)), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l['student_name'] ?? 'Student'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${l['student_no'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
          ])),
          Pill(l['status'] == 'pending' ? 'Waiting for a teacher' : 'Declined', l['status'] == 'pending' ? Colors.amber.shade800 : Colors.red, icon: l['status'] == 'pending' ? Icons.hourglass_top : Icons.block),
        ]))),
      ]));

  Widget _noChild(List<Map<String, dynamic>> open) => ListView(padding: const EdgeInsets.all(16), children: [
        if (open.isNotEmpty) _requests(open),
        EmptyState(icon: Icons.family_restroom, title: open.isEmpty ? 'Link your child' : 'Waiting for approval',
            message: open.isEmpty ? 'Enter your child\'s Student ID. After a teacher approves, you will see their attendance, grades and schedule here.' : 'Once a teacher approves the request, your child appears here.',
            action: FilledButton.icon(onPressed: _dialog, icon: const Icon(Icons.person_add), label: const Text('Link a child'))),
      ]);

  /// Long-press a child's name: a small menu offers "Remove", then a confirmation. Removing only stops YOUR view of the child.
  Future<void> _childMenu(Map<String, dynamic> l, Offset at) async {
    final pick = await showMenu<String>(context: context, position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
        items: const [PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.person_remove_outlined, size: 20), SizedBox(width: 10), Text('Remove')]))]);
    if (pick != 'remove' || !mounted) { return; }
    final name = _first(l);
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: Text('Remove $name?'),
      content: Text('You will no longer see $name\'s attendance, grades, schedule or alerts. To view $name again you must send a new link request and a teacher has to approve it.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(d, true), child: const Text('Remove'))]));
    if (ok != true) { return; }
    try {
      await Api.delete('/api/parent/links/${l['student_id']}');
      if (!mounted) { return; }
      setState(() { links = links.where((x) => x['student_id'] != l['student_id']).toList(); if (selectedKid == l['student_id']) { selectedKid = null; } });
      toast('$name removed from your list');
    } catch (e) { toastError(e); }
  }

  Widget _switcher(List<Map<String, dynamic>> approved, String sel) => Container(
        height: 62, width: double.infinity, color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), children: [
          for (final l in approved) Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
            onLongPressStart: (d) => _childMenu(l, d.globalPosition),
            child: ChoiceChip(
              selected: l['student_id'] == sel,
              avatar: CircleAvatar(radius: 11, child: Text(_first(l).isEmpty ? '?' : _first(l)[0].toUpperCase(), style: const TextStyle(fontSize: 11))),
              label: Text(_first(l)), onSelected: (_) => setState(() => selectedKid = l['student_id'] as String),
            ))),
        ]),
      );

  String _first(Map<String, dynamic> l) => '${kids[l['student_id']]?['first_name'] ?? '${l['student_name'] ?? 'Child'}'.split(' ').first}';

  @override
  Widget build(BuildContext c) {
    if (!loaded) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
    final approved = links.where((l) => l['status'] == 'approved' && kids[l['student_id']] != null).toList()..sort((a, b) => _first(a).compareTo(_first(b)));
    final open = links.where((l) => l['status'] != 'approved').toList();
    final sel = approved.any((l) => l['student_id'] == selectedKid) ? selectedKid : (approved.isEmpty ? null : approved.first['student_id'] as String);
    final kid = sel == null ? null : kids[sel];
    final pending = links.where((l) => l['status'] == 'pending').length;
    final sectionId = kid?['section_id'] as String?, name = kid == null ? '' : '${kid['first_name']} ${kid['last_name']}';
    final label = kid == null ? null : (sectionId != null && (sectionLabels[sectionId] ?? '').isNotEmpty ? sectionLabels[sectionId] : 'Grade ${kid['grade_level']} · not in a section yet');
    Widget needChild() => _noChild(open);
    return StreamBuilder<int>(
      stream: unread, initialData: 0,
      builder: (c, u) => FamilyShell(
        selected: nav,
        actions: [IconButton(tooltip: 'Link a child', icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.person_add_alt_1)), onPressed: _dialog)],
        top: (id) => approved.isNotEmpty && (id == 'home' || id == 'attendance' || id == 'grades') ? _switcher(approved, sel!) : null,
        tabs: [
          FamilyTab(id: 'home', label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home, build: () => kid == null ? needChild() : FamilyHome(
              key: ValueKey('home-$sel'), parent: true, studentId: sel!, name: name, studentNo: '${kid['student_no']}', sectionId: sectionId, classLabel: label,
              onGo: (t) => nav.value = t, loadPhoto: () => _kidPhoto(sel!), extra: [if (open.isNotEmpty) _requests(open)])),
        FamilyTab(id: 'feed', label: 'Feed', icon: Icons.dynamic_feed_outlined, selectedIcon: Icons.dynamic_feed, build: () => const FeedView()),
          FamilyTab(id: 'attendance', label: 'Attendance', icon: Icons.how_to_reg_outlined, selectedIcon: Icons.how_to_reg, build: () => kid == null ? needChild()
              : AttendanceView(sel!, key: ValueKey('att-$sel'), sectionId: sectionId, studentName: name, showSubjects: true)),
          FamilyTab(id: 'grades', label: 'Grades', icon: Icons.school_outlined, selectedIcon: Icons.school, build: () => kid == null ? needChild()
              : GradesView(sel!, key: ValueKey('gr-$sel-$sectionId'), sectionId: sectionId, name: name, studentNo: '${kid['student_no']}', classLabel: label)),
          FamilyTab(id: 'alerts', label: 'Alerts', icon: Icons.notifications_outlined, selectedIcon: Icons.notifications, badge: u.data ?? 0, build: () => const NotificationsView()),
          FamilyTab(id: 'profile', label: 'Profile', icon: Icons.person_outline, selectedIcon: Icons.person, build: () => const ProfileTab()),
        ],
      ),
    );
  }
}
