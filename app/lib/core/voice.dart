import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'api.dart';
import 'offline.dart';

/// Room voice messages: one per person per section, at most 30 seconds, removed by the server after 12 hours.
class VoiceData {
  static const maxSeconds = 30;

  /// Live voice messages of a section (expired ones are filtered out here too, because the server removes them only every few minutes).
  static Stream<JRows> stream(String sectionId) => liveStream('room_voice|section=$sectionId', () => sb.from('room_voice').stream(primaryKey: ['id']).eq('section_id', sectionId))
      .map((rows) => [for (final r in rows) if (alive(r)) r]);
  static bool alive(Map<String, dynamic> v) { final e = DateTime.tryParse('${v['expires_at']}'); return e != null && e.isAfter(DateTime.now()); }

  static Future<void> post(String sectionId, List<int> bytes, int ms, String ext) async {
    final res = await http.Response.fromStream(await Api.upload('/api/room/voice?section_id=$sectionId&ms=$ms', {'voice.$ext': bytes}));
    if (res.statusCode >= 400) {
      dynamic b; try { b = jsonDecode(res.body); } catch (_) { b = null; }
      throw ApiException((b is Map ? b['error'] : null)?.toString() ?? 'Could not send (${res.statusCode})', res.statusCode);
    }
  }
  static Future<void> delete(String id) => Api.delete('/api/room/voice/$id');
}

/// One shared audio player for the whole Room: tapping another voice message stops the current one; tapping the same one stops it.
class VoicePlayer extends ChangeNotifier {
  static final VoicePlayer i = VoicePlayer._();
  VoicePlayer._() {
    _p.onPlayerComplete.listen((_) => _set(null));
    _p.onPlayerStateChanged.listen((s) { if (s == PlayerState.stopped || s == PlayerState.completed) { _set(null); } });
  }
  final AudioPlayer _p = AudioPlayer();
  String? playing;                                                 // id of the voice message that is playing
  void _set(String? id) { if (playing != id) { playing = id; notifyListeners(); } }

  Future<void> toggle(String id, String url) async {
    if (playing == id) { await stop(); return; }
    _set(id);
    try { await _p.stop(); await _p.play(UrlSource(url)); }
    catch (_) { _set(null); rethrow; }
  }
  /// [quiet]: used while a screen is closing (no listener may rebuild at that moment).
  Future<void> stop({bool quiet = false}) async { if (quiet) { playing = null; } else { _set(null); } try { await _p.stop(); } catch (_) {} }
}

/// Records up to 30 s. [stop] returns the bytes + duration; [cancel] throws the recording away.
class VoiceRecorder {
  final AudioRecorder _r = AudioRecorder();
  final _sw = Stopwatch();
  String? _path; String ext = 'm4a';
  int get elapsedMs => _sw.elapsedMilliseconds;

  Future<bool> start() async {
    if (!await _r.hasPermission()) { return false; }
    final dir = await getTemporaryDirectory();
    final aac = await _r.isEncoderSupported(AudioEncoder.aacLc);
    ext = aac ? 'm4a' : 'wav';
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _r.start(aac ? const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 22050, numChannels: 1) : const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: _path!);
    _sw..reset()..start();
    return true;
  }
  Future<({List<int> bytes, int ms})?> stop() async {
    _sw.stop(); final ms = _sw.elapsedMilliseconds;
    final p = await _r.stop() ?? _path; if (p == null) { return null; }
    try { final f = File(p); final b = await f.readAsBytes(); await f.delete().catchError((_) => f); return (bytes: b, ms: ms > maxMs ? maxMs : ms); } catch (_) { return null; }
  }
  static const maxMs = VoiceData.maxSeconds * 1000;
  Future<void> cancel() async { _sw.stop(); try { await _r.cancel(); } catch (_) {} }
  Future<void> dispose() async { try { await _r.dispose(); } catch (_) {} }
}
