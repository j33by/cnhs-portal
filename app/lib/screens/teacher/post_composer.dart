import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api.dart';
import '../../core/messenger.dart';
import '../../core/offline.dart';
import '../../core/teacher_data.dart';
import '../../widgets/feed_view.dart';
import '../../widgets/ui.dart';

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

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 8), child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)));

  Widget _thumb(Widget img, VoidCallback remove) => Padding(padding: const EdgeInsets.only(right: 8), child: Stack(children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 88, height: 88, child: img)),
        Positioned(top: 4, right: 4, child: GestureDetector(onTap: remove, child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
      ]));

  Widget _audience(BuildContext c) {
    if (editing) { return SoftCard(child: Row(children: [const Icon(Icons.visibility_outlined, size: 18), const SizedBox(width: 10), Expanded(child: Text('${widget.existing!['audience'] ?? ''}')), ])); }
    return ListenableBuilder(listenable: TeacherData.i, builder: (c, _) {
      final by = _sections(), grades = {...by.keys, ...extraGrades}.toList()..sort();
      if (by.isEmpty) { return const SoftCard(child: Text('Add a class first. You can only post to sections you teach or advise.')); }
      return SoftCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Whole grade level', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [for (final g in grades) FilterChip(label: Text('Grade $g'), selected: sel.contains('g|$g'), onSelected: (v) => setState(() { v ? sel.add('g|$g') : sel.remove('g|$g'); }))]),
        for (final g in by.keys.toList()..sort()) ...[
          const Divider(height: 22),
          Text('Grade $g', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final s in by[g]!) Padding(padding: const EdgeInsets.only(top: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 84, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)))),
            Expanded(child: Wrap(spacing: 6, runSpacing: 2, children: [
              FilterChip(visualDensity: VisualDensity.compact, label: const Text('Whole section'), selected: sel.contains('s|${s.id}'), onSelected: (v) => setState(() { v ? sel.add('s|${s.id}') : sel.remove('s|${s.id}'); })),
              for (final e in s.subjects.entries) FilterChip(visualDensity: VisualDensity.compact, label: Text(e.value), selected: sel.contains('sub|${s.id}|${e.key}'), onSelected: (v) => setState(() { v ? sel.add('sub|${s.id}|${e.key}') : sel.remove('sub|${s.id}|${e.key}'); })),
              if (s.adviser) FilterChip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.star_rounded, size: 16), label: const Text('Homeroom'), selected: sel.contains('h|${s.id}'), onSelected: (v) => setState(() { v ? sel.add('h|${s.id}') : sel.remove('h|${s.id}'); })),
            ])),
          ])),
        ],
        const SizedBox(height: 4),
      ]));
    });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: Text(editing ? 'Edit post' : 'New post'),
          actions: [Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: busy ? null : _submit, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(editing ? 'Save' : 'Post')))],
        ),
        body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          TextField(controller: text, minLines: 5, maxLines: 12, maxLength: 3000, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What do you want to share with your students?', border: InputBorder.none, counterText: ''), style: const TextStyle(fontSize: 16, height: 1.4)),
          SizedBox(height: 92, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < oldImages.length; i++) _thumb(CachedNetworkImage(imageUrl: oldImages[i], fit: BoxFit.cover), () => setState(() => oldImages.removeAt(i))),
            for (var i = 0; i < picked.length; i++) _thumb(Image.file(picked[i], fit: BoxFit.cover), () => setState(() => picked.removeAt(i))),
            if (!editing && picked.length + oldImages.length < 6) InkWell(borderRadius: BorderRadius.circular(12), onTap: _addPhotos, child: Container(width: 88, height: 88, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(c).dividerColor)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined, color: Theme.of(c).colorScheme.primary), const SizedBox(height: 4), const Text('Photos', style: TextStyle(fontSize: 12))]))),
          ])),
          _label('Type'),
          Wrap(spacing: 8, runSpacing: 4, children: [for (final k in const ['announcement', 'reminder', 'activity', 'assignment', 'urgent']) ChoiceChip(
            label: Text(catLabel(k)), selected: category == k, selectedColor: catColor(k).withValues(alpha: .18), onSelected: (_) => setState(() => category = k))]),
          _label('Visible to'),
          _audience(c),
          _label('Options'),
          SoftCard(padding: EdgeInsets.zero, child: Column(children: [
            SwitchListTile(title: const Text('Allow reactions'), value: allowReactions, onChanged: (v) => setState(() => allowReactions = v)),
            const Divider(height: 1),
            SwitchListTile(title: const Text('Allow comments'), subtitle: const Text('Students and parents can comment'), value: allowComments, onChanged: (v) => setState(() => allowComments = v)),
            const Divider(height: 1),
            SwitchListTile(title: const Text('Pin to the top'), value: pinned, onChanged: (v) => setState(() => pinned = v)),
            if (!editing) ...[const Divider(height: 1), SwitchListTile(title: const Text('Notify students and parents'), subtitle: const Text('Sends an alert to everyone who can see it'), value: notifyPeople, onChanged: (v) => setState(() => notifyPeople = v))],
          ])),
        ]))),
      );
}
