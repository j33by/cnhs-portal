import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'messenger.dart';

enum UsbState { none, connected, syncing, error }

/// Windows only. Watches the USB stick of the biometric terminal.
///  - stick plugged in   -> terminal files are uploaded (people first, then punches) -> the server links terminal people to students by name,
///                          stores punches, notifies students + parents -> "Employee Form.xls" on the stick is rewritten with ALL students
///  - app data changed   -> new student / section / schedule -> "Employee Form.xls" is rewritten at once (stick plugged in) or on the next plug-in
/// A stick is any removable drive (even a brand-new empty one) or any drive that already holds terminal files.
/// File names are matched with OR without underscores ("Employee Form.xls", "Employee_Form.xls").
class UsbSync extends ChangeNotifier {
  UsbState state = UsbState.none;
  String? drive; String message = 'Plug in the biometric USB';
  String detail = '';                                    // what the last sync did (students written, punches, ...)
  DateTime? lastSync;
  Timer? _poll; RealtimeChannel? _chan; bool _busy = false, _writing = false;
  int _ticks = 0; DateTime _retryAt = DateTime(2000);       // after an error, wait 30 s before trying again by itself
  String _letters = '';                                  // existing drive letters; the removable-drive query runs only when this changes
  Set<String> _removable = {};
  final Map<String, String> _seen = {};                  // file path -> "mtime|size" already uploaded
  final Set<String> _backedUp = {};

  static final logRe = RegExp(r'^attendance[ _]*logs.*\.txt$', caseSensitive: false);
  static final reportRe = RegExp(r'^all[ _]*report.*\.xls$', caseSensitive: false);   // the terminal's own attendance export
  static final formRe = RegExp(r'^employee[ _]*form.*\.xls$', caseSensitive: false);
  static final datRe = RegExp(r'userinfo\.dat$', caseSensitive: false);
  static const defaultFormName = 'Employee Form.xls';    // what the terminal's own export is called

  void start() {
    if (!Platform.isWindows) return;
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _chan = sb.channel('usb-dirty').onPostgresChanges(
        event: PostgresChangeEvent.update, schema: 'public', table: 'usb_sync_state',
        callback: (pl) { if (pl.newRecord['dirty'] == true) { _writeForm(); } }).subscribe();       // only when something changed (not for our own "written" update)
  }
  @override
  void dispose() { _poll?.cancel(); _chan?.unsubscribe(); super.dispose(); }

  List<File> _files(Directory d) {
    try { return d.listSync().whereType<File>().toList(); } catch (_) { return []; }
  }
  bool _isTerminalFile(File f) { final n = p.basename(f.path); return logRe.hasMatch(n) || reportRe.hasMatch(n) || formRe.hasMatch(n) || datRe.hasMatch(n); }

  /// Letters of removable drives (USB sticks). Asked from Windows only when the set of drive letters changed.
  Future<void> _refreshRemovable() async {
    final now = [for (var c = 68; c <= 90; c++) if (Directory('${String.fromCharCode(c)}:\\').existsSync()) String.fromCharCode(c)].join();
    if (now == _letters) return;
    _letters = now;
    try {
      final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', "Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' | ForEach-Object { \$_.DeviceID }"]).timeout(const Duration(seconds: 8));
      _removable = {for (final l in const LineSplitter().convert('${r.stdout}')) if (RegExp(r'^[A-Za-z]:').hasMatch(l.trim())) l.trim()[0].toUpperCase()};
    } catch (_) { _removable = {}; }
  }

  Directory? _findStick() {
    Directory? firstRemovable;
    for (var c = 68; c <= 90; c++) {                     // D: .. Z:
      final l = String.fromCharCode(c), d = Directory('$l:\\');
      try {
        if (!d.existsSync()) continue;
        if (_files(d).any(_isTerminalFile)) return d;    // a drive that already holds terminal files wins
        if (firstRemovable == null && _removable.contains(l)) firstRemovable = d;
      } catch (_) {}
    }
    return firstRemovable;                               // e.g. a new, empty USB stick
  }
  List<File> _logs(Directory d) => _files(d).where((f) => logRe.hasMatch(p.basename(f.path)) || reportRe.hasMatch(p.basename(f.path))).toList();
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
      await _refreshRemovable();
      final d = _findStick();
      if (d == null) {
        if (state != UsbState.none) { state = UsbState.none; drive = null; _seen.clear(); message = 'Plug in the biometric USB'; notifyListeners(); }
        return;
      }
      final fresh = state == UsbState.none;
      drive = d.path;
      if (fresh) { state = UsbState.connected; message = 'USB found on ${d.path}'; notifyListeners(); }
      final newLogs = _logs(d).any((f) => _seen[f.path] != _sig(f));
      if ((fresh || newLogs) && DateTime.now().isAfter(_retryAt)) { _busy = false; await syncNow(); return; }       // plugged in: always read the stick and write the student list
      if (++_ticks % 5 == 0) { await _writeIfDirty(); }                        // every ~15 s: pick up changes whose live message was missed
    } catch (e) { state = UsbState.error; message = errorText(e); notifyListeners(); } finally { _busy = false; }
  }

  Future<void> _writeIfDirty() async {
    try {
      final r = await Api.raw('/api/usb/state'); if (r.statusCode != 200) return;
      final s = jsonDecode(r.body); if (s is Map && s['dirty'] == true) { await _writeForm(); }
    } catch (_) {}
  }

  /// Full two-way sync: stick -> database, then database -> stick.
  Future<void> syncNow() async {
    final d = _findStick(); if (d == null) return;
    state = UsbState.syncing; message = 'Syncing… please do not remove the USB'; detail = ''; notifyListeners();
    try {
      final notes = <String>[];
      final form = _form(d);
      if (form != null) {                                // 1) who is already on the terminal -> matched to students by name
        final r = await _ingest({'employee': await form.readAsBytes()}, p.basename(form.path));
        final linked = r['linked'] ?? 0; if (linked > 0) notes.add('$linked terminal ${linked == 1 ? 'person' : 'people'} linked to students by name');
      }
      var files = 0, punches = 0, newPunches = 0;
      for (final f in _logs(d)) {                        // 2) all log files; duplicates are ignored by the server
        final r = await _ingest({(reportRe.hasMatch(p.basename(f.path)) ? 'report' : 'logs'): await f.readAsBytes()}, p.basename(f.path));
        final a = r['attendance'] is Map ? r['attendance'] as Map : const {};
        punches += (a['punches'] as num?)?.toInt() ?? 0; newPunches += (a['newPunches'] as num?)?.toInt() ?? 0;
        _seen[f.path] = _sig(f); files++;
      }
      if (files > 0) notes.insert(0, '$newPunches new punch${newPunches == 1 ? '' : 'es'} read from $files log file${files == 1 ? '' : 's'}${newPunches > 0 ? ' · students and parents notified' : ''}');
      final wrote = await _writeForm(throwOnError: true);   // 3) every student -> Employee Form.xls on the stick
      if (wrote != null) { notes.add(wrote); }
      state = UsbState.connected; lastSync = DateTime.now(); message = 'Synced ${d.path} · safe to remove the USB'; detail = notes.join('\n');
    } catch (e) { state = UsbState.error; message = 'Sync failed: ${errorText(e)}'; _retryAt = DateTime.now().add(const Duration(seconds: 30)); }
    notifyListeners();
  }

  Future<Map<String, dynamic>> _ingest(Map<String, List<int>> files, String name) async {
    final res = await http.Response.fromStream(await Api.upload('/api/usb/ingest', files));
    dynamic body; try { body = jsonDecode(res.body); } catch (_) { body = null; }
    if (res.statusCode >= 400) throw ApiException('Upload of $name failed: ${(body is Map ? body['error'] : null) ?? 'server error ${res.statusCode}'}', res.statusCode);
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  /// Ask Windows to write everything cached to the stick (best effort: needs no admin on most PCs; ignored when refused).
  Future<void> _flushDrive(Directory d) async {
    try { await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', 'Write-VolumeCache -DriveLetter ${d.path[0]}']).timeout(const Duration(seconds: 15)); } catch (_) {}
  }

  /// Rewrite the student list on the stick. Returns a short description of what was written (null when there is no stick).
  Future<String?> _writeForm({bool throwOnError = false}) async {
    if (_writing) return null; _writing = true;
    try {
      final d = _findStick(); if (d == null) return null;     // not plugged in: stays "dirty", written on next plug-in
      final r = await Api.raw('/api/usb/employee-form');
      if (r.statusCode != 200) {
        String why = 'server error ${r.statusCode}'; try { final b = jsonDecode(r.body); if (b is Map && b['error'] != null) { why = '${b['error']}'; } } catch (_) {}
        throw ApiException('Could not build the student list: $why', r.statusCode);
      }
      final existing = _form(d);
      final target = existing?.path ?? p.join(d.path, defaultFormName);
      if (existing != null && _backedUp.add(target)) {        // keep the terminal's original once per session
        final bak = File('$target.bak'); if (!bak.existsSync()) { try { await existing.copy(bak.path); } catch (_) {} }
      }
      try { await File(target).writeAsBytes(r.bodyBytes, flush: true); }
      on FileSystemException catch (e) { throw ApiException('Could not write ${p.basename(target)} to ${d.path} (${e.osError?.message ?? e.message}). Is the stick locked or full?'); }
      final back = await File(target).readAsBytes();      // read it back: the stick must hold exactly what we wrote
      if (back.length != r.bodyBytes.length || back.length < 1000) { throw ApiException('The file on the stick looks incomplete. Try again.'); }
      await _flushDrive(d);                                // push Windows' write cache to the stick so it can be pulled out safely
      await Api.post('/api/usb/written', {'version': int.tryParse(r.headers['x-sync-version'] ?? '0') ?? 0});
      final students = r.headers['x-students'] ?? '?', people = r.headers['x-people'] ?? '?', assigned = int.tryParse(r.headers['x-assigned'] ?? '0') ?? 0;
      lastSync = DateTime.now();
      final msg = '$students student${students == '1' ? '' : 's'} written to ${p.basename(target)} (${people == students ? 'all' : '$people people incl. others already on the terminal'})${assigned > 0 ? ' · $assigned new device ID${assigned == 1 ? '' : 's'} given' : ''}';
      detail = detail.isEmpty ? msg : '$detail\n$msg';
      if (state != UsbState.syncing) { message = 'Student list updated on ${d.path} · safe to remove the USB'; }
      notifyListeners();
      return msg;
    } catch (e) {
      if (throwOnError) { rethrow; }
      state = UsbState.error; message = 'Could not update the USB: ${errorText(e)}'; notifyListeners(); return null;
    } finally { _writing = false; }
  }
}
