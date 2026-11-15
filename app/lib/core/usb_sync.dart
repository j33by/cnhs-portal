import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';

enum UsbState { none, connected, syncing, error }

/// Windows only. Watches the drive letters for the terminal's USB stick.
///  - Stick plugged in      -> uploads Attendance_Logs.txt (all punches) -> server updates attendance + notifies parents/students
///  - App data changed      -> server marks USB "dirty" (Realtime) -> Employee_Form.xls is rewritten on the stick
class UsbSync extends ChangeNotifier {
  UsbState state = UsbState.none;
  String? drive; String message = 'Plug in the biometric USB';
  DateTime? lastSync; int lastNew = 0;
  Timer? _poll; RealtimeChannel? _chan; DateTime? _logMtime; bool _busy = false;
  static final _logRe = RegExp(r'attendance[ _]*logs.*\.txt$', caseSensitive: false);
  static final _formRe = RegExp(r'employee[ _]*form.*\.xls$', caseSensitive: false);

  void start() {
    if (!Platform.isWindows) return;
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _chan = sb.channel('usb-dirty').onPostgresChanges(
        event: PostgresChangeEvent.update, schema: 'public', table: 'usb_sync_state',
        callback: (_) => _writeForm()).subscribe();            // instant write-back when the app changes anything
  }
  @override void dispose() { _poll?.cancel(); _chan?.unsubscribe(); super.dispose(); }

  Directory? _findStick() {
    for (var c = 68; c <= 90; c++) {                           // D: .. Z:  (skips C:)
      final d = Directory('${String.fromCharCode(c)}:\\');
      try {
        if (!d.existsSync()) continue;
        final names = d.listSync().whereType<File>().map((f) => f.path).toList();
        if (names.any((n) => _logRe.hasMatch(n) || _formRe.hasMatch(n))) return d;
      } catch (_) {}
    }
    return null;
  }
  File? _newest(Directory d, RegExp re) {
    final fs = d.listSync().whereType<File>().where((f) => re.hasMatch(f.path)).toList();
    if (fs.isEmpty) return null;
    fs.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return fs.first;
  }

  Future<void> _tick() async {
    if (_busy) return; _busy = true;
    try {
      final d = _findStick();
      if (d == null) { if (state != UsbState.none) { state = UsbState.none; drive = null; _logMtime = null; message = 'Plug in the biometric USB'; notifyListeners(); } return; }
      drive = d.path;
      if (state == UsbState.none) { state = UsbState.connected; message = 'USB found on ${d.path}'; notifyListeners(); }
      final log = _newest(d, _logRe);
      if (log != null && (_logMtime == null || log.lastModifiedSync().isAfter(_logMtime!))) await syncNow();
    } catch (e) { state = UsbState.error; message = '$e'; notifyListeners(); } finally { _busy = false; }
  }

  /// Full two-way sync: stick -> database, then database -> stick.
  Future<void> syncNow() async {
    final d = _findStick(); if (d == null) return;
    state = UsbState.syncing; message = 'Syncing…'; notifyListeners();
    try {
      final log = _newest(d, _logRe), form = _newest(d, _formRe);
      final files = <String, List<int>>{};
      if (log != null) files['logs'] = await log.readAsBytes();
      if (form != null) files['employee'] = await form.readAsBytes();
      if (files.isNotEmpty) {
        final r = await Api.upload('/api/usb/ingest', files);
        if (r.statusCode >= 400) throw ApiException('Upload failed (${r.statusCode})');
        if (log != null) _logMtime = log.lastModifiedSync();
      }
      await _writeForm();
      state = UsbState.connected; lastSync = DateTime.now(); message = 'Synced ${d.path}';
    } catch (e) { state = UsbState.error; message = 'Sync failed: $e'; }
    notifyListeners();
  }

  Future<void> _writeForm() async {
    final d = _findStick(); if (d == null) return;             // not plugged in: stays "dirty", written on next plug-in
    final r = await Api.raw('/api/usb/employee-form');
    if (r.statusCode != 200) return;
    final target = _newest(d, _formRe)?.path ?? '${d.path}Employee_Form.xls';
    await File(target).writeAsBytes(r.bodyBytes, flush: true);
    await Api.post('/api/usb/written', {'version': int.tryParse(r.headers['x-sync-version'] ?? '0') ?? 0});
    lastSync = DateTime.now(); notifyListeners();
  }
}
