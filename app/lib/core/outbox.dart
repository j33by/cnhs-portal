import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'messenger.dart';
import 'offline.dart';

String newOpId() {
  final r = Random.secure();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
}

/// One saved change waiting for the internet. `id` is the operation id the server uses to make retries harmless.
class OutboxItem {
  final String id, uid, kind, key, label, method, path; final Map<String, dynamic> body; final DateTime created;
  String state; String? message; int tries; bool sending = false;      // state: pending | failed
  OutboxItem({required this.id, required this.uid, required this.kind, required this.key, required this.label, required this.method, required this.path, required this.body, required this.created, this.state = 'pending', this.message, this.tries = 0});
  Map<String, dynamic> toJson() => {'id': id, 'uid': uid, 'kind': kind, 'key': key, 'label': label, 'method': method, 'path': path, 'body': body, 'created': created.toIso8601String(), 'state': state, 'message': message, 'tries': tries};
  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(id: j['id'], uid: j['uid'], kind: j['kind'], key: j['key'], label: j['label'], method: j['method'], path: j['path'],
      body: Map<String, dynamic>.from(j['body'] as Map), created: DateTime.parse(j['created']), state: j['state'] ?? 'pending', message: j['message'], tries: j['tries'] ?? 0);
}

/// Offline writes for teachers (subject attendance and class-record scores).
/// - A save made with no internet is stored on the phone and sent automatically later, oldest first.
/// - Every change has an operation id; the server remembers it, so a retry is never applied or notified twice.
/// - Every entry carries the version (`base`) the teacher saw. The server refuses to overwrite something that changed since,
///   and refuses to bring back something that was deleted since. Those entries are reported, never forced.
class Outbox extends ChangeNotifier {
  Outbox._();
  static final i = Outbox._();
  final items = <OutboxItem>[];
  final notes = <Map<String, dynamic>>[];       // finished, but something was not applied (shown in Sync status)
  int syncedTick = 0;
  bool _flushing = false, _started = false;

  List<OutboxItem> get mine => [for (final x in items) if (x.uid == myUid) x];
  int get waiting => mine.where((x) => x.state != 'failed').length;
  int get failed => mine.where((x) => x.state == 'failed').length;
  List<Map<String, dynamic>> get myNotes => [for (final n in notes) if (n['uid'] == myUid) n];
  List<OutboxItem> pendingFor(String key) => [for (final x in mine) if (x.key == key && x.state != 'failed') x];

  void init() {
    if (_started) { return; }
    _started = true;
    final p = LocalCache.prefs;
    try {
      final q = p?.getString('ob:q'), n = p?.getString('ob:n');
      if (q != null) { items.addAll([for (final e in jsonDecode(q) as List) OutboxItem.fromJson(Map<String, dynamic>.from(e as Map))]); }
      if (n != null) { notes.addAll([for (final e in jsonDecode(n) as List) Map<String, dynamic>.from(e as Map)]); }
    } catch (_) {}
    Net.i.addListener(() { if (Net.i.online) { flush(); } });
    sb.auth.onAuthStateChange.listen((_) => flush());
    Timer.periodic(const Duration(seconds: 15), (_) { if (waiting > 0) { flush(); } });
    flush();
  }

  void _persist() {
    final p = LocalCache.prefs; if (p == null) { return; }
    p.setString('ob:q', jsonEncode([for (final x in items) x.toJson()]));
    p.setString('ob:n', jsonEncode(notes));
  }

  bool _retryable(Object e) => e is ApiException ? (e.status == null || e.status! >= 500 || const {401, 408, 409, 429}.contains(e.status)) : true;

  Future<Map<String, dynamic>> _send(OutboxItem it) async {
    final r = await Api.send(it.method, it.path, it.body, headers: {'X-Op-Id': it.id});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  /// Save now if online, otherwise (or when the connection fails) keep it on the phone.
  /// Returns the server answer, or null when it was stored for later. A rejected change (validation, not allowed) throws as usual.
  Future<Map<String, dynamic>?> submit({required String kind, required String key, required String label, required String method, required String path, required Map<String, dynamic> body}) async {
    final uid = myUid;
    if (uid.isEmpty) { throw ApiException('Please sign in again.'); }
    final prev = mine.where((x) => x.key == key && x.state == 'pending' && !x.sending).toList();
    if (prev.isNotEmpty) {                       // an unsent save for the same class: fold the new edits into it (newer edit wins, the oldest base is kept)
      _merge(kind, prev.first.body, body);
      _persist(); notifyListeners(); flush();
      return null;
    }
    final it = OutboxItem(id: newOpId(), uid: uid, kind: kind, key: key, label: label, method: method, path: path, body: {...body, 'queued': false}, created: DateTime.now());
    if (Net.i.online) {
      try {
        final r = await _send(it);
        _applyResult(it, r);
        return r;
      } catch (e) {
        if (!_retryable(e)) { rethrow; }
      }
    }
    it.body['queued'] = true;                    // from now on the server applies it carefully (no overwrite of newer work, no resurrecting deleted data)
    items.add(it); _persist(); notifyListeners();
    Net.i.suspect();
    return null;
  }

  void _merge(String kind, Map<String, dynamic> into, Map<String, dynamic> from) {
    if (kind == 'class_attendance') {
      final dates = (into['dates'] as List).cast<Map<String, dynamic>>();
      for (final d in (from['dates'] as List).cast<Map<String, dynamic>>()) {
        final hit = dates.where((x) => x['date'] == d['date']).toList();
        if (hit.isEmpty) { dates.add(d); continue; }
        final entries = (hit.first['entries'] as List).cast<Map<String, dynamic>>();
        for (final e in (d['entries'] as List).cast<Map<String, dynamic>>()) {
          final i = entries.indexWhere((x) => x['student_id'] == e['student_id']);
          if (i < 0) { entries.add(e); } else { final base = entries[i]['base']; entries[i] = {...e, 'base': base}; }
        }
      }
    } else {
      final list = (into['scores'] as List).cast<Map<String, dynamic>>();
      for (final e in (from['scores'] as List).cast<Map<String, dynamic>>()) {
        final i = list.indexWhere((x) => x['column_id'] == e['column_id'] && x['student_id'] == e['student_id']);
        if (i < 0) { list.add(e); } else { final base = list[i]['base']; list[i] = {...e, 'base': base}; }
      }
    }
  }

  static const _why = {'changed': 'changed by someone else meanwhile', 'deleted': 'deleted meanwhile', 'column_deleted': 'its column was deleted', 'student_left': 'student no longer in the class', 'invalid': 'invalid score'};

  /// After a successful send: remember what was not applied, and move the versions forward in changes still waiting for the same class.
  int _applyResult(OutboxItem it, Map<String, dynamic> r) {
    final sk = (r['skipped'] as List?) ?? const [], vs = (r['versions'] as List?) ?? const [];
    if (vs.isNotEmpty) {
      for (final o in items) {
        if (identical(o, it) || o.key != it.key || o.uid != it.uid) { continue; }
        if (o.kind == 'class_attendance') {
          for (final d in (o.body['dates'] as List).cast<Map<String, dynamic>>()) {
            for (final e in (d['entries'] as List).cast<Map<String, dynamic>>()) {
              for (final v in vs) { if (v['student_id'] == e['student_id'] && v['date'] == d['date']) { e['base'] = v['updated_at']; } }
            }
          }
        } else {
          for (final e in (o.body['scores'] as List).cast<Map<String, dynamic>>()) {
            for (final v in vs) { if (v['student_id'] == e['student_id'] && v['column_id'] == e['column_id']) { e['base'] = v['updated_at']; } }
          }
        }
      }
    }
    if (sk.isNotEmpty) {
      final by = <String, int>{};
      for (final s in sk) { by['${s['reason']}'] = (by['${s['reason']}'] ?? 0) + 1; }
      notes.insert(0, {'uid': it.uid, 'label': it.label, 'at': DateTime.now().toIso8601String(), 'text': '${sk.length} entr${sk.length == 1 ? 'y' : 'ies'} not applied: ${by.entries.map((e) => '${e.value} ${_why[e.key] ?? e.key}').join(', ')}. The server kept its own version.'});
      if (notes.length > 30) { notes.removeRange(30, notes.length); }
    }
    _persist();
    return sk.length;
  }

  Future<void> flush() async {
    if (_flushing || !Net.i.online || myUidOrNull == null || sb.auth.currentSession == null || waiting == 0) { return; }
    _flushing = true;
    var done = 0, skipped = 0;
    try {
      for (final it in List.of(mine)) {
        if (it.state == 'failed') { continue; }
        it.sending = true; notifyListeners();
        try {
          final r = await _send(it);
          items.remove(it); done++; skipped += _applyResult(it, r);
        } on ApiException catch (e) {
          it.tries++; it.message = e.message;
          if (_retryable(e)) { break; }
          it.state = 'failed'; _persist();                     // the server refused it for good: keep it visible, never loop
        } catch (_) { it.tries++; break; }
        finally { it.sending = false; }
      }
    } finally { _flushing = false; _persist(); notifyListeners(); }
    if (done > 0) { syncedTick++; notifyListeners(); toast(skipped == 0 ? 'Saved changes synced ($done)' : 'Changes synced. $skipped entr${skipped == 1 ? 'y was' : 'ies were'} not applied, see Sync status'); }
  }

  void retry(OutboxItem it) { it.state = 'pending'; it.tries = 0; it.message = null; _persist(); notifyListeners(); flush(); }
  void discard(OutboxItem it) { items.remove(it); _persist(); notifyListeners(); }
  void clearNotes() { notes.removeWhere((n) => n['uid'] == myUid); _persist(); notifyListeners(); }
}
