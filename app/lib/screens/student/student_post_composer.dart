import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../core/api.dart';
import '../../core/img.dart';
import '../../core/messenger.dart';
import '../../core/offline.dart';
import '../../widgets/ui.dart';

/// A student post for the Section feed. Only the students of the section and the section's adviser can see it.
class StudentPostComposer extends StatefulWidget {
  final Map<String, dynamic>? existing; final String? photo, name;
  const StudentPostComposer({super.key, this.existing, this.photo, this.name});
  @override
  State<StudentPostComposer> createState() => _StudentPostComposerState();
}

class _StudentPostComposerState extends State<StudentPostComposer> {
  late final TextEditingController text = TextEditingController(text: widget.existing == null ? '' : '${widget.existing!['body']}');
  late final List<String> oldImages = [...((widget.existing?['images'] as List?)?.cast<String>() ?? const <String>[])];
  final picked = <Uint8List>[];
  bool busy = false;
  bool get editing => widget.existing != null;
  int get photoCount => oldImages.length + picked.length;

  @override
  void dispose() { text.dispose(); super.dispose(); }

  Future<void> _addPhotos() async {
    final room = 4 - photoCount; if (room <= 0) { toast('Up to 4 photos'); return; }
    try {
      final xs = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 82);
      for (final x in xs.take(room)) { picked.add(await x.readAsBytes()); }
      if (mounted) { setState(() {}); }
    } catch (e) { toastError(e); }
  }

  Future<void> _submit() async {
    final t = text.text.trim();
    if (t.isEmpty && photoCount == 0) { toast('Write something or add a photo'); return; }
    if (!Net.i.online) { toast('You are offline. Connect to the internet to post.'); return; }
    setState(() => busy = true);
    try {
      if (editing) {
        await Api.patch('/api/posts/${widget.existing!['id']}', {'text': t, 'images': oldImages});
        toast('Post updated');
      } else {
        final urls = <String>[];
        for (var i = 0; i < picked.length; i++) {
          final path = '$myUid/post_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          await sb.storage.from('pictures').uploadBinary(path, picked[i], fileOptions: const FileOptions(contentType: 'image/jpeg'));
          urls.add(sb.storage.from('pictures').getPublicUrl(path));
        }
        await Api.post('/api/section-posts', {'text': t, 'images': urls});
        toast('Posted to your section');
      }
      if (mounted) { Navigator.pop(context); }
    } catch (e) { toastError(e); }
    if (mounted) { setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, name = widget.name ?? '${widget.existing?['author_name'] ?? ''}', photo = widget.photo ?? widget.existing?['author_photo'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit post' : 'Post to my section'),
        actions: [Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: busy ? null : _submit,
            child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(editing ? 'Save' : 'Post')))],
      ),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundImage: photo != null && photo.isNotEmpty ? CachedNetImage(photo) : null, child: photo == null || photo.isEmpty ? Text(name.isEmpty ? '?' : name[0].toUpperCase()) : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 3),
            const Pill('Section only', Color(0xFF00796B), icon: Icons.lock_outline),
          ])),
        ]),
        const SizedBox(height: 10),
        Text('Only your classmates and your adviser can see this post.', style: TextStyle(fontSize: 12.5, color: Theme.of(c).hintColor)),
        const SizedBox(height: 10),
        TextField(controller: text, autofocus: !editing, minLines: 5, maxLines: 14, maxLength: 2000, textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Share something with your section…', border: InputBorder.none, counterText: '')),
        if (photoCount > 0) Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < oldImages.length; i++) _thumb(c, Image(image: CachedNetImage(oldImages[i]), fit: BoxFit.cover), () => setState(() => oldImages.removeAt(i))),
          for (var i = 0; i < picked.length; i++) _thumb(c, Image.memory(picked[i], fit: BoxFit.cover), () => setState(() => picked.removeAt(i))),
        ]),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: busy || photoCount >= 4 ? null : _addPhotos, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(photoCount == 0 ? 'Add photos' : 'Add more ($photoCount/4)'))),
        const SizedBox(height: 6),
        Text('Classmates and your adviser can like and comment.', style: TextStyle(fontSize: 12, color: cs.outline)),
      ]))),
    );
  }

  Widget _thumb(BuildContext c, Widget img, VoidCallback remove) => Stack(clipBehavior: Clip.none, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 104, height: 104, child: img)),
        Positioned(top: -6, right: -6, child: InkWell(onTap: remove, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: Theme.of(c).colorScheme.inverseSurface, shape: BoxShape.circle),
            child: Icon(Icons.close, size: 15, color: Theme.of(c).colorScheme.onInverseSurface)))),
      ]);
}
