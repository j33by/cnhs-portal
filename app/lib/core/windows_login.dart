import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'config.dart';

/// Google sign-in for the Windows app without registering a URL scheme:
/// open the browser, catch the redirect on http://localhost:54321, exchange the code for a session.
Future<void> signInWithGoogleWindows() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, Config.windowsPort);
  try {
    final res = await sb.auth.getOAuthSignInUrl(provider: OAuthProvider.google, redirectTo: Config.windowsRedirect);
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', res.url]);
    String? code, error;
    await for (final req in server.timeout(const Duration(minutes: 3))) {
      final q = req.uri.queryParameters;
      if (q['code'] == null && q['error'] == null) { req.response.statusCode = 404; await req.response.close(); continue; }   // favicon etc.
      code = q['code']; error = q['error_description'] ?? q['error'];
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html><body style="font-family:sans-serif;text-align:center;margin-top:20vh"><h2>${code != null ? 'Signed in to CNHS Portal' : 'Sign-in failed'}</h2><p>You can close this tab and return to the app.</p></body></html>');
      await req.response.close();
      break;
    }
    if (code == null) throw ApiException(error ?? 'Sign-in was cancelled');
    await sb.auth.exchangeCodeForSession(code);
  } finally {
    await server.close(force: true);
  }
}
