import 'package:flutter/material.dart';
import '../../widgets/notifications_view.dart';
import 'no_class_tab.dart';

/// Teacher "Alerts": the notification inbox, and the No-class announcer.
class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});
  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  int seg = 0;
  bool openedNoClass = false;

  @override
  Widget build(BuildContext c) {
    if (seg == 1) { openedNoClass = true; }
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 4), child: SizedBox(width: double.infinity, child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, icon: Icon(Icons.notifications_outlined, size: 18), label: Text('Notifications')),
          ButtonSegment(value: 1, icon: Icon(Icons.event_busy, size: 18), label: Text('No class')),
        ],
        selected: {seg}, onSelectionChanged: (v) => setState(() => seg = v.first),
      ))),
      Expanded(child: IndexedStack(index: seg, children: [
        TickerMode(enabled: seg == 0, child: const NotificationsView()),
        TickerMode(enabled: seg == 1, child: openedNoClass ? const NoClassTab() : const SizedBox.shrink()),
      ])),
    ]);
  }
}
