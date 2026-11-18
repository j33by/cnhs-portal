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
        body: Stack(fit: StackFit.expand, children: [
          Image.asset('assets/images/login_bg.jpg', fit: BoxFit.cover, alignment: Alignment.center, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1B5E3B))),
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: .15), Colors.black.withValues(alpha: .55)]))),
          SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: Container(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            decoration: BoxDecoration(color: Theme.of(c).colorScheme.surface, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 24, offset: const Offset(0, 10))]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 92, height: 92, padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: Theme.of(c).dividerColor), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 8)]),
                child: ClipOval(child: Image.asset('assets/images/logo.jpg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 52, color: Color(0xFF1B5E3B)))),
              ),
              const SizedBox(height: 14),
              Text('CNHS Portal', style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('Calape National High School', style: TextStyle(color: Theme.of(c).hintColor)),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.login), label: const Text('Continue with Google'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  try {
                    if (Platform.isWindows) { await signInWithGoogleWindows(); }
                    else { await sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: Config.mobileRedirect); }
                  } catch (e) { toastError(e); }
                },
              ),
              const SizedBox(height: 12),
              Text('First time? You will fill in a short form after signing in.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
            ]),
          ))))),
        ]),
      );
}
