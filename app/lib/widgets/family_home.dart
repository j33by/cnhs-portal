import 'dart:async';
import 'package:flutter/material.dart';
import 'attendance_views.dart';
import 'schedule_widgets.dart';
import 'ui.dart';

/// Home tab for a student (and for a parent looking at one child): photo, name and ID,
/// then the weekly schedule, attendance and the approaching class, like the teacher Home.
class FamilyHome extends StatefulWidget {
  final String studentId, name; final String? studentNo, photo, sectionId, classLabel;
  final bool parent; final void Function(String tabId) onGo; final Future<String?> Function()? loadPhoto; final List<Widget> extra;
  const FamilyHome({super.key, required this.studentId, required this.name, required this.onGo, this.studentNo, this.photo, this.sectionId, this.classLabel, this.parent = false, this.loadPhoto, this.extra = const []});
  @override
  State<FamilyHome> createState() => _FamilyHomeState();
}

class _FamilyHomeState extends State<FamilyHome> {
  Timer? _tick;
  String? _photo;
  bool _wasVisible = false;

  @override
  void initState() {
    super.initState();
    _refreshPhoto();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) { setState(() {}); } });   // live countdown
  }
  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  Future<void> _refreshPhoto() async {
    final f = widget.loadPhoto; if (f == null) { return; }
    try { final p = await f(); if (mounted && p != _photo) { setState(() => _photo = p); } } catch (_) {}
  }

  String _greeting() { final h = DateTime.now().hour; return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'; }

  @override
  Widget build(BuildContext c) {
    final visible = TickerMode.of(c);                                  // false while another tab is on screen
    if (visible && !_wasVisible) { WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPhoto()); }
    _wasVisible = visible;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      HeroHeader(
        greeting: widget.parent ? 'Viewing your child' : '${_greeting()}!', name: widget.name, photo: _photo ?? widget.photo,
        idLabel: 'Student ID', idValue: widget.studentNo, subtitle: widget.classLabel ?? (widget.parent ? 'Not in a section yet' : 'Waiting for your adviser to add you to a section'),
      ),
      Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 0), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...widget.extra,
        SectionFeed(sectionId: widget.sectionId, studentId: widget.studentId, builder: (c, slots, loaded) {
          if (!loaded) { return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())); }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.sectionId == null) SoftCard(child: Row(children: [
              Icon(Icons.hourglass_top, color: Theme.of(c).colorScheme.primary), const SizedBox(width: 12),
              const Expanded(child: Text('Your schedule appears once you are added to a section.')),
            ]))
            else ScheduleSection(slots: slots, title: widget.parent ? "Child's schedule" : 'My schedule'),
            const SizedBox(height: 24),
            const SectionTitle('Attendance', icon: Icons.how_to_reg),
            TodayAttendanceCard(studentId: widget.studentId, sectionId: widget.sectionId, name: widget.name.split(' ').first, onSeeAll: () => widget.onGo('attendance')),
            if (widget.sectionId != null) ...[const SizedBox(height: 24), ApproachingClass(slots: slots)],
          ]);
        }),
      ])))),
    ]);
  }
}
