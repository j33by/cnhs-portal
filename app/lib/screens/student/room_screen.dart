import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/chat_data.dart';
import '../../core/api.dart';
import '../../core/offline.dart';
import '../../core/messenger.dart';
import '../../core/voice.dart';
import '../../widgets/ui.dart';
import 'chat_view.dart';
import 'messages_screen.dart';
import '../teacher/teacher_messages.dart';

/// "Room": the people of one section (adviser, subject teachers, classmates), voice messages and shortcuts to message anyone.
/// Students open their own section; teachers open the section they pick.
class RoomScreen extends StatefulWidget {
  /// Students: null (their own section). Teachers: the section whose room to open.
  final String? sectionId;
  const RoomScreen({super.key, this.sectionId});
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  Map<String, dynamic>? data; bool failed = false; String q = '';
  Timer? _tick; StreamSubscription<dynamic>? _live;
  bool get teacherView => widget.sectionId != null;

  @override
  void initState() {
    super.initState(); _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) { setState(() {}); } });      // refresh "expires in" and hide expired voices
    // people change in real time: students joining/leaving, teachers being assigned
    _live = ChatData.assignmentChanges().listen((_) => _load(), onError: (_) {});
  }
  @override
  void dispose() { _tick?.cancel(); _live?.cancel(); VoicePlayer.i.stop(quiet: true); super.dispose(); }
  Future<void> _load() async {
    try { final r = await ChatData.roster(sectionId: widget.sectionId, onFresh: (f) { if (mounted) { setState(() => data = f); } }); if (mounted) { setState(() { data = r; failed = false; }); } }
    catch (_) { if (mounted && data == null) { setState(() => failed = true); } }
  }

  Future<void> _message(Map<String, dynamic> p) async => once('open-chat', () async {
    try {
      final id = await ChatData.openPrivate('${p['id']}');
      if (!mounted) { return; }
      pushOnce(context, MaterialPageRoute(builder: (_) => ChatScreen(threadId: id, name: fullName(p), photo: p['photo_url'] as String?)));
    } catch (e) { toastError(e); }
  });

  Future<void> _group(String secId, String label) async => once('open-chat', () async {
    try {
      if (!teacherView) { pushOnce(context, MaterialPageRoute(builder: (_) => const MessagesScreen(initialTab: 1))); return; }
      final id = await ChatData.openStaff(secId);
      if (!mounted) { return; }
      pushOnce(context, MaterialPageRoute(builder: (_) => StaffGroupScreen(threadId: id, title: '$label · Teachers')));
    } catch (e) { toastError(e); }
  });

  @override
  Widget build(BuildContext c) {
    final d = data;
    return Scaffold(
      appBar: AppBar(title: Text(teacherView ? 'Room' : 'My Room')),
      body: d == null
          ? (failed ? EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load your room', message: 'Check your connection and try again.', action: FilledButton(onPressed: _load, child: const Text('Retry'))) : const Center(child: CircularProgressIndicator()))
          : d['section'] == null
              ? const EmptyState(icon: Icons.meeting_room_outlined, title: 'No room yet', message: 'Your room opens once you are added to a section.')
              : _body(c, d),
    );
  }

  Widget _body(BuildContext c, Map<String, dynamic> d) {
    final cs = Theme.of(c).colorScheme;
    final sec = d['section'] as Map, adviser = d['adviser'] == null ? null : Map<String, dynamic>.from(d['adviser'] as Map), secId = '${sec['id']}', label = 'Grade ${sec['grade_level']} · ${sec['name']}';
    final subs = [for (final t in (d['subject_teachers'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
    final mates = [for (final m in (d['classmates'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
    final teachers = [if (adviser != null) adviser, ...subs];
    final f = q.trim().toLowerCase();
    final shown = f.isEmpty ? mates : mates.where((m) => fullName(m).toLowerCase().contains(f)).toList();
    return StreamBuilder<JRows>(stream: VoiceData.stream(secId), builder: (c, vs) {
      final voices = {for (final v in (vs.data ?? const <Map<String, dynamic>>[]).where(VoiceData.alive)) '${v['user_id']}': v};
      final iAmAdviser = adviser != null && adviser['id'] == myUid;
      return RefreshIndicator(onRefresh: _load, child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          // ---- header
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary, Color.lerp(cs.primary, Colors.black, .3)!])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), shape: BoxShape.circle), child: const Icon(Icons.groups_rounded, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text('${mates.length} student${mates.length == 1 ? '' : 's'} · ${teachers.length} teacher${teachers.length == 1 ? '' : 's'}', style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13)),
                ])),
              ]),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(onPressed: () => _group(secId, label), icon: Icon(teacherView ? Icons.lock_outline : Icons.forum_outlined, size: 18), label: Text(teacherView ? 'Teachers chat' : 'Group chat')),
            ])),
          const SizedBox(height: 12),
          _VoiceComposer(sectionId: secId, mine: voices[myUid]),
          const SizedBox(height: 14),
          // ---- teachers (drop-down)
          _Collapsible(icon: Icons.school_outlined, title: 'Teachers', count: teachers.length, preview: [for (final t in teachers.take(4)) t],
            child: teachers.isEmpty ? Padding(padding: const EdgeInsets.all(16), child: Text('No teachers assigned yet.', style: TextStyle(color: Theme.of(c).hintColor)))
                : Column(children: [for (final t in teachers) _teacherRow(c, t, t['id'] == adviser?['id'] ? 'Adviser' : (t['subjects'] as List? ?? const []).join(' · '), voices, iAmAdviser, t['id'] == adviser?['id'])])),
          const SizedBox(height: 10),
          // ---- classmates / students (drop-down)
          _Collapsible(icon: Icons.people_outline, title: teacherView ? 'Students' : 'Classmates', count: mates.length, initiallyOpen: true, preview: const [],
            child: Column(children: [
              if (mates.length > 6) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: TextField(onChanged: (v) => setState(() => q = v),
                  decoration: InputDecoration(hintText: teacherView ? 'Search students' : 'Search classmates', prefixIcon: const Icon(Icons.search, size: 20), isDense: true, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
              if (shown.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(mates.isEmpty ? 'No students yet.' : 'No one matches "$q".', style: TextStyle(color: Theme.of(c).hintColor))),
              for (final m in shown) _mateRow(c, m, voices, iAmAdviser),
            ])),
        ],
      ))));
    });
  }

  Widget _teacherRow(BuildContext c, Map<String, dynamic> t, String sub, Map<String, Map<String, dynamic>> voices, bool mod, bool isAdviser) {
    final me = t['id'] == myUid, v = voices['${t['id']}'];
    return ListTile(
      dense: false, contentPadding: const EdgeInsets.symmetric(horizontal: 14), onTap: me ? null : () => _message(t),
      leading: PersonAvatar(url: t['photo_url'] as String?, name: fullName(t), radius: 20),
      title: Row(children: [Flexible(child: Text(fullName(t), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))), if (v != null) VoiceChip(key: ValueKey('v${v['id']}'), voice: v, canDelete: me || mod)]),
      subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
      trailing: me ? const Pill('You', Color(0xFF546E7A)) : Row(mainAxisSize: MainAxisSize.min, children: [
        if (isAdviser) const Padding(padding: EdgeInsets.only(right: 4), child: Pill('Adviser', Color(0xFF1B5E3B), icon: Icons.verified_outlined)),
        IconButton(tooltip: 'Message', icon: const Icon(Icons.chat_bubble_outline, size: 20), onPressed: () => _message(t)),
      ]),
    );
  }

  Widget _mateRow(BuildContext c, Map<String, dynamic> m, Map<String, Map<String, dynamic>> voices, bool mod) {
    final me = m['id'] == myUid, v = voices['${m['id']}'];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14), onTap: me ? null : () => _message(m),
      leading: PersonAvatar(url: m['photo_url'] as String?, name: fullName(m), radius: 20),
      title: Row(children: [Flexible(child: Text(fullName(m), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))), if (v != null) VoiceChip(key: ValueKey('v${v['id']}'), voice: v, canDelete: me || mod)]),
      trailing: me ? const Pill('You', Color(0xFF546E7A)) : IconButton(tooltip: 'Message', icon: const Icon(Icons.chat_bubble_outline, size: 20), onPressed: () => _message(m)),
    );
  }
}

/// A card with a header that expands / collapses its content (animated). The header can show a few small avatars as a preview while closed.
class _Collapsible extends StatefulWidget {
  final IconData icon; final String title; final int count; final Widget child; final bool initiallyOpen; final List<Map<String, dynamic>> preview;
  const _Collapsible({required this.icon, required this.title, required this.count, required this.child, this.initiallyOpen = false, this.preview = const []});
  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  late bool open = widget.initiallyOpen;
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(c).dividerColor.withValues(alpha: .5))),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(onTap: () => setState(() => open = !open), child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 10, 12), child: Row(children: [
          Icon(widget.icon, color: cs.primary), const SizedBox(width: 10),
          Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Text('${widget.count}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer))),
          const Spacer(),
          if (!open && widget.preview.isNotEmpty) SizedBox(height: 28, width: 18.0 * widget.preview.length + 12, child: Stack(children: [
            for (var i = 0; i < widget.preview.length; i++) Positioned(left: 18.0 * i, child: Container(padding: const EdgeInsets.all(1.5), decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                child: PersonAvatar(url: widget.preview[i]['photo_url'] as String?, name: fullName(widget.preview[i]), radius: 11))),
          ])),
          AnimatedRotation(turns: open ? .5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.keyboard_arrow_down_rounded)),
        ]))),
        AnimatedSize(duration: const Duration(milliseconds: 220), curve: Curves.easeInOut, alignment: Alignment.topCenter,
            child: open ? Column(children: [Divider(height: 1, color: Theme.of(c).dividerColor.withValues(alpha: .5)), widget.child, const SizedBox(height: 4)]) : const SizedBox(width: double.infinity)),
      ]),
    );
  }
}

const _green = Color(0xFF2E9E5B);

String _mmss(int ms) { final s = (ms / 1000).round(); return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'; }
String _left(Map<String, dynamic> v) {
  final e = DateTime.tryParse('${v['expires_at']}'); if (e == null) { return ''; }
  final m = e.difference(DateTime.now()).inMinutes; if (m <= 0) { return 'expiring'; }
  return m >= 60 ? 'expires in ${m ~/ 60}h ${m % 60}m' : 'expires in ${m}m';
}

/// The little volume icon beside a name. Tap = play, tap again = stop. A green pulse shows while it plays.
class VoiceChip extends StatefulWidget {
  final Map<String, dynamic> voice; final bool canDelete;
  const VoiceChip({super.key, required this.voice, this.canDelete = false});
  @override
  State<VoiceChip> createState() => _VoiceChipState();
}

class _VoiceChipState extends State<VoiceChip> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  String get id => '${widget.voice['id']}';
  void _sync() { if (!mounted) { return; } if (VoicePlayer.i.playing == id) { if (!_a.isAnimating) { _a.repeat(); } } else { _a.stop(); _a.value = 0; } setState(() {}); }
  @override
  void initState() { super.initState(); VoicePlayer.i.addListener(_sync); if (VoicePlayer.i.playing == id) { _a.repeat(); } }
  @override
  void dispose() { VoicePlayer.i.removeListener(_sync); if (VoicePlayer.i.playing == id) { VoicePlayer.i.stop(quiet: true); } _a.dispose(); super.dispose(); }

  Future<void> _tap() async { try { await VoicePlayer.i.toggle(id, '${widget.voice['audio_url']}'); } catch (e) { toast('Could not play this voice message.'); } }
  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Delete voice message?'), content: const Text('It will be removed for everyone in the room.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
    if (ok != true) { return; }
    try { if (VoicePlayer.i.playing == id) { await VoicePlayer.i.stop(); } await VoiceData.delete(id); } catch (e) { toastError(e); }
  }

  @override
  Widget build(BuildContext c) {
    final on = VoicePlayer.i.playing == id;
    return Padding(padding: const EdgeInsets.only(left: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(message: on ? 'Tap to stop' : 'Play voice message', child: InkResponse(onTap: _tap, radius: 22, child: SizedBox(width: 38, height: 38, child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(animation: _a, builder: (c, _) => on ? Container(width: 24 + 14 * _a.value, height: 24 + 14 * _a.value, decoration: BoxDecoration(shape: BoxShape.circle, color: _green.withValues(alpha: .38 * (1 - _a.value)))) : const SizedBox.shrink()),
        Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? _green : _green.withValues(alpha: .16)),
            child: Icon(on ? Icons.stop_rounded : Icons.volume_up_rounded, size: 16, color: on ? Colors.white : _green)),
      ])))),
      Text(_mmss((widget.voice['duration_ms'] as num?)?.toInt() ?? 0), style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
      if (widget.canDelete) InkResponse(onTap: _delete, radius: 18, child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.delete_outline, size: 18, color: Theme.of(c).hintColor))),
    ]));
  }
}

/// "Voice message" card: record up to 30 s and send it to the room. It lasts 12 hours. Posting again replaces the old one.
class _VoiceComposer extends StatefulWidget {
  final String sectionId; final Map<String, dynamic>? mine;
  const _VoiceComposer({required this.sectionId, required this.mine});
  @override
  State<_VoiceComposer> createState() => _VoiceComposerState();
}

enum _Rec { idle, recording, ready, sending }

class _VoiceComposerState extends State<_VoiceComposer> {
  final _rec = VoiceRecorder();
  _Rec st = _Rec.idle; Timer? _t; int ms = 0; ({List<int> bytes, int ms})? clip;
  @override
  void dispose() { _t?.cancel(); _rec.dispose(); super.dispose(); }

  Future<void> _start() async {
    try {
      if (!await _rec.start()) { toast('Allow the microphone to record a voice message.'); return; }
    } catch (e) { toast('Could not start recording.'); return; }
    setState(() { st = _Rec.recording; ms = 0; });
    _t = Timer.periodic(const Duration(milliseconds: 150), (_) { if (!mounted) { return; } setState(() => ms = _rec.elapsedMs); if (_rec.elapsedMs >= VoiceRecorder.maxMs) { _stop(); } });
  }
  Future<void> _stop() async {
    _t?.cancel();
    final r = await _rec.stop();
    if (!mounted) { return; }
    if (r == null || r.ms < 500) { setState(() => st = _Rec.idle); toast('That was too short.'); return; }
    setState(() { clip = r; st = _Rec.ready; });
  }
  Future<void> _cancel() async { _t?.cancel(); if (st == _Rec.recording) { await _rec.cancel(); } if (mounted) { setState(() { st = _Rec.idle; clip = null; }); } }
  Future<void> _send() async {
    final r = clip; if (r == null) { return; }
    setState(() => st = _Rec.sending);
    try { await VoiceData.post(widget.sectionId, r.bytes, r.ms, _rec.ext); if (mounted) { setState(() { st = _Rec.idle; clip = null; }); toast('Voice message sent. It stays for 12 hours.'); } }
    catch (e) { toastError(e); if (mounted) { setState(() => st = _Rec.ready); } }
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, mine = widget.mine;
    Widget body;
    switch (st) {
      case _Rec.recording:
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14), const SizedBox(width: 8),
            Text('Recording  ${_mmss(ms)} / 0:30', style: const TextStyle(fontWeight: FontWeight.w600)), const Spacer(),
            TextButton(onPressed: _cancel, child: const Text('Cancel')), const SizedBox(width: 4), FilledButton.icon(onPressed: _stop, icon: const Icon(Icons.stop_rounded, size: 18), label: const Text('Stop')),
          ]),
          const SizedBox(height: 8), ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: (ms / VoiceRecorder.maxMs).clamp(0, 1).toDouble(), minHeight: 6, color: _green)),
        ]);
      case _Rec.ready:
      case _Rec.sending:
        body = Row(children: [
          const Icon(Icons.mic, color: _green), const SizedBox(width: 8),
          Expanded(child: Text('Voice message ready · ${_mmss(clip?.ms ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w600))),
          TextButton(onPressed: st == _Rec.sending ? null : _cancel, child: const Text('Discard')), const SizedBox(width: 4),
          FilledButton.icon(onPressed: st == _Rec.sending ? null : _send, icon: st == _Rec.sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 18), label: const Text('Send')),
        ]);
      case _Rec.idle:
        body = Row(children: [
          CircleAvatar(radius: 20, backgroundColor: _green.withValues(alpha: .15), child: const Icon(Icons.mic_none_rounded, color: _green)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mine == null ? 'Voice message' : 'Your voice message is live', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(mine == null ? 'Up to 30 seconds. Everyone in this room can play it. It disappears after 12 hours.' : _left(mine), style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor)),
          ])),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(onPressed: _start, icon: const Icon(Icons.mic, size: 18), label: Text(mine == null ? 'Record' : 'Replace')),
        ]);
    }
    return AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: st == _Rec.recording ? _green : Theme.of(c).dividerColor.withValues(alpha: .5), width: st == _Rec.recording ? 1.5 : 1)),
        child: body);
  }
}
