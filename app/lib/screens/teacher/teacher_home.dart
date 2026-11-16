import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/streams.dart';
import '../../core/usb_sync.dart';
import '../../widgets/shared.dart';
import '../profile_screen.dart';
import 'advisory.dart';
import 'bind_requests.dart';
import 'classes.dart';
import 'my_subjects.dart';
import 'usb_panel.dart';

class _Tab {
  final String label; final IconData icon, selectedIcon; final Widget page; final Stream<int>? badge;
  const _Tab(this.label, this.icon, this.selectedIcon, this.page, {this.badge});
}

/// Teacher app. Phones: detailed bottom bar (icons, always-visible labels, counters).
/// Windows / wide screens: navigation rail. Every tab is created the first time it is opened and then kept alive.
/// Sign out is at the bottom of the Profile tab.
class TeacherHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const TeacherHome({super.key, required this.profile});
  @override
  State<TeacherHome> createState() => _TeacherHomeState();
}

class _TeacherHomeState extends State<TeacherHome> {
  final usb = UsbSync();
  int i = 0;
  final visited = <int>{0};
  late final Stream<int> unread = unreadStream(), pending = pendingBindsStream();

  @override
  void initState() { super.initState(); usb.start(); }
  @override
  void dispose() { usb.dispose(); super.dispose(); }

  Widget _icon(_Tab t, bool selected) {
    final icon = Icon(selected ? t.selectedIcon : t.icon);
    if (t.badge == null) { return icon; }
    return StreamBuilder<int>(stream: t.badge, initialData: 0, builder: (c, s) => Badge(isLabelVisible: (s.data ?? 0) > 0, label: Text('${s.data}'), child: icon));
  }

  @override
  Widget build(BuildContext c) {
    final desktop = Platform.isWindows;
    final tabs = <_Tab>[
      _Tab('Advisory', Icons.groups_outlined, Icons.groups, AdvisoryScreen(teacherId: widget.profile['id'])),
      _Tab('Classes', Icons.menu_book_outlined, Icons.menu_book, MyClasses(teacherId: widget.profile['id'])),
      const _Tab('Subjects', Icons.library_books_outlined, Icons.library_books, MySubjects()),
      _Tab('Requests', Icons.how_to_reg_outlined, Icons.how_to_reg, const BindRequests(), badge: pending),
      if (desktop) _Tab('Biometric USB', Icons.usb, Icons.usb, UsbPanel(usb: usb)),
      _Tab('Alerts', Icons.notifications_outlined, Icons.notifications, const NotificationsView(), badge: unread),
      const _Tab('Profile', Icons.person_outline, Icons.person, ProfileTab()),
    ];
    if (i >= tabs.length) { i = 0; }
    visited.add(i);
    final body = IndexedStack(index: i, children: [for (var k = 0; k < tabs.length; k++) visited.contains(k) ? tabs[k].page : const SizedBox.shrink()]);
    return Scaffold(
      appBar: AppBar(
        title: Text(tabs[i].label),
        actions: [if (desktop) ListenableBuilder(listenable: usb, builder: (_, __) => Padding(padding: const EdgeInsets.only(right: 12), child: Tooltip(message: usb.message,
            child: Icon(Icons.usb, color: usb.state == UsbState.none ? Colors.grey : usb.state == UsbState.error ? Colors.red : Colors.greenAccent))))],
      ),
      body: desktop || MediaQuery.sizeOf(c).width >= 900
          ? Row(children: [
              NavigationRail(
                selectedIndex: i, onDestinationSelected: (x) => setState(() => i = x), labelType: NavigationRailLabelType.all,
                destinations: [for (final t in tabs) NavigationRailDestination(icon: _icon(t, false), selectedIcon: _icon(t, true), label: Text(t.label))],
              ),
              const VerticalDivider(width: 1), Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: desktop || MediaQuery.sizeOf(c).width >= 900 ? null : NavigationBar(
        height: 68, labelBehavior: NavigationDestinationLabelBehavior.alwaysShow, selectedIndex: i,
        onDestinationSelected: (x) => setState(() => i = x),
        destinations: [for (final t in tabs) NavigationDestination(icon: _icon(t, false), selectedIcon: _icon(t, true), label: t.label)],
      ),
    );
  }
}
