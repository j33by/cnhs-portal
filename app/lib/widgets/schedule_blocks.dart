import 'package:flutter/material.dart';

class _Block {
  final days = <int>{};
  TimeOfDay? start, end;
}

/// One or more schedule blocks. Each block = days of the week + start time + end time.
/// onChanged gives: [{days:[1,3,5], start_time:'07:30', end_time:'08:30'}]
class ScheduleBlocks extends StatefulWidget {
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  const ScheduleBlocks({super.key, required this.onChanged});
  @override
  State<ScheduleBlocks> createState() => _ScheduleBlocksState();
}

class _ScheduleBlocksState extends State<ScheduleBlocks> {
  final blocks = <_Block>[_Block()];
  static const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _emit()); }

  String _fmt(TimeOfDay? t) => t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  void _emit() => widget.onChanged([for (final b in blocks) {'days': (b.days.toList()..sort()), 'start_time': _fmt(b.start), 'end_time': _fmt(b.end)}]);

  Future<void> _pick(_Block b, bool start) async {
    final t = await showTimePicker(context: context, initialTime: (start ? b.start : b.end) ?? const TimeOfDay(hour: 7, minute: 30));
    if (t == null) return;
    setState(() { if (start) { b.start = t; } else { b.end = t; } });
    _emit();
  }

  @override
  Widget build(BuildContext c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < blocks.length; i++) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Schedule ${i + 1}', style: Theme.of(c).textTheme.titleSmall), const Spacer(),
            if (blocks.length > 1) IconButton(icon: const Icon(Icons.close), tooltip: 'Remove', onPressed: () { setState(() => blocks.removeAt(i)); _emit(); }),
          ]),
          Wrap(spacing: 6, children: [for (var d = 1; d <= 5; d++) FilterChip(label: Text(dayNames[d - 1]), selected: blocks[i].days.contains(d),
              onSelected: (on) { setState(() { if (on) { blocks[i].days.add(d); } else { blocks[i].days.remove(d); } }); _emit(); })]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.access_time), label: Text(blocks[i].start == null ? 'Start time' : blocks[i].start!.format(c)), onPressed: () => _pick(blocks[i], true))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.access_time_filled), label: Text(blocks[i].end == null ? 'End time' : blocks[i].end!.format(c)), onPressed: () => _pick(blocks[i], false))),
          ]),
        ]))),
        TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add another schedule'), onPressed: () { setState(() => blocks.add(_Block())); _emit(); }),
      ]);
}

/// null when every block is complete, otherwise a message for the teacher.
String? validateBlocks(List<Map<String, dynamic>> blocks) {
  if (blocks.isEmpty) return 'Add at least one schedule';
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i]; final n = blocks.length > 1 ? 'Schedule ${i + 1}: ' : '';
    if ((b['days'] as List).isEmpty) return '${n}pick at least one day';
    final st = '${b['start_time']}', en = '${b['end_time']}';
    if (st.isEmpty || en.isEmpty) return '${n}choose the start and end time';
    if (st.compareTo(en) >= 0) return '${n}end time must be after the start time';
  }
  return null;
}

String _h12(String hhmm) {
  final p = hhmm.split(':'); final h = int.parse(p[0]);
  return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
}

/// "Mon · Wed · Fri  7:30 AM – 8:30 AM", one line per block.
String describeBlocks(List<Map<String, dynamic>> blocks) {
  const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
  return blocks.where((b) => (b['days'] as List).isNotEmpty && '${b['start_time']}'.isNotEmpty && '${b['end_time']}'.isNotEmpty).map((b) =>
      '${(b['days'] as List).map((d) => names[d as int]).join(' · ')}   ${_h12('${b['start_time']}')} – ${_h12('${b['end_time']}')}').join('\n');
}
