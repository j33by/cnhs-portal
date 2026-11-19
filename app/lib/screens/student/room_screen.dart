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

/// "Room": the people of my section — adviser, subject teachers and classmates (names only). Tap a classmate to message privately.
class RoomScreen extends StatefulWidget {
  /// Students: null (their own section). Teachers: the section whose room to open.
  final String? sectionId;
  const RoomScreen({super.key, this.sectionId});
  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  Map<String, dynamic>? data; bool failed = false; String q = '';
  Timer? _tick;
  bool get teacherView => widget.sectionId != null;

  @override
  void initState() { super.initState(); _load(); _tick = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) { setState(() {}); } }); }   // refresh "expires in" and hide expired voices
  @override
  void dispose() { _tick?.cancel(); VoicePlayer.i.stop(quiet: true); super.dispose(); }
  Future<void> _load() async {
    try { final r = await ChatData.roster(sectionId: widget.sectionId); if (mounted) { setState(() { data = r; failed = false; }); } }
    catch (_) { if (mounted && data == null) { setState(() => failed = true); } }
  }

  Future<void> _message(Map<String, dynamic> p) async {
    try {
      final id = await ChatData.openPrivate('${p['id']}');
      if (!mounted) { return; }
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(threadId: id, name: fullName(p), photo: p['photo_url'] as String?)));
    } catch (e) { toastError(e); }
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, d = data;
    return Scaffold(
      appBar: AppBar(title: Text(teacherView ? 'Room' : 'My Room')),
      body: d == null
          ? (failed ? EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load your room', message: 'Check your connection and try again.', action: FilledButton(onPressed: _load, child: const Text('Retry'))) : const Center(child: CircularProgressIndicator()))
          : d['section'] == null
              ? const EmptyState(icon: Icons.meeting_room_outlined, title: 'No room yet', message: 'Your room opens once you are added to a section.')
              : _body(c, d, cs),
    );
  }

  Widget _body(BuildContext c, Map<String, dynamic> d, ColorScheme cs) {
    final sec = d['section'] as Map, adviser = d['adviser'] as Map?, secId = '${sec['id']}';
    final subs = [for (final t in (d['subject_teachers'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
    final mates = [for (final m in (d['classmates'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
    final f = q.trim().toLowerCase();
    final shown = f.isEmpty ? mates : mates.where((m) => fullName(m).toLowerCase().contains(f)).toList();
    return StreamBuilder<JRows>(stream: VoiceData.stream(secId), builder: (c, vs) {
    final voices = {for (final v in (vs.data ?? const <Map<String, dynamic>>[]).where(VoiceData.alive)) '${v['user_id']}': v};
    final iAmAdviser = adviser != null && adviser['id'] == myUid;
    return RefreshIndicator(onRefresh: _load, child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(20)), child: Row(children: [
          CircleAvatar(radius: 24, backgroundColor: cs.primary, child: Icon(Icons.groups, color: cs.onPrimary)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Grade ${sec['grade_level']} · ${sec['name']}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
            Text('${mates.length} classmate${mates.length == 1 ? '' : 's'}', style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: .75))),
          ])),
          if (!teacherView) FilledButton.tonalIcon(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MessagesScreen(initialTab: 1))), icon: const Icon(Icons.forum_outlined, size: 18), label: const Text('Group chat')),
        ])),
        const SizedBox(height: 12),
        _VoiceComposer(sectionId: secId, mine: voices[myUid]),
        const SizedBox(height: 20),
        const SectionTitle('Teachers', icon: Icons.school_outlined),
        if (adviser == null && subs.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No teachers assigned yet.')),
        if (adviser != null) _teacher(c, Map<String, dynamic>.from(adviser), 'Adviser', voices, iAmAdviser, highlight: true),
        for (final t in subs) _teacher(c, t, (t['subjects'] as List? ?? const []).join(' · '), voices, iAmAdviser),
        const SizedBox(height: 20),
        SectionTitle(teacherView ? 'Students' : 'Classmates', icon: Icons.people_outline),
        TextField(onChanged: (v) => setState(() => q = v), decoration: InputDecoration(hintText: teacherView ? 'Search students' : 'Search classmates', prefixIcon: const Icon(Icons.search), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
        const SizedBox(height: 8),
        if (shown.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(mates.isEmpty ? 'No classmates yet.' : 'No one matches "$q".', style: TextStyle(color: Theme.of(c).hintColor)))),
        for (final m in shown) _mate(c, m, voices, iAmAdviser),
      ],
    ))));
    });
  }

  Widget _teacher(BuildContext c, Map<String, dynamic> t, String sub, Map<String, Map<String, dynamic>> voices, bool mod, {bool highlight = false}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: SoftCard(child: Row(children: [
        PersonAvatar(url: t['photo_url'] as String?, name: fullName(t), radius: 22), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Flexible(child: Text(fullName(t), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))), if (voices['${t['id']}'] != null) VoiceChip(key: ValueKey('v${voices['${t['id']}']!['id']}'), voice: voices['${t['id']}']!, canDelete: t['id'] == myUid || mod)]),
          if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor)),
        ])),
        if (t['id'] == myUid) const Pill('You', Color(0xFF546E7A)) else if (highlight) const Pill('Adviser', Color(0xFF1B5E3B), icon: Icons.verified_outlined),
      ])));

  Widget _mate(BuildContext c, Map<String, dynamic> m, Map<String, Map<String, dynamic>> voices, bool mod) {
    final me = m['id'] == myUid, v = voices['${m['id']}'];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4), onTap: me || teacherView ? null : () => _message(m),
      leading: PersonAvatar(url: m['photo_url'] as String?, name: fullName(m), radius: 20),
      title: Row(children: [Flexible(child: Text(fullName(m), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))), if (v != null) VoiceChip(key: ValueKey('v${v['id']}'), voice: v, canDelete: me || mod)]),
      trailing: me ? const Pill('You', Color(0xFF546E7A)) : teacherView ? null : IconButton(tooltip: 'Message', icon: const Icon(Icons.chat_bubble_outline), onPressed: () => _message(m)),
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
