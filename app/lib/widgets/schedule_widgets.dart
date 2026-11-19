import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/lookup.dart';
import 'colors.dart';
import 'status.dart';
import 'ui.dart';
import '../core/offline.dart';

final _ymd = DateFormat('yyyy-MM-dd');

/// Live weekly schedule of ONE section, with subject + teacher names and "No class" notices already applied.
/// Each slot: the schedules row + subject, teacher, cancelled (bool), cancel_reason, is_today, date.
class SectionFeed extends StatefulWidget {
  final String? sectionId; final String? studentId;       // studentId: also show classes the student took in OTHER sections
  final Widget Function(BuildContext c, List<Map<String, dynamic>> slots, bool loaded) builder;
  const SectionFeed({super.key, required this.sectionId, this.studentId, required this.builder});
  @override
  State<SectionFeed> createState() => _SectionFeedState();
}

class _SectionFeedState extends State<SectionFeed> {
  final rowsBy = <String, List<Map<String, dynamic>>>{}, cancelBy = <String, List<Map<String, dynamic>>>{};
  final subs = <String, List<StreamSubscription<dynamic>>>{};
  List<Map<String, dynamic>> extras = [];
  bool loaded = false;
  StreamSubscription<dynamic>? _x;

  @override
  void initState() { super.initState(); _start(); }
  @override
  void didUpdateWidget(SectionFeed old) {
    super.didUpdateWidget(old);
    if (old.sectionId != widget.sectionId || old.studentId != widget.studentId) { _stop(); loaded = false; extras = []; rowsBy.clear(); cancelBy.clear(); _start(); }
  }
  @override
  void dispose() { _stop(); super.dispose(); }

  void _stop() { _x?.cancel(); _x = null; for (final l in subs.values) { for (final s in l) { s.cancel(); } } subs.clear(); }
  void _start() {
    final sid = widget.studentId;
    if (sid != null) {
      _x = liveStream('student_subjects|student_id=$sid', () => sb.from('student_subjects').stream(primaryKey: ['student_id', 'section_id', 'subject_id']).eq('student_id', sid)).listen((r) { if (mounted) { extras = r; _sync(); setState(() {}); } }, onError: (_) {});
    }
    _sync();
  }

  Set<String> get _ids => {if (widget.sectionId != null) widget.sectionId!, for (final e in extras) e['section_id'] as String};

  void _sync() {                                   // one schedule + one no-class stream per section the student has classes in
    final want = _ids;
    for (final id in subs.keys.where((k) => !want.contains(k)).toList()) { for (final s in subs.remove(id)!) { s.cancel(); } rowsBy.remove(id); cancelBy.remove(id); }
    for (final id in want) {
      if (subs.containsKey(id)) { continue; }
      subs[id] = [
        liveStream('schedules|section_id=$id', () => sb.from('schedules').stream(primaryKey: ['id']).eq('section_id', id)).listen((r) { if (mounted) { setState(() { rowsBy[id] = r; loaded = true; }); } }, onError: (_) {}),
        liveStream('class_cancellations|section_id=$id', () => sb.from('class_cancellations').stream(primaryKey: ['id']).eq('section_id', id)).listen((r) { if (mounted) { setState(() => cancelBy[id] = r); } }, onError: (_) {}),
      ];
    }
    if (want.isEmpty) { loaded = true; }
  }

  List<Map<String, dynamic>> _slots() {
    final now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
    final mine = {for (final e in extras) '${e['section_id']}|${e['subject_id']}'};
    final cmap = <String, Map<String, dynamic>>{for (final l in cancelBy.values) for (final c in l) '${c['cancel_date']}|${c['section_id']}|${c['subject_id']}': c};
    DateTime nextDate(int dow) {
      var d = today;
      for (var i = 0; i < 7; i++) { if (d.weekday == dow) { return d; } d = d.add(const Duration(days: 1)); }
      return today;
    }
    final out = <Map<String, dynamic>>[];
    for (final e in rowsBy.entries) {
      for (final r in e.value) {
        if (e.key != widget.sectionId && !mine.contains('${r['section_id']}|${r['subject_id']}')) { continue; }
        final d = nextDate(r['day_of_week'] as int), c = cmap['${_ymd.format(d)}|${r['section_id']}|${r['subject_id']}'];
        out.add({
          ...r, 'subject': Lookup.i.subject(r['subject_id'] as String?), 'teacher': Lookup.i.teacher(r['teacher_id'] as String?),
          'cancelled': c != null, 'cancel_reason': c?['reason'], 'cancel_message': c?['message'], 'is_today': d == today, 'date': d,
        });
      }
    }
    out.sort((a, b) { final x = (a['day_of_week'] as int).compareTo(b['day_of_week'] as int); return x != 0 ? x : '${a['start_time']}'.compareTo('${b['start_time']}'); });
    return out;
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: Lookup.i, builder: (c, _) => widget.builder(c, _slots(), loaded));
}

void showSlotSheet(BuildContext c, Map<String, dynamic> s) {
  final col = subjectColor('${s['subject']}'), room = (s['room'] ?? '').toString(), cancelled = s['cancelled'] == true;
  showModalBottomSheet<void>(context: c, showDragHandle: true, builder: (_) => SafeArea(child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 6, height: 44, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(4))), const SizedBox(width: 12),
        Expanded(child: Text('${s['subject']}', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
      ]),
      const SizedBox(height: 14),
      _sheetRow(Icons.person, 'Teacher', '${s['teacher']}'),
      _sheetRow(Icons.calendar_today, 'Day', kDays[s['day_of_week'] as int]),
      _sheetRow(Icons.access_time, 'Time', '${t12('${s['start_time']}')} – ${t12('${s['end_time']}')}'),
      if (room.isNotEmpty) _sheetRow(Icons.meeting_room, 'Room', room),
      if (cancelled) Container(
        margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: stColor('N').withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.event_busy, color: stColor('N')), const SizedBox(width: 10),
          Expanded(child: Text('No class on ${DateFormat('EEE, MMM d').format(s['date'] as DateTime)}${s['cancel_reason'] != null ? '\n${s['cancel_reason']}' : ''}${s['cancel_message'] != null ? ' · ${s['cancel_message']}' : ''}', style: TextStyle(color: stColor('N'), fontWeight: FontWeight.w600))),
        ]),
      ),
    ]),
  )));
}

Widget _sheetRow(IconData i, String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
      Icon(i, size: 18), const SizedBox(width: 12), SizedBox(width: 64, child: Text(k, style: const TextStyle(fontSize: 12.5))), Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]));

/// "My schedule": List or Week calendar (same as the teacher Home).
class ScheduleSection extends StatefulWidget {
  final List<Map<String, dynamic>> slots; final String title; final bool showTitle;
  const ScheduleSection({super.key, required this.slots, this.title = 'Class schedule', this.showTitle = true});
  @override
  State<ScheduleSection> createState() => _ScheduleSectionState();
}

class _ScheduleSectionState extends State<ScheduleSection> {
  String mode = 'list';

  Widget _tile(Map<String, dynamic> s) {
    final col = subjectColor('${s['subject']}'), room = (s['room'] ?? '').toString(), cancelled = s['cancelled'] == true, today = s['is_today'] == true;
    final c = Theme.of(context), muted = cancelled ? c.hintColor : null;
    return Card(
      elevation: 0, margin: const EdgeInsets.only(bottom: 8), clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: today && !cancelled ? col : c.dividerColor.withValues(alpha: .4), width: today && !cancelled ? 1.5 : 1)),
      child: InkWell(
        onTap: () => showSlotSheet(context, s),
        child: IntrinsicHeight(child: Row(children: [
          Container(width: 6, color: cancelled ? stColor('N') : col),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: SizedBox(width: 64, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(t12('${s['start_time']}'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: muted)),
            Text(t12('${s['end_time']}'), style: TextStyle(fontSize: 11, color: c.hintColor)),
          ]))),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['subject']}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: muted, decoration: cancelled ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 2),
            Text('${s['teacher']}${room.isEmpty ? '' : ' · $room'}', style: const TextStyle(fontSize: 13)),
          ]))),
          if (cancelled) Padding(padding: const EdgeInsets.only(right: 10), child: Pill('No class', stColor('N'), icon: Icons.event_busy)),
        ])),
      ),
    );
  }

  Widget _listMode(List<Map<String, dynamic>> slots) {
    final today = DateTime.now().weekday;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var d = 1; d <= 5; d++) ...[
        if (slots.any((s) => s['day_of_week'] == d)) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 10, 0, 6), child: Row(children: [
            Text(kDays[d], style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            if (d == today) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(10)),
                child: Text('Today', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 11))),
          ])),
          for (final s in slots.where((s) => s['day_of_week'] == d)) _tile(s),
        ],
      ],
    ]);
  }

  Widget _weekMode(List<Map<String, dynamic>> slots) {
    var lo = 24 * 60, hi = 0;
    for (final s in slots) { lo = math.min(lo, minOf('${s['start_time']}')); hi = math.max(hi, minOf('${s['end_time']}')); }
    final start = math.max(6 * 60, (lo ~/ 60) * 60), end = math.min(20 * 60, ((hi + 59) ~/ 60) * 60);
    const hourH = 60.0, timeW = 42.0, headH = 30.0;
    final now = DateTime.now(), today = now.weekday, nowMin = now.hour * 60 + now.minute;
    return LayoutBuilder(builder: (c, box) {
      final colW = math.max(104.0, (box.maxWidth - timeW) / 5);
      final totalH = headH + (end - start) / 60 * hourH;
      double y(int m) => headH + (m - start) / 60 * hourH;
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: timeW + colW * 5, height: totalH, child: Stack(children: [
        for (var d = 1; d <= 5; d++) Positioned(left: timeW + (d - 1) * colW, top: 0, width: colW, bottom: 0, child: Container(
            decoration: BoxDecoration(color: d == today ? Theme.of(c).colorScheme.primary.withValues(alpha: .06) : null, border: Border(left: BorderSide(color: Theme.of(c).dividerColor.withValues(alpha: .3)))),
            child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(kDayShort[d], style: TextStyle(fontWeight: d == today ? FontWeight.bold : FontWeight.w500, color: d == today ? Theme.of(c).colorScheme.primary : null)))))),
        for (var m = start; m <= end; m += 60) Positioned(top: y(m) - 7, left: 0, right: 0, child: Row(children: [
          SizedBox(width: timeW, child: Text(t12('${(m ~/ 60).toString().padLeft(2, '0')}:00'), textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Theme.of(c).hintColor))),
          Expanded(child: Divider(height: 1, color: Theme.of(c).dividerColor.withValues(alpha: .35))),
        ])),
        for (final s in slots) () {
          final a = minOf('${s['start_time']}'), b = minOf('${s['end_time']}'), cancelled = s['cancelled'] == true;
          final col = cancelled ? stColor('N') : subjectColor('${s['subject']}');
          return Positioned(
            left: timeW + ((s['day_of_week'] as int) - 1) * colW + 3, top: y(a) + 1, width: colW - 6, height: math.max(34.0, (b - a) / 60 * hourH - 2),
            child: Material(color: col.withValues(alpha: .16), borderRadius: BorderRadius.circular(10), clipBehavior: Clip.antiAlias, child: InkWell(
              onTap: () => showSlotSheet(c, s),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4), decoration: BoxDecoration(border: Border(left: BorderSide(color: col, width: 4))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['subject']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: col, decoration: cancelled ? TextDecoration.lineThrough : null)),
                  Text(cancelled ? 'No class' : '${s['teacher']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5)),
                ]),
              ),
            )),
          );
        }(),
        if (today <= 5 && nowMin >= start && nowMin <= end) Positioned(left: timeW + (today - 1) * colW, width: colW, top: y(nowMin), child: Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)), Expanded(child: Container(height: 1.5, color: Colors.red)),
        ])),
      ])));
    });
  }

  @override
  Widget build(BuildContext c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (widget.showTitle) Expanded(child: Text(widget.title, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))) else const Spacer(),
          SegmentedButton<String>(
            showSelectedIcon: false, style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [ButtonSegment(value: 'list', icon: Icon(Icons.view_agenda_outlined, size: 18), label: Text('List')), ButtonSegment(value: 'week', icon: Icon(Icons.calendar_view_week, size: 18), label: Text('Week'))],
            selected: {mode}, onSelectionChanged: (v) => setState(() => mode = v.first),
          ),
        ]),
        const SizedBox(height: 8),
        if (widget.slots.isEmpty) SoftCard(child: const Padding(padding: EdgeInsets.all(14), child: Center(child: Text('No classes scheduled yet.\nThey appear here as soon as your teachers set the schedule.', textAlign: TextAlign.center))))
        else if (mode == 'list') _listMode(widget.slots) else _weekMode(widget.slots),
      ]);
}

/// "Approaching class": in session / next class with a live countdown, later today, and no-class notices.
class ApproachingClass extends StatelessWidget {
  final List<Map<String, dynamic>> slots;
  const ApproachingClass({super.key, required this.slots});

  Widget _later(BuildContext c, Map<String, dynamic> s) {
    final col = subjectColor('${s['subject']}');
    return Card(
      elevation: 0, margin: const EdgeInsets.only(bottom: 8), clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(c).dividerColor.withValues(alpha: .4))),
      child: IntrinsicHeight(child: Row(children: [
        Container(width: 6, color: col),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: SizedBox(width: 64, child: Column(children: [
          Text(t12('${s['start_time']}'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text(t12('${s['end_time']}'), style: TextStyle(fontSize: 11, color: Theme.of(c).hintColor))]))),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['subject']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)), Text('${s['teacher']}', style: const TextStyle(fontSize: 13))]))),
      ])),
    );
  }

  Widget _hero(BuildContext c, {required String label, required Map<String, dynamic> s, required String big, double? progress}) {
    final col = subjectColor('${s['subject']}'), room = (s['room'] ?? '').toString();
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors: [col, Color.lerp(col, Colors.black, .3)!], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: .6))),
          const Spacer(), Text('${t12('${s['start_time']}')} – ${t12('${s['end_time']}')}', style: const TextStyle(color: Colors.white)),
        ]),
        const SizedBox(height: 12),
        Text(big, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('${s['subject']}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        Text('${s['teacher']}${room.isEmpty ? '' : ' · $room'}', style: TextStyle(color: Colors.white.withValues(alpha: .9))),
        if (progress != null) Padding(padding: const EdgeInsets.only(top: 12), child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 6, backgroundColor: Colors.white24, color: Colors.white))),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    final now = DateTime.now();
    DateTime at(String t) { final m = minOf(t); return DateTime(now.year, now.month, now.day, m ~/ 60, m % 60); }
    final todays = slots.where((s) => s['day_of_week'] == now.weekday).toList();
    final off = todays.where((s) => s['cancelled'] == true).toList();
    final live = todays.where((s) => s['cancelled'] != true).toList();
    final ongoing = live.where((s) => !at('${s['start_time']}').isAfter(now) && at('${s['end_time']}').isAfter(now)).toList();
    final upcoming = live.where((s) => at('${s['start_time']}').isAfter(now)).toList();
    Map<String, dynamic>? later; var laterIn = 0;
    if (ongoing.isEmpty && upcoming.isEmpty) {
      for (var add = 1; add <= 7 && later == null; add++) {
        final d = now.add(Duration(days: add));
        final list = slots.where((s) => s['day_of_week'] == d.weekday && s['cancelled'] != true).toList();
        if (list.isNotEmpty) { later = list.first; laterIn = add; }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Approaching class', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      for (final s in off) Padding(padding: const EdgeInsets.only(bottom: 10), child: Container(
        padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: stColor('N').withValues(alpha: .12), borderRadius: BorderRadius.circular(14), border: Border.all(color: stColor('N').withValues(alpha: .4))),
        child: Row(children: [
          Icon(Icons.event_busy, color: stColor('N')), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No ${s['subject']} class today', style: TextStyle(fontWeight: FontWeight.bold, color: stColor('N'))),
            Text('${t12('${s['start_time']}')} – ${t12('${s['end_time']}')}${s['cancel_reason'] != null ? ' · ${s['cancel_reason']}' : ''}. You will not be marked absent.', style: const TextStyle(fontSize: 12.5)),
          ])),
        ]),
      )),
      for (final s in ongoing) Padding(padding: const EdgeInsets.only(bottom: 10), child: _hero(c, label: 'IN SESSION', s: s, big: 'Ends in ${leftText(at('${s['end_time']}').difference(now))}',
          progress: now.difference(at('${s['start_time']}')).inSeconds / at('${s['end_time']}').difference(at('${s['start_time']}')).inSeconds)),
      if (upcoming.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.only(bottom: 10), child: () {
          final s = upcoming.first, left = at('${s['start_time']}').difference(now);
          return _hero(c, label: 'NEXT CLASS', s: s, big: 'Starts in ${leftText(left)}', progress: 1 - left.inMinutes / 60);
        }()),
        if (upcoming.length > 1) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 4, 0, 6), child: Text('Later today', style: Theme.of(c).textTheme.titleSmall)),
          for (final s in upcoming.skip(1)) _later(c, s),
        ],
      ],
      if (ongoing.isEmpty && upcoming.isEmpty) ...[
        if (later != null) _hero(c, label: laterIn == 1 ? 'TOMORROW' : kDayShort[(later['day_of_week'] as int)].toUpperCase(), s: later, big: off.isEmpty ? 'No more classes today' : 'No class left today')
        else if (off.isEmpty) SoftCard(child: const Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Nothing coming up.')))),
      ],
    ]);
  }
}

/// Plain schedule of a section (used by the adviser screen and anywhere a bare schedule is needed).
class ScheduleView extends StatelessWidget {
  final String? sectionId; const ScheduleView(this.sectionId, {super.key});
  @override
  Widget build(BuildContext c) {
    if (sectionId == null) { return const EmptyState(icon: Icons.calendar_month, title: 'Not in a section yet', message: 'The schedule appears once an adviser adds the student.'); }
    return SectionFeed(sectionId: sectionId, builder: (c, slots, loaded) => !loaded
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [ScheduleSection(slots: slots, showTitle: false)]));
  }
}
