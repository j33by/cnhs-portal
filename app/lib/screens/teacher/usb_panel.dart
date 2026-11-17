import 'package:flutter/material.dart';
import '../../core/usb_sync.dart';
import 'device_links.dart';

class UsbPanel extends StatelessWidget {
  final UsbSync usb; const UsbPanel({super.key, required this.usb});
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: usb, builder: (c, _) {
        final col = switch (usb.state) { UsbState.none => Colors.grey, UsbState.error => Colors.red, _ => Colors.green };
        return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          Icon(Icons.usb, size: 96, color: col), const SizedBox(height: 12), const UnlinkedDeviceCount(),
          Text(usb.message, style: Theme.of(c).textTheme.titleMedium, textAlign: TextAlign.center),
          if (usb.lastSync != null) Text('Last sync ${TimeOfDay.fromDateTime(usb.lastSync!).format(c)}'),
          const SizedBox(height: 24),
          if (usb.state == UsbState.syncing) const CircularProgressIndicator()
          else FilledButton.icon(onPressed: usb.state == UsbState.none ? null : usb.syncNow, icon: const Icon(Icons.sync), label: const Text('Sync now')),
          const SizedBox(height: 24),
          const Text('Plug the USB from the biometric terminal into this PC. Attendance is read automatically, parents and students are notified, and Employee_Form.xls on the stick is updated with the latest students, sections and schedules.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          const Text('30 minutes after a sync, students who have no fingerprint punch for the day are marked absent automatically and their parents are notified. Subject teachers can still mark a student present, absent or excused in their own class.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ])));
      });
}
