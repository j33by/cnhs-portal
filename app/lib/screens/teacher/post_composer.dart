import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../core/offline.dart';
import '../../core/teacher_data.dart';
import '../../widgets/feed_view.dart';

/// Write a post (or edit one): text, photos, category, who can see it, and whether people may react or comment.
class PostComposer extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const PostComposer({super.key, this.existing});
  @override
  State<PostComposer> createState() => _PostComposerState();
}

class _Sec { final String id; final int grade; final String name; final subjects = <String, String>{}; bool adviser = false; _Sec(this.id, this.grade, this.name); }

class _PostComposerState extends State<PostComposer> {
  final text = TextEditingController();
  String category = 'announcement';
  bool allowReactions = true, allowComments = true, notifyPeople = true, pinned = false, busy = false;
  final picked = <File>[];
  List<String> oldImages = [];
  final sel = <String>{};                     // g|7   s|<section>   sub|<section>|<subject>   h|<section>
  final extraGrades = <int>{};
  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      text.text = '${e['body']}'; category = '${e['category']}'; allowReactions = e['allow_reactions'] == true; allowComments = e['allow_comments'] == true; pinned = e['pinned'] == true;
      oldImages = ((e['images'] as List?) ?? const []).cast<String>().toList();
    } else { _loadGrades(); }
  }
  @override
  void dispose() { text.dispose(); super.dispose(); }

  Future<void> _loadGrades() async {
    try {
      final t = await cachedRow('teacher-grades', () => sb.from('teachers').select('grade_levels').eq('id', myUid).maybeSingle());
      if (mounted && t?['grade_levels'] is List) { setState(() => extraGrades.addAll([for (final g in t!['grade_levels'] as List) (g as num).toInt()])); }
    } catch (_) {}
  }

  Future<void> _addPhotos() async {
    final room = 6 - picked.length - oldImages.length; if (room <= 0) { toast('Up to 6 photos per post'); return; }
    try {
      final xs = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 82);
      if (xs.isNotEmpty) { setState(() => picked.addAll(xs.take(room).map((x) => File(x.path)))); }
    } catch (e) { toastError(e); }
  }

  Map<int, List<_Sec>> _sections() {
    final m = <String, _Sec>{};
    for (final a in TeacherData.i.advisories) { (m[a['section_id'] as String] ??= _Sec(a['section_id'] as String, a['grade'] as int, '${a['section']}')).adviser = true; }
    for (final c in TeacherData.i.classes) { (m[c['section_id'] as String] ??= _Sec(c['section_id'] as String, c['grade'] as int, '${c['section']}')).subjects['${c['subject_id']}'] = '${c['subject']}'; }
    final by = <int, List<_Sec>>{};
    for (final s in m.values) { (by[s.grade] ??= []).add(s); }
    for (final l in by.values) { l.sort((a, b) => a.name.compareTo(b.name)); }
    return by;
  }

  List<Map<String, dynamic>> _targets() {
    final out = <Map<String, dynamic>>[];
    for (final t in sel) {
      final p = t.split('|');
      if (p[0] == 'g') { out.add({'kind': 'grade', 'grade_level': int.parse(p[1])}); }
      else if (p[0] == 's') { out.add({'kind': 'section', 'section_id': p[1]}); }
      else if (p[0] == 'sub') { out.add({'kind': 'subject', 'section_id': p[1], 'subject_id': p[2]}); }
      else if (p[0] == 'h') { out.add({'kind': 'homeroom', 'section_id': p[1]}); }
    }
    return out;
  }

  Future<void> _submit() async {
    final t = text.text.trim();
    if (t.isEmpty && picked.isEmpty && oldImages.isEmpty) { toast('Write something or add a photo'); return; }
    if (!editing && sel.isEmpty) { toast('Choose who can see this post'); return; }
    setState(() => busy = true);
    try {
      if (editing) {
        await Api.patch('/api/posts/${widget.existing!['id']}', {'text': t, 'category': category, 'allow_reactions': allowReactions, 'allow_comments': allowComments, 'pinned': pinned, 'images': oldImages});
        toast('Post updated');
      } else {
        final urls = <String>[];
        for (var i = 0; i < picked.length; i++) {
          final path = '$myUid/post_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          await sb.storage.from('pictures').upload(path, picked[i]);
          urls.add(sb.storage.from('pictures').getPublicUrl(path));
        }
        final r = await Api.post('/api/posts', {'text': t, 'category': category, 'images': urls, 'allow_reactions': allowReactions, 'allow_comments': allowComments, 'notify': notifyPeople, 'pinned': pinned, 'targets': _targets()});
        toast('Posted to ${r['sections']} section${r['sections'] == 1 ? '' : 's'}${notifyPeople ? ' · ${r['notified']} people notified' : ''}');
      }
      if (mounted) { Navigator.pop(context); }
    } catch (e) { toastError(e); }
    if (mounted) { setState(() => busy = false); }
  }

  // ---- audience: one short pill on the screen, the full picker in a sheet
  String _audienceText() {
    if (editing) { return '${widget.existing!['audience'] ?? ''}'; }
    if (sel.isEmpty) { return 'Choose audience'; }
    final by = _sections(), parts = <String>[];
    for (final t in sel) {
      final p = t.split('|');
      if (p[0] == 'g') { parts.add('Grade ${p[1]}'); continue; }
      final s = by.values.expand((l) => l).firstWhere((x) => x.id == p[1], orElse: () => _Sec('', 0, '?'));
      parts.add(p[0] == 'sub' ? '${s.name} · ${s.subjects[p[2]] ?? ''}' : p[0] == 'h' ? '${s.name} homeroom' : s.name);
    }
    return parts.length > 2 ? '${parts.take(2).join(', ')} +${parts.length - 2}' : parts.join(', ');
  }

  void _pickAudience() {
    if (editing) { return; }
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => StatefulBuilder(builder: (c, set) {
      void toggle(String k, bool v) { set(() {}); setState(() { v ? sel.add(k) : sel.remove(k); }); }
      return ListenableBuilder(listenable: TeacherData.i, builder: (c, _) {
        final by = _sections(), grades = {...by.keys, ...extraGrades}.toList()..sort();
        return SafeArea(child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .8), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Row(children: [Expanded(child: Text('Who can see this', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))), TextButton(onPressed: sel.isEmpty ? null : () { set(() {}); setState(sel.clear); }, child: const Text('Clear'))])),
          Flexible(child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), shrinkWrap: true, children: [
            if (by.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Add a class first.')),
            if (grades.isNotEmpty) ...[
              Text('Grade level', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)), const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [for (final g in grades) FilterChip(label: Text('Grade $g'), selected: sel.contains('g|$g'), onSelected: (v) => toggle('g|$g', v))]),
            ],
            for (final g in by.keys.toList()..sort()) ...[
              const SizedBox(height: 16), Text('Grade $g', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
              for (final s in by[g]!) Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 78, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)))),
                Expanded(child: Wrap(spacing: 6, runSpacing: 2, children: [
                  FilterChip(visualDensity: VisualDensity.compact, label: const Text('All'), selected: sel.contains('s|${s.id}'), onSelected: (v) => toggle('s|${s.id}', v)),
                  for (final e in s.subjects.entries) FilterChip(visualDensity: VisualDensity.compact, label: Text(e.value), selected: sel.contains('sub|${s.id}|${e.key}'), onSelected: (v) => toggle('sub|${s.id}|${e.key}', v)),
                  if (s.adviser) FilterChip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.star_rounded, size: 16), label: const Text('Homeroom'), selected: sel.contains('h|${s.id}'), onSelected: (v) => toggle('h|${s.id}', v)),
                ])),
              ])),
            ],
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: FilledButton(onPressed: () => Navigator.pop(c), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: Text(sel.isEmpty ? 'Done' : 'Done · ${sel.length} selected'))),
        ])));
      });
    }));
  }

  void _options() => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => StatefulBuilder(builder: (c, set) {
        Widget sw(String t, bool v, ValueChanged<bool> f) => SwitchListTile(title: Text(t), value: v, onChanged: (x) { set(() {}); setState(() => f(x)); });
        return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          sw('Reactions', allowReactions, (x) => allowReactions = x),
          sw('Comments', allowComments, (x) => allowComments = x),
          sw('Pin to top', pinned, (x) => pinned = x),
          if (!editing) sw('Notify students and parents', notifyPeople, (x) => notifyPeople = x),
          const SizedBox(height: 8),
        ]));
      }));

  Widget _thumb(Widget img, VoidCallback remove) => Padding(padding: const EdgeInsets.only(right: 8), child: Stack(children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 84, height: 84, child: img)),
        Positioned(top: 4, right: 4, child: GestureDetector(onTap: remove, child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
      ]));

  bool get _customOptions => !allowReactions || !allowComments || pinned || (!editing && !notifyPeople);

  @override
  Widget build(BuildContext c) {
    final col = catColor(category);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), title: Text(editing ? 'Edit post' : 'New post'),
        actions: [Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: busy ? null : _submit, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(editing ? 'Save' : 'Post')))],
      ),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: Row(children: [
          const CircleAvatar(radius: 20, child: Icon(Icons.person)), const SizedBox(width: 10),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: ActionChip(
            avatar: Icon(Icons.group_outlined, size: 18, color: sel.isEmpty && !editing ? Theme.of(c).colorScheme.error : null), label: Text(_audienceText(), overflow: TextOverflow.ellipsis),
            onPressed: editing ? null : _pickAudience, side: BorderSide(color: sel.isEmpty && !editing ? Theme.of(c).colorScheme.error : Theme.of(c).dividerColor)))),
        ])),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: text, minLines: 6, maxLines: null, maxLength: 3000, autofocus: !editing, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Write something…', border: InputBorder.none, counterText: ''), style: const TextStyle(fontSize: 17, height: 1.4)),
          if (picked.isNotEmpty || oldImages.isNotEmpty) SizedBox(height: 90, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < oldImages.length; i++) _thumb(CachedNetworkImage(imageUrl: oldImages[i], fit: BoxFit.cover), () => setState(() => oldImages.removeAt(i))),
            for (var i = 0; i < picked.length; i++) _thumb(Image.file(picked[i], fit: BoxFit.cover), () => setState(() => picked.removeAt(i))),
          ])),
        ]))),
        const Divider(height: 1),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 4), child: Row(children: [
          IconButton(tooltip: 'Photos', onPressed: editing ? null : _addPhotos, icon: Icon(Icons.image_outlined, color: editing ? null : Theme.of(c).colorScheme.primary)),
          PopupMenuButton<String>(
            tooltip: 'Type', onSelected: (k) => setState(() => category = k),
            itemBuilder: (_) => [for (final k in const ['announcement', 'reminder', 'activity', 'assignment', 'urgent']) PopupMenuItem(value: k, child: Row(children: [Icon(Icons.circle, size: 10, color: catColor(k)), const SizedBox(width: 10), Text(catLabel(k))]))],
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: col.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 9, color: col), const SizedBox(width: 7), Text(catLabel(category), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: col)), Icon(Icons.arrow_drop_down, size: 18, color: col)])),
          ),
          const Spacer(),
          IconButton(tooltip: 'Options', onPressed: _options, icon: Badge(isLabelVisible: _customOptions, smallSize: 8, child: const Icon(Icons.tune))),
        ]))),
      ]))),
    );
  }
}
