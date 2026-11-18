import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// Everything the student, parent and teacher screens share. The widgets themselves live in their own files.
export 'status.dart';
export 'attendance_views.dart';
export 'grade_card.dart';
export 'notifications_view.dart';
export 'schedule_widgets.dart';

class ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> p; final String sub; const ProfileHeader(this.p, this.sub, {super.key});
  @override
  Widget build(BuildContext c) => ListTile(leading: CircleAvatar(backgroundImage: p['photo_url'] != null ? CachedNetworkImageProvider(p['photo_url']) : null, child: p['photo_url'] == null ? const Icon(Icons.person) : null), title: Text(p['full_name']), subtitle: Text(sub));
}
