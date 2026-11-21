import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart';
import 'offline.dart';

/// Everything the student Room / Messages screens need from the server.
/// Reading is live straight from Supabase (rows are protected by row-level security: only the students of the section can read);
/// everything that writes goes through the API.
class ChatData {
  /// The chat that is open on screen right now (no pop-up alert for it).
  static String? viewing;
  static const reactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  /// Classmates (names), adviser and subject teachers of my section. Shows the last saved answer while offline.
  static Future<Map<String, dynamic>> roster({String? sectionId, void Function(Map<String, dynamic>)? onFresh}) async {
    final r = await cachedRow('room_roster|${sectionId ?? 'mine'}', () async {
      final v = await sb.rpc('room_roster', params: sectionId == null ? null : {'p_section': sectionId});
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    }, fast: true, onFresh: onFresh);         // saved copy at once, replaced by the live one when it arrives
    return r ?? <String, dynamic>{};
  }

  /// Live list of chats I can open (the section group chat + my private chats).
  static Stream<JRows> threads() => liveStream('chat_threads|all', () => sb.from('chat_threads').stream(primaryKey: ['id']));
  /// When I last read each chat (drives the unread dots).
  static Stream<JRows> reads() => liveStream('chat_reads|user_id=$myUid', () => sb.from('chat_reads').stream(primaryKey: ['thread_id', 'user_id']).eq('user_id', myUid));
  static Stream<JRows> messages(String threadId, int limit) => liveStream('chat_messages|thread=$threadId|$limit',
      () => sb.from('chat_messages').stream(primaryKey: ['id']).eq('thread_id', threadId).order('created_at', ascending: false).limit(limit));

  /// Is this chat unread for me?
  static bool isUnread(Map<String, dynamic> thread, Map<String, DateTime> readAt) {
    if ('${thread['last_preview'] ?? ''}'.isEmpty || thread['last_sender_id'] == myUid) { return false; }
    final last = DateTime.tryParse('${thread['last_message_at']}'); if (last == null) { return false; }
    final read = readAt['${thread['id']}'];
    return read == null || last.isAfter(read);
  }
  static Map<String, DateTime> readMap(JRows rows) => {
        for (final r in rows) if (DateTime.tryParse('${r['last_read_at']}') != null) '${r['thread_id']}': DateTime.parse('${r['last_read_at']}'),
      };

  /// Teachers: colleagues who share a section with me + my sections (each section has a teachers-only group chat).
  static Future<Map<String, dynamic>> directory({void Function(Map<String, dynamic>)? onFresh}) async {
    final r = await cachedRow('staff_directory', () async { final v = await sb.rpc('staff_directory'); return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}; }, fast: true, onFresh: onFresh);
    return r ?? <String, dynamic>{};
  }
  /// Fires when teaching assignments change, so the teacher lists refresh by themselves.
  static Stream<JRows> assignmentChanges() => liveStream('section_subjects|all', () => sb.from('section_subjects').stream(primaryKey: ['section_id', 'subject_id']));
  static Future<String> openStaff(String sectionId) async => '${(await Api.post('/api/chat/staff', {'section_id': sectionId}))['id']}';

  static Future<String> openGroup() async => '${(await Api.post('/api/chat/group'))['id']}';
  static Future<String> openPrivate(String userId) async => '${(await Api.post('/api/chat/private', {'user_id': userId}))['id']}';
  static Future<void> markRead(String threadId) async { try { await Api.post('/api/chat/$threadId/read'); } catch (_) {} }

  static Future<Map<String, dynamic>> send(String threadId, {String text = '', List<Map<String, dynamic>> files = const [], String? replyTo}) async =>
      Map<String, dynamic>.from(await Api.post('/api/chat/$threadId/messages', {'text': text, 'attachments': files, if (replyTo != null) 'reply_to': replyTo}));

  /// Upload files (name -> bytes). Returns the [{url,name,size,type}] to attach to the message.
  static Future<List<Map<String, dynamic>>> upload(String threadId, Map<String, List<int>> files) async {
    final res = await http.Response.fromStream(await Api.upload('/api/chat/$threadId/upload', files));
    dynamic body; try { body = jsonDecode(res.body); } catch (_) { body = null; }
    if (res.statusCode >= 400) { throw ApiException((body is Map ? body['error'] : null)?.toString() ?? 'Upload failed (${res.statusCode})', res.statusCode); }
    return [for (final f in (body['files'] as List)) Map<String, dynamic>.from(f as Map)];
  }

  static Future<void> react(String messageId, String? emoji) => Api.put('/api/chat/messages/$messageId/reaction', {'emoji': emoji});
  static Future<void> delete(String messageId) => Api.delete('/api/chat/messages/$messageId');
}

String fullName(Map<String, dynamic> p) => '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
