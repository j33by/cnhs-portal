import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api.dart';
import '../core/config.dart';
import '../core/messenger.dart';
import '../core/windows_login.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.school, size: 72, color: Color(0xFF1B5E3B)),
          const SizedBox(height: 12),
          Text('CNHS Portal', style: Theme.of(c).textTheme.headlineMedium),
          const Text('Calape National High School'),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.login), label: const Text('Continue with Google'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              try {
                if (Platform.isWindows) { await signInWithGoogleWindows(); }
                else { await sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: Config.mobileRedirect); }
              } catch (e) { toastError(e); }
            },
          ),
          const SizedBox(height: 12),
          const Text('First time? You will fill in a short form after signing in.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ])))),
      );
}
