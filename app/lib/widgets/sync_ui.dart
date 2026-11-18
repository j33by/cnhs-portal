import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/offline.dart';
import '../core/outbox.dart';

void showSyncSheet(BuildContext c) => showModalBottomSheet<void>(context: c, isScrollControlled: true, showDragHandle: true, builder: (_) => const _SyncSheet());

class _SyncSheet extends StatelessWidget {
  const _SyncSheet();
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: Listenable.merge([Outbox.i, Net.i]), builder: (c, _) {
        final items = Outbox.i.mine, notes = Outbox.i.myNotes, f = DateFormat('MMM d, h:mm a');
        return SafeArea(child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .8), child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), shrinkWrap: true, children: [
          Text('Sync status', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(Net.i.online ? 'Online. Saved changes are sent automatically.' : "Offline. Changes are saved on this phone and are sent automatically when the internet is back.", style: TextStyle(color: Theme.of(c).hintColor)),
          const SizedBox(height: 12),
          if (items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('Everything is synced.'))),
          for (final it in items) Card(
            elevation: 0, margin: const EdgeInsets.only(bottom: 8), color: it.state == 'failed' ? Colors.red.withValues(alpha: .08) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: it.state == 'failed' ? Colors.red : Theme.of(c).dividerColor.withValues(alpha: .4))),
            child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(it.state == 'failed' ? Icons.error_outline : it.sending ? Icons.sync : Icons.cloud_upload_outlined, color: it.state == 'failed' ? Colors.red : Colors.amber.shade800),
                const SizedBox(width: 10),
                Expanded(child: Text(it.label, style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              Padding(padding: const EdgeInsets.only(left: 34, top: 2), child: Text('Saved ${f.format(it.created)} · ${it.state == 'failed' ? 'needs attention' : it.sending ? 'sending…' : 'waiting for internet'}', style: const TextStyle(fontSize: 12.5))),
              if (it.state == 'failed' && it.message != null) Padding(padding: const EdgeInsets.only(left: 34, top: 4), child: Text('${it.message}', style: TextStyle(fontSize: 12.5, color: Colors.red.shade700))),
              if (it.state == 'failed') Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
                const SizedBox(width: 24),
                TextButton(onPressed: () => Outbox.i.retry(it), child: const Text('Retry')),
                TextButton(onPressed: () => Outbox.i.discard(it), child: Text('Discard', style: TextStyle(color: Colors.red.shade700))),
              ])),
            ])),
          ),
          if (items.any((x) => x.state != 'failed') && Net.i.online) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => Outbox.i.flush(), icon: const Icon(Icons.sync, size: 18), label: const Text('Sync now'))),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [Expanded(child: Text('Not applied', style: Theme.of(c).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))), TextButton(onPressed: Outbox.i.clearNotes, child: const Text('Clear'))]),
            for (final n in notes) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.info_outline), title: Text('${n['label']}'), subtitle: Text('${n['text']}')),
          ],
        ])));
      });
}
