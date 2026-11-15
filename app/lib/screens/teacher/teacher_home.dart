import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/usb_sync.dart';
import '../../widgets/shared.dart';
import 'advisory.dart';
import 'classes.dart';
import 'bind_requests.dart';
import 'my_subjects.dart';
import 'usb_panel.dart';
import '../profile_screen.dart';

class TeacherHome extends StatefulWidget { final Map<String, dynamic> profile; const TeacherHome({super.key, required this.profile}); @override State<TeacherHome> createState() => _T(); }
class _T extends State<TeacherHome> {
  final usb = UsbSync(); int i = 0;
  @override void initState() { super.initState(); usb.start(); }
  @override void dispose() { usb.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) {
    final desktop = Platform.isWindows;
    final tabs = <(String, IconData, Widget)>[
      ('Advisory', Icons.groups, AdvisoryScreen(teacherId: widget.profile['id'])),
      ('My classes', Icons.menu_book, MyClasses(teacherId: widget.profile['id'])),
      ('Subjects', Icons.subject, const MySubjects()),
      ('Requests', Icons.link, const BindRequests()),
      if (desktop) ('Biometric USB', Icons.usb, UsbPanel(usb: usb)),
      ('Alerts', Icons.notifications, const NotificationsView()),
      ('Profile', Icons.person, const ProfileTab()),
    ];
    final body = tabs[i].$3;
    return Scaffold(
      appBar: AppBar(title: Text(tabs[i].$1), actions: [if (desktop) ListenableBuilder(listenable: usb, builder: (_, __) => Icon(Icons.usb, color: usb.state == UsbState.none ? Colors.grey : usb.state == UsbState.error ? Colors.red : Colors.greenAccent)), IconButton(icon: const Icon(Icons.logout), onPressed: () => sb.auth.signOut())]),
      body: desktop ? Row(children: [NavigationRail(selectedIndex: i, onDestinationSelected: (x) => setState(() => i = x), labelType: NavigationRailLabelType.all, destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$2), label: Text(t.$1))]), const VerticalDivider(width: 1), Expanded(child: body)]) : body,
      bottomNavigationBar: desktop ? null : NavigationBar(labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected, selectedIndex: i, onDestinationSelected: (x) => setState(() => i = x), destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1)]),
    );
  }
}
