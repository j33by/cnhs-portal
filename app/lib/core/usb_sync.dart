import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'messenger.dart';

enum UsbState { none, connected, syncing, error }

/// Windows only. Watches drive letters for the terminal's USB stick.
///  - stick plugged in   -> every "Attendance Logs*.txt" and "Employee Form*.xls" is uploaded -> server stores punches, notifies parents/students
///  - app data changed   -> server marks the USB dirty (Realtime) -> "Employee Form.xls" on the stick is rewritten
/// File names are matched with OR without underscores ("Employee Form.xls", "Employee_Form.xls").
class UsbSync extends ChangeNotifier {
  UsbState state = UsbState.none;
  String? drive; String message = 'Plug in the biometric USB';
  DateTime? lastSync;
  Timer? _poll; RealtimeChannel? _chan; bool _busy = false;
  final Map<String, String> _seen = {};                  // file path -> "mtime|size" already uploaded
  final Set<String> _backedUp = {};

  static final logRe = RegExp(r'^attendance[ _]*logs.*\.txt$', caseSensitive: false);
  static final formRe = RegExp(r'^employee[ _]*form.*\.xls$', caseSensitive: false);
  static final datRe = RegExp(r'userinfo\.dat$', caseSensitive: false);
  static const defaultFormName = 'Employee Form.xls';    // what the terminal's own export is called

  void start() {
    if (!Platform.isWindows) return;
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _chan = sb.channel('usb-dirty').onPostgresChanges(
        event: PostgresChangeEvent.update, schema: 'public', table: 'usb_sync_state',
        callback: (_) { _writeForm(); }).subscribe();
  }
  @override
  void dispose() { _poll?.cancel(); _chan?.unsubscribe(); super.dispose(); }

  List<File> _files(Directory d) {
    try { return d.listSync().whereType<File>().toList(); } catch (_) { return []; }
  }
  bool _isTerminalFile(File f) { final n = p.basename(f.path); return logRe.hasMatch(n) || formRe.hasMatch(n) || datRe.hasMatch(n); }

  Directory? _findStick() {
    for (var c = 68; c <= 90; c++) {                     // D: .. Z:
      final d = Directory('${String.fromCharCode(c)}:\\');
      try { if (d.existsSync() && _files(d).any(_isTerminalFile)) return d; } catch (_) {}
    }
    return null;
  }
  List<File> _logs(Directory d) => _files(d).where((f) => logRe.hasMatch(p.basename(f.path))).toList();
  File? _form(Directory d) {
    final fs = _files(d).where((f) => formRe.hasMatch(p.basename(f.path))).toList();
    if (fs.isEmpty) return null;
    final exact = fs.where((f) => p.basename(f.path).toLowerCase().replaceAll('_', ' ') == 'employee form.xls');
    if (exact.isNotEmpty) return exact.first;
    fs.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return fs.first;
  }
  String _sig(File f) => '${f.lastModifiedSync().millisecondsSinceEpoch}|${f.lengthSync()}';

  Future<void> _tick() async {
    if (_busy) return; _busy = true;
    try {
      final d = _findStick();
      if (d == null) {
        if (state != UsbState.none) { state = UsbState.none; drive = null; _seen.clear(); message = 'Plug in the biometric USB'; notifyListeners(); }
        return;
      }
      drive = d.path;
      if (state == UsbState.none) { state = UsbState.connected; message = 'USB found on ${d.path}'; notifyListeners(); }
      if (_logs(d).any((f) => _seen[f.path] != _sig(f))) { _busy = false; await syncNow(); }
    } catch (e) { state = UsbState.error; message = errorText(e); notifyListeners(); } finally { _busy = false; }
  }

  /// Full two-way sync: stick -> database, then database -> stick.
  Future<void> syncNow() async {
    final d = _findStick(); if (d == null) return;
    state = UsbState.syncing; message = 'Syncing…'; notifyListeners();
    try {
      var uploaded = 0;
      for (final f in _logs(d)) {                        // all log files; duplicates are ignored by the server
        final r = await Api.upload('/api/usb/ingest', {'logs': await f.readAsBytes()});
        if (r.statusCode >= 400) throw ApiException('Upload of ${p.basename(f.path)} failed (${r.statusCode})');
        _seen[f.path] = _sig(f); uploaded++;
      }
      final form = _form(d);
      if (form != null) await Api.upload('/api/usb/ingest', {'employee': await form.readAsBytes()});   // learn who is already on the terminal
      await _writeForm();
      state = UsbState.connected; lastSync = DateTime.now(); message = 'Synced ${d.path}  ($uploaded log file${uploaded == 1 ? '' : 's'})';
    } catch (e) { state = UsbState.error; message = 'Sync failed: ${errorText(e)}'; }
    notifyListeners();
  }

  Future<void> _writeForm() async {
    final d = _findStick(); if (d == null) return;       // not plugged in: stays "dirty", written on next plug-in
    final r = await Api.raw('/api/usb/employee-form');
    if (r.statusCode != 200) return;
    final existing = _form(d);
    final target = existing?.path ?? p.join(d.path, defaultFormName);
    if (existing != null && _backedUp.add(target)) {     // keep the terminal's original once per session
      final bak = File('$target.bak'); if (!bak.existsSync()) await existing.copy(bak.path);
    }
    await File(target).writeAsBytes(r.bodyBytes, flush: true);
    await Api.post('/api/usb/written', {'version': int.tryParse(r.headers['x-sync-version'] ?? '0') ?? 0});
    lastSync = DateTime.now(); notifyListeners();
  }
}
