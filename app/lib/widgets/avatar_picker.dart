import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api.dart';

/// Uploads to Supabase Storage bucket "avatars" under <userId>/profile.jpg and returns the public URL.
class AvatarPicker extends StatefulWidget {
  final String? url; final ValueChanged<String> onUploaded;
  const AvatarPicker({super.key, this.url, required this.onUploaded});
  @override State<AvatarPicker> createState() => _S();
}
class _S extends State<AvatarPicker> {
  String? url; bool busy = false;
  @override void initState() { super.initState(); url = widget.url; }
  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    final File? f = x == null ? null : File(x.path);
    if (f == null) return; setState(() => busy = true);
    try {
      final path = '${sb.auth.currentUser!.id}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await sb.storage.from('avatars').upload(path, f);
      final u = sb.storage.from('avatars').getPublicUrl(path);
      setState(() => url = u); widget.onUploaded(u);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'))); }
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext c) => GestureDetector(onTap: _pick, child: Stack(alignment: Alignment.bottomRight, children: [
        CircleAvatar(radius: 48, backgroundImage: url != null ? CachedNetworkImageProvider(url!) : null, child: url == null ? const Icon(Icons.person, size: 48) : null),
        busy ? const CircularProgressIndicator() : const CircleAvatar(radius: 14, child: Icon(Icons.camera_alt, size: 16)),
      ]));
}
