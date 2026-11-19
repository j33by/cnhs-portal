import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/chat_data.dart';
import '../../core/img.dart';
import '../../core/messenger.dart';
import '../../core/offline.dart';
import '../../widgets/feed_view.dart';
import '../../widgets/ui.dart';

const _senderColors = [Color(0xFF1B5E3B), Color(0xFF3949AB), Color(0xFFB7791F), Color(0xFF00796B), Color(0xFF8E24AA), Color(0xFFC2185B), Color(0xFF455A64)];
Color _colorFor(String id) => _senderColors[id.codeUnits.fold<int>(0, (a, b) => a + b) % _senderColors.length];

String _dayLabel(DateTime t) {
  final now = DateTime.now(), d = DateTime(t.year, t.month, t.day), today = DateTime(now.year, now.month, now.day), diff = today.difference(d).inDays;
  if (diff == 0) { return 'Today'; }
  if (diff == 1) { return 'Yesterday'; }
  return DateFormat(t.year == now.year ? 'EEE, MMM d' : 'MMM d, y').format(t);
}
String _size(num b) => b >= 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : b >= 1024 ? '${(b / 1024).round()} KB' : '${b.round()} B';
IconData _fileIcon(String name) {
  final e = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (e == 'pdf') { return Icons.picture_as_pdf_outlined; }
  if (e == 'doc' || e == 'docx' || e == 'txt') { return Icons.description_outlined; }
  if (e == 'xls' || e == 'xlsx' || e == 'csv') { return Icons.table_chart_outlined; }
  if (e == 'ppt' || e == 'pptx') { return Icons.slideshow; }
  if (e == 'zip') { return Icons.folder_zip_outlined; }
  if (e == 'mp3' || e == 'm4a') { return Icons.audiotrack; }
  if (e == 'mp4') { return Icons.videocam_outlined; }
  return Icons.insert_drive_file_outlined;
}

class PersonAvatar extends StatelessWidget {
  final String? url; final String name; final double radius;
  const PersonAvatar({super.key, this.url, required this.name, this.radius = 20});
  @override
  Widget build(BuildContext c) => CircleAvatar(
        radius: radius, backgroundColor: Theme.of(c).colorScheme.primaryContainer,
        backgroundImage: url != null && url!.isNotEmpty ? CachedNetImage(url!) : null,
        child: url == null || url!.isEmpty ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontSize: radius * .8, fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.onPrimaryContainer)) : null,
      );
}

/// Full-screen private chat with one classmate.
class ChatScreen extends StatelessWidget {
  final String threadId, name; final String? photo;
  const ChatScreen({super.key, required this.threadId, required this.name, this.photo});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(titleSpacing: 0, title: Row(children: [
          PersonAvatar(url: photo, name: name, radius: 17), const SizedBox(width: 10),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        ])),
        body: ChatView(threadId: threadId, group: false),
      );
}

class _Pick { final String name; final List<int> bytes; final bool image; _Pick(this.name, this.bytes, this.image); }

/// The conversation itself: messages (live), reply, react, delete, photos and files. Used by the private chat and by the Group tab.
class ChatView extends StatefulWidget {
  final String threadId; final bool group;
  const ChatView({super.key, required this.threadId, required this.group});
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  int limit = 60;
  late Stream<JRows> _stream = ChatData.messages(widget.threadId, limit);
  final ctl = TextEditingController(), scroll = ScrollController();
  final pending = <_Pick>[];
  final _sent = <String, Map<String, dynamic>>{};      // my own messages, shown at once until the live feed brings them
  Map<String, dynamic>? replyTo;
  bool sending = false;
  String? _readMark;

  @override
  void initState() { super.initState(); ChatData.viewing = widget.threadId; WidgetsBinding.instance.addPostFrameCallback((_) => ChatData.markRead(widget.threadId)); }
  @override
  void dispose() { if (ChatData.viewing == widget.threadId) { ChatData.viewing = null; } ctl.dispose(); scroll.dispose(); super.dispose(); }

  // ---------- sending ----------
  Future<void> _send() async {
    final t = ctl.text.trim();
    if ((t.isEmpty && pending.isEmpty) || sending) { return; }
    if (!Net.i.online) { toast('You are offline. Connect to the internet to send.'); return; }
    setState(() => sending = true);
    try {
      var files = <Map<String, dynamic>>[];
      if (pending.isNotEmpty) {
        final m = <String, List<int>>{};
        for (var i = 0; i < pending.length; i++) { var n = pending[i].name; if (m.containsKey(n)) { n = '${i + 1}_$n'; } m[n] = pending[i].bytes; }
        files = await ChatData.upload(widget.threadId, m);
      }
      final msg = await ChatData.send(widget.threadId, text: t, files: files, replyTo: replyTo?['id'] as String?);
      _sent['${msg['id']}'] = msg;
      ctl.clear(); pending.clear(); replyTo = null;
      if (scroll.hasClients) { scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }
    } catch (e) { toastError(e); }
    if (mounted) { setState(() => sending = false); }
  }

  // ---------- attaching ----------
  void _attachSheet() {
    final mobile = Platform.isAndroid || Platform.isIOS;
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Photos'), onTap: () { Navigator.pop(c); _pickPhotos(ImageSource.gallery); }),
      if (mobile) ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () { Navigator.pop(c); _pickPhotos(ImageSource.camera); }),
      ListTile(leading: const Icon(Icons.attach_file), title: const Text('File'), subtitle: const Text('PDF, Word, Excel, PowerPoint, text, ZIP · up to 10 MB'), onTap: () { Navigator.pop(c); _pickFiles(); }),
    ])));
  }

  Future<void> _pickPhotos(ImageSource src) async {
    final room = 5 - pending.length; if (room <= 0) { toast('Up to 5 files per message'); return; }
    try {
      final picker = ImagePicker();
      final xs = src == ImageSource.camera ? [if (await picker.pickImage(source: src, maxWidth: 1600, imageQuality: 82) case final x?) x] : await picker.pickMultiImage(maxWidth: 1600, imageQuality: 82);
      for (final x in xs.take(room)) {
        var n = x.name.isEmpty ? 'photo.jpg' : x.name; if (!n.contains('.')) { n = '$n.jpg'; }
        pending.add(_Pick(n, await x.readAsBytes(), true));
      }
      if (mounted) { setState(() {}); }
    } catch (e) { toastError(e); }
  }

  Future<void> _pickFiles() async {
    final room = 5 - pending.length; if (room <= 0) { toast('Up to 5 files per message'); return; }
    try {
      final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'zip', 'mp3', 'm4a', 'mp4']);
      if (r == null) { return; }
      for (final f in r.files.take(room)) {
        if (f.path == null) { continue; }
        if (f.size > 10 * 1024 * 1024) { toast('"${f.name}" is bigger than 10 MB'); continue; }
        final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
        pending.add(_Pick(f.name, await File(f.path!).readAsBytes(), const ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)));
      }
      if (mounted) { setState(() {}); }
    } catch (e) { toastError(e); }
  }

  // ---------- message actions ----------
  Future<void> _actions(Map<String, dynamic> m) async {
    if (m['deleted'] == true) { return; }
    final mine = m['sender_id'] == myUid, body = '${m['body']}'.trim();
    final reacts = Map<String, dynamic>.from((m['reactions'] as Map?) ?? const {});
    final myReact = reacts.entries.where((e) => (e.value as List).contains(myUid)).map((e) => e.key).firstOrNull;
    final v = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final e in ChatData.reactions) InkWell(
          borderRadius: BorderRadius.circular(24), onTap: () => Navigator.pop(c, 'r:$e'),
          child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, color: myReact == e ? Theme.of(c).colorScheme.primaryContainer : null), child: Text(e, style: const TextStyle(fontSize: 26))),
        ),
      ])),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () => Navigator.pop(c, 'reply')),
      if (body.isNotEmpty) ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('Copy text'), onTap: () => Navigator.pop(c, 'copy')),
      if (mine) ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error), title: Text('Delete for everyone', style: TextStyle(color: Theme.of(c).colorScheme.error)), onTap: () => Navigator.pop(c, 'delete')),
    ])));
    if (v == null || !mounted) { return; }
    if (v.startsWith('r:')) { _react('${m['id']}', v.substring(2)); }
    else if (v == 'reply') { setState(() => replyTo = m); }
    else if (v == 'copy') { await Clipboard.setData(ClipboardData(text: body)); toast('Copied'); }
    else if (v == 'delete') {
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Delete this message?'), content: const Text('It is removed for everyone in this chat, together with its files.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
      if (ok == true) { try { await ChatData.delete('${m['id']}'); _sent.remove('${m['id']}'); } catch (e) { toastError(e); } }
    }
  }

  Future<void> _react(String id, String emoji) async { try { await ChatData.react(id, emoji); } catch (e) { toastError(e); } }

  Future<void> _open(String url) async {
    try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) { toast('Could not open the file'); }
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext c) => Column(children: [
        Expanded(child: StreamBuilder<JRows>(stream: _stream, builder: (c, s) {
          if (!s.hasData) { return const Center(child: CircularProgressIndicator()); }
          final byId = {for (final r in s.data!) '${r['id']}': r};
          for (final e in _sent.entries) { byId.putIfAbsent(e.key, () => e.value); }
          final msgs = byId.values.toList()..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));   // newest first
          if (msgs.isEmpty) { return EmptyState(icon: Icons.waving_hand_outlined, title: widget.group ? 'Start the class chat' : 'Say hi 👋', message: widget.group ? 'Everyone in your section can read and write here.' : 'Only you and your classmate can see this chat.'); }
          final newest = msgs.first;
          if (newest['sender_id'] != myUid && '${newest['id']}' != _readMark) { _readMark = '${newest['id']}'; WidgetsBinding.instance.addPostFrameCallback((_) => ChatData.markRead(widget.threadId)); }
          return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView.builder(
            controller: scroll, reverse: true, padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), itemCount: msgs.length + (s.data!.length >= limit ? 1 : 0),
            itemBuilder: (c, i) {
              if (i == msgs.length) {
                return Padding(padding: const EdgeInsets.all(8), child: Center(child: TextButton(onPressed: () => setState(() { limit += 60; _stream = ChatData.messages(widget.threadId, limit); }), child: const Text('Load earlier messages'))));
              }
              final m = msgs[i], older = i + 1 < msgs.length ? msgs[i + 1] : null, newer = i > 0 ? msgs[i - 1] : null;
              final t = DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now();
              bool near(Map<String, dynamic>? o) {
                if (o == null || o['sender_id'] != m['sender_id']) { return false; }
                final ot = DateTime.tryParse('${o['created_at']}')?.toLocal(); if (ot == null) { return false; }
                return ot.difference(t).abs().inMinutes < 5 && ot.day == t.day;
              }
              final newDay = older == null || (DateTime.tryParse('${older['created_at']}')?.toLocal().day ?? t.day) != t.day || (DateTime.tryParse('${older['created_at']}')?.toLocal().month ?? t.month) != t.month;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (newDay) _DayChip(_dayLabel(t)),
                _MessageRow(key: ValueKey('${m['id']}'), m: m, group: widget.group, firstInRun: !near(older) || newDay, lastInRun: !near(newer), time: t,
                    onActions: () => _actions(m), onReact: (e) => _react('${m['id']}', e), onOpen: _open),
              ]);
            },
          )));
        })),
        _composer(c),
      ]);

  Widget _composer(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Material(color: cs.surface, elevation: 6, child: SafeArea(top: false, child: Align(alignment: Alignment.bottomCenter, heightFactor: 1, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (replyTo != null) Container(
          margin: const EdgeInsets.fromLTRB(6, 2, 0, 6), padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: cs.primary, width: 3))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Replying to ${replyTo!['sender_id'] == myUid ? 'yourself' : replyTo!['sender_name']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
              Text(_snippetOf(replyTo!), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Theme.of(c).hintColor)),
            ])),
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => replyTo = null)),
          ]),
        ),
        if (pending.isNotEmpty) SizedBox(height: 70, child: ListView.separated(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(6, 0, 6, 8), itemCount: pending.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (c, i) {
            final p = pending[i];
            return Stack(clipBehavior: Clip.none, children: [
              Container(
                width: p.image ? 62 : 150, height: 62, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: p.image ? Image.memory(Uint8List.fromList(p.bytes), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined))
                    : Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [Icon(_fileIcon(p.name), color: cs.primary), const SizedBox(width: 6), Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))])),
              ),
              Positioned(top: -6, right: -6, child: InkWell(onTap: () => setState(() => pending.removeAt(i)), child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: cs.inverseSurface, shape: BoxShape.circle), child: Icon(Icons.close, size: 14, color: cs.onInverseSurface)))),
            ]);
          },
        )),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(tooltip: 'Attach', onPressed: sending ? null : _attachSheet, icon: Icon(Icons.add_circle_outline, color: cs.primary)),
          Expanded(child: TextField(
            controller: ctl, minLines: 1, maxLines: 5, maxLength: 2000, textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: 'Message', counterText: '', isDense: true, filled: true, fillColor: cs.surfaceContainerHighest, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)),
          )),
          const SizedBox(width: 6),
          IconButton.filled(onPressed: sending || (ctl.text.trim().isEmpty && pending.isEmpty) ? null : _send,
              icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 20)),
        ]),
      ]),
    )))));
  }
}

String _snippetOf(Map<String, dynamic> m) {
  final b = '${m['body']}'.trim(); if (b.isNotEmpty) { return b; }
  final a = (m['attachments'] as List?) ?? const [];
  if (a.isEmpty) { return ''; }
  final f = Map<String, dynamic>.from(a.first as Map);
  return '${f['type']}'.startsWith('image/') ? 'Photo' : 'File: ${f['name']}';
}

class _DayChip extends StatelessWidget {
  final String text;
  const _DayChip(this.text);
  @override
  Widget build(BuildContext c) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: Theme.of(c).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(c).hintColor)),
      )));
}

class _MessageRow extends StatelessWidget {
  final Map<String, dynamic> m; final bool group, firstInRun, lastInRun; final DateTime time;
  final VoidCallback onActions; final ValueChanged<String> onReact; final ValueChanged<String> onOpen;
  const _MessageRow({super.key, required this.m, required this.group, required this.firstInRun, required this.lastInRun, required this.time, required this.onActions, required this.onReact, required this.onOpen});

  bool get mine => m['sender_id'] == myUid;

  Widget _bubble(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    if (m['deleted'] == true) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(c).dividerColor)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block, size: 15, color: Theme.of(c).hintColor), const SizedBox(width: 6),
          Text('This message was deleted', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13.5, color: Theme.of(c).hintColor)),
        ]),
      );
    }
    final fg = mine ? cs.onPrimary : cs.onSurface, body = '${m['body']}'.trim();
    final atts = ((m['attachments'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final images = [for (final a in atts) if ('${a['type']}'.startsWith('image/')) '${a['url']}'];
    final files = [for (final a in atts) if (!'${a['type']}'.startsWith('image/')) a];
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine || !lastInRun ? 18 : 5), bottomRight: Radius.circular(!mine || !lastInRun ? 18 : 5));
    final imageOnly = images.isNotEmpty && files.isEmpty && body.isEmpty && m['reply_to'] == null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: imageOnly ? Colors.transparent : (mine ? cs.primary : cs.surfaceContainerHighest), borderRadius: radius),
      padding: imageOnly ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (m['reply_to'] != null || (m['reply_snippet'] ?? '').toString().isNotEmpty) Container(
          margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          decoration: BoxDecoration(color: fg.withValues(alpha: .12), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: fg.withValues(alpha: .7), width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m['reply_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
            Text('${m['reply_snippet'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: .85))),
          ]),
        ),
        if (images.isNotEmpty) Padding(padding: EdgeInsets.only(bottom: body.isNotEmpty || files.isNotEmpty ? 6 : 0), child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (var i = 0; i < images.length; i++) GestureDetector(
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ImageViewer(urls: images, start: i))),
            child: ClipRRect(borderRadius: BorderRadius.circular(imageOnly ? 14 : 10), child: SizedBox(
              width: images.length == 1 ? 220 : 108, height: images.length == 1 ? 220 : 108,
              child: Image(image: CachedNetImage(images[i]), fit: BoxFit.cover,
                  frameBuilder: (_, child, frame, sync) => frame == null && !sync ? Container(color: cs.surfaceContainerHigh) : child,
                  errorBuilder: (_, __, ___) => Container(color: cs.surfaceContainerHigh, child: const Icon(Icons.broken_image_outlined))),
            )),
          ),
        ])),
        for (final f in files) Padding(padding: const EdgeInsets.only(bottom: 6), child: InkWell(
          borderRadius: BorderRadius.circular(10), onTap: () => onOpen('${f['url']}'),
          child: Container(
            constraints: const BoxConstraints(minWidth: 190), padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: fg.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: fg.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)), child: Icon(_fileIcon('${f['name']}'), color: fg, size: 22)),
              const SizedBox(width: 10),
              Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${f['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
                if ((f['size'] ?? 0) is num && (f['size'] as num) > 0) Text(_size(f['size'] as num), style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: .8))),
              ])),
              const SizedBox(width: 6), Icon(Icons.download_outlined, size: 18, color: fg.withValues(alpha: .8)),
            ]),
          ),
        )),
        if (body.isNotEmpty) Text(body, style: TextStyle(fontSize: 15, height: 1.3, color: fg)),
      ]),
    );
  }

  Widget _reactions(BuildContext c) {
    final r = Map<String, dynamic>.from((m['reactions'] as Map?) ?? const {});
    if (r.isEmpty || m['deleted'] == true) { return const SizedBox.shrink(); }
    final cs = Theme.of(c).colorScheme;
    return Padding(padding: const EdgeInsets.only(top: 3), child: Wrap(spacing: 4, runSpacing: 4, children: [
      for (final e in r.entries) if ((e.value as List).isNotEmpty) InkWell(
        borderRadius: BorderRadius.circular(14), onTap: () => onReact(e.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: (e.value as List).contains(myUid) ? cs.primaryContainer : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: (e.value as List).contains(myUid) ? cs.primary : Theme.of(c).dividerColor.withValues(alpha: .6))),
          child: Text('${e.key}${(e.value as List).length > 1 ? ' ${(e.value as List).length}' : ''}', style: const TextStyle(fontSize: 13)),
        ),
      ),
    ]));
  }

  @override
  Widget build(BuildContext c) {
    final maxW = (MediaQuery.sizeOf(c).width * .78).clamp(0.0, 520.0), sender = '${m['sender_name']}';
    return Padding(
      padding: EdgeInsets.only(top: firstInRun ? 8 : 2),
      child: Row(mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (!mine && group) SizedBox(width: 34, child: lastInRun ? PersonAvatar(url: m['sender_photo'] as String?, name: sender, radius: 14) : null),
        Flexible(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          if (!mine && group && firstInRun) Padding(padding: const EdgeInsets.only(left: 4, bottom: 2), child: Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _colorFor('${m['sender_id']}')))),
          GestureDetector(onLongPress: onActions, onSecondaryTap: onActions, onDoubleTap: m['deleted'] == true ? null : () => onReact('👍'), child: _bubble(c)),
          _reactions(c),
          if (lastInRun) Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 0), child: Text(DateFormat('h:mm a').format(time), style: TextStyle(fontSize: 11, color: Theme.of(c).hintColor))),
        ]))),
      ]),
    );
  }
}
