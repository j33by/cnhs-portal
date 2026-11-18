import 'api.dart';
import 'offline.dart';

/// Unread notification count for the signed-in user (live).
Stream<int> unreadStream() => liveStream('notifications|user_id=${myUid}', () => sb.from('notifications').stream(primaryKey: ['id']).eq('user_id', myUid))
    .map((rows) => rows.where((r) => r['read'] != true).length).asBroadcastStream();

/// Parent link requests waiting for a teacher (live).
Stream<int> pendingBindsStream() => liveStream('parent_links|status=pending', () => sb.from('parent_links').stream(primaryKey: ['id']).eq('status', 'pending'))
    .map((rows) => rows.length).asBroadcastStream();
