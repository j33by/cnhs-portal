import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config.dart';
import 'core/api.dart';
import 'core/lookup.dart';
import 'core/messenger.dart';
import 'core/push.dart';
import 'core/session.dart';
import 'screens/login.dart';
import 'screens/onboarding.dart';
import 'screens/teacher/teacher_home.dart';
import 'screens/student/student_home.dart';
import 'screens/parent/parent_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  await Push.init();
  runApp(const CnhsApp());
}

class CnhsApp extends StatelessWidget {
  const CnhsApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'CNHS Portal', debugShowCheckedModeBanner: false, scaffoldMessengerKey: messengerKey,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E3B), useMaterial3: true),
        home: const AuthGate());
}

/// Decides what to show. The profile is loaded ONCE per signed-in user: token refreshes and other auth events
/// do not reload it, so screens never flash back to a spinner and keep their place.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Map<String, dynamic>? profile;
  String? loadedFor;
  bool loading = false;
  Object? loadError;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = sb.auth.onAuthStateChange.listen((_) => _load());
    profileReload.addListener(_reload);
    _load();
  }
  @override
  void dispose() { _sub?.cancel(); profileReload.removeListener(_reload); super.dispose(); }

  void _reload() { loadedFor = null; _load(); }

  Future<void> _load() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      Lookup.i.stop();
      if (mounted) { setState(() { profile = null; loadedFor = null; loading = false; loadError = null; }); }
      return;
    }
    if (uid == loadedFor && profile != null) { return; }
    setState(() { loading = true; loadError = null; });
    try {
      final p = await sb.from('profiles').select().eq('id', uid).maybeSingle();
      if (!mounted) { return; }
      setState(() { profile = p; loadedFor = uid; loading = false; });
      if (p != null && p['onboarded'] == true) { Lookup.i.start(); Push.register(); }
    } catch (e) {
      if (mounted) { setState(() { loadError = e; loading = false; }); }
    }
  }

  @override
  Widget build(BuildContext c) {
    if (sb.auth.currentSession == null) { return const LoginScreen(); }
    if (loadError != null && profile == null) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off, size: 56), const SizedBox(height: 12), Text(errorText(loadError!), textAlign: TextAlign.center), const SizedBox(height: 16),
        FilledButton(onPressed: _reload, child: const Text('Try again')), TextButton(onPressed: () => sb.auth.signOut(), child: const Text('Sign out')),
      ]))));
    }
    if (loading && profile == null) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
    final p = profile;
    if (p == null || p['onboarded'] != true) { return const OnboardingScreen(); }
    switch (p['role']) {
      case 'teacher': return TeacherHome(profile: p);
      case 'student': return StudentHome(profile: p);
      default: return ParentHome(profile: p);
    }
  }
}
