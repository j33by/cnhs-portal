import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

final sb = Supabase.instance.client;

class ApiException implements Exception {
  final String message; ApiException(this.message);
  @override String toString() => message;
}

/// All writes go through the Node API on Render. Reads/realtime use Supabase directly.
class Api {
  static Map<String, String> get _h => {
        'Authorization': 'Bearer ${sb.auth.currentSession?.accessToken ?? ''}',
        'Content-Type': 'application/json',
      };
  static dynamic _out(http.Response r) {
    dynamic body;
    try { body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body); } catch (_) { body = {'error': 'Server error (${r.statusCode})'}; }
    if (r.statusCode >= 400) throw ApiException((body is Map ? body['error'] : null)?.toString() ?? 'Request failed (${r.statusCode})');
    return body;
  }
  static Future<dynamic> post(String p, [Map<String, dynamic>? b]) async =>
      _out(await http.post(Uri.parse('${Config.apiUrl}$p'), headers: _h, body: jsonEncode(b ?? {})));
  static Future<dynamic> put(String p, Map<String, dynamic> b) async =>
      _out(await http.put(Uri.parse('${Config.apiUrl}$p'), headers: _h, body: jsonEncode(b)));
  static Future<dynamic> patch(String p, Map<String, dynamic> b) async =>
      _out(await http.patch(Uri.parse('${Config.apiUrl}$p'), headers: _h, body: jsonEncode(b)));
  static Future<dynamic> delete(String p) async => _out(await http.delete(Uri.parse('${Config.apiUrl}$p'), headers: _h));
  static Future<http.Response> raw(String p) => http.get(Uri.parse('${Config.apiUrl}$p'), headers: _h);

  static Future<http.StreamedResponse> upload(String p, Map<String, List<int>> files) async {
    final r = http.MultipartRequest('POST', Uri.parse('${Config.apiUrl}$p'))
      ..headers['Authorization'] = _h['Authorization']!;
    files.forEach((k, v) => r.files.add(http.MultipartFile.fromBytes(k, v, filename: k)));
    return r.send();
  }
}
