import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../widgets/ui.dart';
import 'package:flutter/services.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../core/teacher_data.dart';
import '../../widgets/colors.dart';
import '../../widgets/shared.dart';
import '../../core/offline.dart';
import '../../core/img.dart';

const _dayShort = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

int _min(String t) { final p = t.split(':'); return int.parse(p[0]) * 60 + int.parse(p[1]); }
String _hm(String t) => t12(t);
String _left(Duration d) {
  final m = d.inMinutes;
  if (m < 1) { return 'less than a minute'; }
  if (m < 60) { return '$m min'; }
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

/// Home: who I am, my weekly schedule (list or calendar) and the class that is coming up.
class HomeTab extends StatefulWidget {
  final Map<String, dynamic> profile;
  final void Function(Map<String, dynamic> cls) onOpenClass;
  const HomeTab({super.key, required this.profile, required this.onOpenClass});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, dynamic>? me;            // teachers row: teacher_no, alert_minutes
  String? photo;
  String mode = 'list';                // list | week
  Timer? _tick;
  bool _wasVisible = false;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) { setState(() {}); } });   // live countdown
  }
  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  Future<void> _loadMe() async {
    try {
      final uid = myUid;
      final t = await cachedRow('me-teacher-home', () => sb.from('teachers').select('teacher_no,alert_minutes').eq('id', uid).maybeSingle());
      final p = await cachedRow('myphoto', () => sb.from('profiles').select('photo_url').eq('id', uid).maybeSingle());
      if (mounted) { setState(() { me = t; photo = p?['photo_url'] as String?; }); }
    } catch (e) { toastError(e); }
  }

  Future<void> _setAlert(int v) async {
    try {
      await Api.patch('/api/me', {'alert_minutes': v});
      setState(() => me = {...?me, 'alert_minutes': v});
      toast(v == 0 ? 'Class reminders are off' : 'You will be notified $v minutes before each class');
    } catch (e) { toastError(e); }
  }

  String _greeting() { final h = DateTime.now().hour; return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'; }

  // ---------------------------------------------------------------- header
  Widget _header(BuildContext c) {
    final name = '${widget.profile['full_name']}';
    final id = me?['teacher_no'];
    return SchoolBackdrop(
      child: Column(children: [
        Text('${_greeting()}!', style: TextStyle(color: Colors.white.withValues(alpha: .85))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: CircleAvatar(radius: 52, backgroundImage: (photo ?? widget.profile['photo_url']) != null ? CachedNetImage((photo ?? widget.profile['photo_url']) as String) : null,
              child: (photo ?? widget.profile['photo_url']) == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 38)) : null),
        ),
        const SizedBox(height: 12),
        Text(name, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: id == null ? null : () { Clipboard.setData(ClipboardData(text: '$id')); toast('Teacher ID copied'); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.badge, size: 16, color: Colors.white), const SizedBox(width: 6),
              Text('Teacher ID  ${id ?? '…'}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: .5)),
              const SizedBox(width: 6), Icon(Icons.copy, size: 14, color: Colors.white.withValues(alpha: .8)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- schedule
  Widget _slotTile(Map<String, dynamic> s, {bool today = false}) {
    final col = subjectColor('${s['subject']}');
    final room = (s['room'] ?? '').toString();
    return Card(
      elevation: 0, margin: const EdgeInsets.only(bottom: 8), clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: today ? col : Theme.of(context).dividerColor.withValues(alpha: .4), width: today ? 1.5 : 1)),
      child: InkWell(
        onTap: () => widget.onOpenClass(s['cls'] as Map<String, dynamic>),
        child: IntrinsicHeight(child: Row(children: [
          Container(width: 6, color: col),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: SizedBox(width: 64, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_hm('${s['start_time']}'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(_hm('${s['end_time']}'), style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          ]))),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['subject']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 2),
            Text('Grade ${s['grade']} · ${s['section']}${room.isEmpty ? '' : ' · $room'}', style: const TextStyle(fontSize: 13)),
          ]))),
          if (s['adviser'] == true) Padding(padding: const EdgeInsets.only(right: 10), child: Tooltip(message: 'You are the adviser', child: Icon(Icons.star_rounded, color: Colors.amber.shade700))),
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
          for (final s in (slots.where((s) => s['day_of_week'] == d).toList()..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}')))) _slotTile(s, today: d == today),
        ],
      ],
    ]);
  }

  Widget _weekMode(List<Map<String, dynamic>> slots) {
    var lo = 24 * 60, hi = 0;
    for (final s in slots) { lo = math.min(lo, _min('${s['start_time']}')); hi = math.max(hi, _min('${s['end_time']}')); }
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
            child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(_dayShort[d], style: TextStyle(fontWeight: d == today ? FontWeight.bold : FontWeight.w500, color: d == today ? Theme.of(c).colorScheme.primary : null)))))),
        for (var m = start; m <= end; m += 60) Positioned(top: y(m) - 7, left: 0, right: 0, child: Row(children: [
          SizedBox(width: timeW, child: Text(_hm('${(m ~/ 60).toString().padLeft(2, '0')}:00'), textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Theme.of(c).hintColor))),
          Expanded(child: Divider(height: 1, color: Theme.of(c).dividerColor.withValues(alpha: .35))),
        ])),
        for (final s in slots) () {
          final a = _min('${s['start_time']}'), b = _min('${s['end_time']}'), col = subjectColor('${s['subject']}');
          return Positioned(
            left: timeW + ((s['day_of_week'] as int) - 1) * colW + 3, top: y(a) + 1, width: colW - 6, height: math.max(34.0, (b - a) / 60 * hourH - 2),
            child: Material(color: col.withValues(alpha: .16), borderRadius: BorderRadius.circular(10), clipBehavior: Clip.antiAlias, child: InkWell(
              onTap: () => widget.onOpenClass(s['cls'] as Map<String, dynamic>),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4), decoration: BoxDecoration(border: Border(left: BorderSide(color: col, width: 4))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['subject']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: col)),
                  Text('G${s['grade']} ${s['section']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5)),
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

  Widget _scheduleSection(BuildContext c, List<Map<String, dynamic>> slots) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('My schedule', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          SegmentedButton<String>(
            showSelectedIcon: false, style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [ButtonSegment(value: 'list', icon: Icon(Icons.view_agenda_outlined, size: 18), label: Text('List')), ButtonSegment(value: 'week', icon: Icon(Icons.calendar_view_week, size: 18), label: Text('Week'))],
            selected: {mode}, onSelectionChanged: (v) => setState(() => mode = v.first),
          ),
        ]),
        const SizedBox(height: 8),
        if (slots.isEmpty) Card(elevation: 0, color: Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: .5), child: const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No classes scheduled yet.\nOpen the Classes tab and tap "Add class".', textAlign: TextAlign.center))))
        else if (mode == 'list') _listMode(slots) else _weekMode(slots),
      ]);

  // ---------------------------------------------------------------- approaching class
  Widget _approaching(BuildContext c, List<Map<String, dynamic>> slots) {
    final now = DateTime.now();
    DateTime at(DateTime day, String t) { final m = _min(t); return DateTime(day.year, day.month, day.day, m ~/ 60, m % 60); }
    final todays = slots.where((s) => s['day_of_week'] == now.weekday).toList()..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
    final ongoing = todays.where((s) => !at(now, '${s['start_time']}').isAfter(now) && at(now, '${s['end_time']}').isAfter(now)).toList();
    final upcoming = todays.where((s) => at(now, '${s['start_time']}').isAfter(now)).toList();
    Map<String, dynamic>? later; int laterIn = 0;
    if (ongoing.isEmpty && upcoming.isEmpty) {
      for (var add = 1; add <= 7 && later == null; add++) {
        final d = now.add(Duration(days: add));
        final list = slots.where((s) => s['day_of_week'] == d.weekday).toList()..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
        if (list.isNotEmpty) { later = list.first; laterIn = add; }
      }
    }
    final alert = (me?['alert_minutes'] as int?) ?? 10;

    Widget hero({required String label, required Map<String, dynamic> s, required String big, double? progress}) {
      final col = subjectColor('${s['subject']}');
      final room = (s['room'] ?? '').toString();
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors: [col, Color.lerp(col, Colors.black, .3)!], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: .6))),
            const Spacer(), Text('${_hm('${s['start_time']}')} – ${_hm('${s['end_time']}')}', style: const TextStyle(color: Colors.white)),
          ]),
          const SizedBox(height: 12),
          Text(big, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('${s['subject']}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          Text('Grade ${s['grade']} · ${s['section']}${room.isEmpty ? '' : ' · $room'}', style: TextStyle(color: Colors.white.withValues(alpha: .9))),
          if (progress != null) Padding(padding: const EdgeInsets.only(top: 12), child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 6, backgroundColor: Colors.white24, color: Colors.white))),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => widget.onOpenClass(s['cls'] as Map<String, dynamic>), style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.arrow_forward, size: 18), label: const Text('Open class'))),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Approaching class', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      for (final s in ongoing) Padding(padding: const EdgeInsets.only(bottom: 10), child: hero(
          label: 'IN SESSION', s: s, big: 'Ends in ${_left(at(now, '${s['end_time']}').difference(now))}',
          progress: now.difference(at(now, '${s['start_time']}')).inSeconds / at(now, '${s['end_time']}').difference(at(now, '${s['start_time']}')).inSeconds)),
      if (upcoming.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.only(bottom: 10), child: () {
          final s = upcoming.first, left = at(now, '${s['start_time']}').difference(now);
          return hero(label: 'NEXT CLASS', s: s, big: 'Starts in ${_left(left)}', progress: 1 - left.inMinutes / 60);
        }()),
        if (upcoming.length > 1) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 4, 0, 6), child: Text('Later today', style: Theme.of(c).textTheme.titleSmall)),
          for (final s in upcoming.skip(1)) _slotTile(s),
        ],
      ],
      if (ongoing.isEmpty && upcoming.isEmpty) ...[
        if (later != null) hero(label: laterIn == 1 ? 'TOMORROW' : _dayShort[later['day_of_week'] as int].toUpperCase(), s: later, big: 'No more classes today')
        else Card(elevation: 0, color: Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: .5), child: const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Nothing coming up. Add a class to see it here.')))),
      ],
      const SizedBox(height: 12),
      Card(elevation: 0, color: Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: .5), child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 8, 10), child: Row(children: [
        const Icon(Icons.notifications_active_outlined), const SizedBox(width: 10),
        Expanded(child: Text(alert == 0 ? 'Phone reminders are off' : 'Phone reminder $alert min before class', style: const TextStyle(fontWeight: FontWeight.w500))),
        DropdownButton<int>(
          value: const [0, 5, 10, 15, 20, 30, 45, 60].contains(alert) ? alert : 10, underline: const SizedBox(),
          items: [for (final v in const [0, 5, 10, 15, 20, 30, 45, 60]) DropdownMenuItem(value: v, child: Text(v == 0 ? 'Off' : '$v min'))],
          onChanged: (v) { if (v != null) { _setAlert(v); } },
        ),
      ]))),
      const Padding(padding: EdgeInsets.fromLTRB(6, 4, 6, 0), child: Text('Reminders arrive as notifications on your Android phone.', style: TextStyle(fontSize: 11))),
    ]);
  }

  @override
  Widget build(BuildContext c) {
    final visible = TickerMode.of(c);                                  // false while another tab is on screen
    if (visible && !_wasVisible && me != null) { WidgetsBinding.instance.addPostFrameCallback((_) => _loadMe()); }
    _wasVisible = visible;
    return ListenableBuilder(listenable: TeacherData.i, builder: (c, _) {
      final slots = TeacherData.i.slots;
      return RefreshIndicator(
        onRefresh: () async { await Future.wait([TeacherData.i.reload(), _loadMe()]); },
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          _header(c),
          Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 0), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!TeacherData.i.loaded) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())) else ...[
              _scheduleSection(c, slots), const SizedBox(height: 24), _approaching(c, slots),
            ],
          ]))),
        ]),
      );
    });
  }
}
