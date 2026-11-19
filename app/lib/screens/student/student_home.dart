import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/streams.dart';
import '../../widgets/family_home.dart';
import '../../widgets/family_shell.dart';
import '../../widgets/feed_view.dart';
import '../../widgets/shared.dart';
import '../profile_screen.dart';
import '../../widgets/chat_actions.dart';
import '../../core/chat_data.dart';
import '../../core/messenger.dart';
import '../../widgets/notifications_view.dart';
import '../../core/offline.dart';

/// Student app: Home, Attendance, Grades, Alerts, Profile (bottom bar, same layout as the teacher app).
/// Sign out is at the bottom of the Profile tab.
class StudentHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StudentHome({super.key, required this.profile});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  Map<String, dynamic>? st;
  String? sectionLabel, _sectionFor;
  StreamSubscription<dynamic>? _sub, _alerts;
  final _shown = <String>{}; bool _primed = false;
  late final Stream<int> unread = unreadStream();
  final nav = ValueNotifier<String>('home');

  @override
  void initState() {
    super.initState();
    _watchAlerts();
    _sub = liveStream('students|id=${widget.profile['id']}', () => sb.from('students').stream(primaryKey: ['id']).eq('id', widget.profile['id'])).listen((rows) {
      if (rows.isEmpty || !mounted) { return; }
      setState(() => st = rows.first);
      _loadSection();
    });
  }
  /// Pop-up banner when a new chat message arrives while the app is open (everything is also kept in the Alerts tab).
  void _watchAlerts() {
    _alerts = liveStream('notifications|user_id=$myUid|o', () => sb.from('notifications').stream(primaryKey: ['id']).eq('user_id', myUid).order('created_at', ascending: false)).listen((rows) {
      final fresh = [for (final n in rows) if (n['kind'] == 'chat' && n['read'] != true && _shown.add('${n['id']}|${n['created_at']}')) n];
      if (!_primed) { _primed = true; return; }                       // what was already there when the app opened is not a pop-up
      if (fresh.isEmpty || !mounted) { return; }
      final n = fresh.first, d = n['data'] is Map ? n['data'] as Map : const {};
      if (d['thread_id'] != null && d['thread_id'] == ChatData.viewing) { return; }
      messengerKey.currentState?..hideCurrentSnackBar()..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 5),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${n['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${n['body']}', maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
        action: SnackBarAction(label: 'Open', onPressed: () { if (mounted) { openChatAlert(context, n); } }),
      ));
    });
  }

  @override
  void dispose() { _alerts?.cancel(); _sub?.cancel(); nav.dispose(); super.dispose(); }

  Future<void> _loadSection() async {
    final id = st?['section_id'] as String?;
    if (id == _sectionFor) { return; }
    _sectionFor = id;
    if (id == null) { if (mounted) { setState(() => sectionLabel = null); } return; }
    try {
      final s = (await cachedRow('section|$id', () => sb.from('sections').select('name,grade_level').eq('id', id).maybeSingle()))!;
      if (mounted) { setState(() => sectionLabel = 'Grade ${s['grade_level']} · ${s['name']}'); }
    } catch (_) {}
  }

  Future<String?> _photo() async {
    final p = await cachedRow('myphoto', () => sb.from('profiles').select('photo_url').eq('id', widget.profile['id']).maybeSingle());
    return p?['photo_url'] as String?;
  }

  @override
  Widget build(BuildContext c) {
    final s = st;
    if (s == null) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
    final id = s['id'] as String, sectionId = s['section_id'] as String?, name = '${s['first_name']} ${s['last_name']}';
    return StreamBuilder<int>(
      stream: unread, initialData: 0,
      builder: (c, u) => FamilyShell(selected: nav, actions: [if (sectionId != null) const ChatActions()], tabs: [
        FamilyTab(id: 'home', label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home,
            build: () => FamilyHome(studentId: id, name: name, studentNo: '${s['student_no']}', photo: widget.profile['photo_url'] as String?, sectionId: sectionId, classLabel: sectionLabel, onGo: (t) => nav.value = t, loadPhoto: _photo)),
        FamilyTab(id: 'feed', label: 'Feed', icon: Icons.dynamic_feed_outlined, selectedIcon: Icons.dynamic_feed, build: () => FeedView(student: true, sectionId: sectionId)),
        FamilyTab(id: 'attendance', label: 'Attendance', icon: Icons.how_to_reg_outlined, selectedIcon: Icons.how_to_reg,
            build: () => AttendanceView(id, sectionId: sectionId, studentName: name, showSubjects: true)),
        FamilyTab(id: 'grades', label: 'Grades', icon: Icons.school_outlined, selectedIcon: Icons.school,
            build: () => GradesView(id, key: ValueKey('gr-$sectionId'), sectionId: sectionId, name: name, studentNo: '${s['student_no']}', classLabel: sectionLabel ?? 'Grade ${s['grade_level']}')),
        FamilyTab(id: 'alerts', label: 'Alerts', icon: Icons.notifications_outlined, selectedIcon: Icons.notifications, badge: u.data ?? 0, build: () => const NotificationsView()),
        FamilyTab(id: 'profile', label: 'Profile', icon: Icons.person_outline, selectedIcon: Icons.person, build: () => const ProfileTab()),
      ]),
    );
  }
}
