import 'api.dart';

/// Unread notification count for the signed-in user (live).
Stream<int> unreadStream() => sb.from('notifications').stream(primaryKey: ['id']).eq('user_id', sb.auth.currentUser!.id)
    .map((rows) => rows.where((r) => r['read'] != true).length).asBroadcastStream();

/// Parent link requests waiting for a teacher (live).
Stream<int> pendingBindsStream() => sb.from('parent_links').stream(primaryKey: ['id']).eq('status', 'pending')
    .map((rows) => rows.length).asBroadcastStream();
