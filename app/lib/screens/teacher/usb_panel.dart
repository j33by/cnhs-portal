import 'package:flutter/material.dart';
import '../../core/usb_sync.dart';

class UsbPanel extends StatelessWidget {
  final UsbSync usb; const UsbPanel({super.key, required this.usb});
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: usb, builder: (c, _) {
        final col = switch (usb.state) { UsbState.none => Colors.grey, UsbState.error => Colors.red, _ => Colors.green };
        return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.usb, size: 96, color: col), const SizedBox(height: 12),
          Text(usb.message, style: Theme.of(c).textTheme.titleMedium, textAlign: TextAlign.center),
          if (usb.lastSync != null) Text('Last sync ${TimeOfDay.fromDateTime(usb.lastSync!).format(c)}'),
          const SizedBox(height: 24),
          if (usb.state == UsbState.syncing) const CircularProgressIndicator()
          else FilledButton.icon(onPressed: usb.state == UsbState.none ? null : usb.syncNow, icon: const Icon(Icons.sync), label: const Text('Sync now')),
          const SizedBox(height: 24),
          const Text('Plug the USB from the biometric terminal into this PC. Attendance is read automatically, parents and students are notified, and Employee_Form.xls on the stick is updated with the latest students, sections and schedules.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ])));
      });
}
