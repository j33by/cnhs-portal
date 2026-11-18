import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config.dart';
import 'core/api.dart';
import 'core/lookup.dart';
import 'core/messenger.dart';
import 'core/offline.dart';
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
  await LocalCache.init();          // last saved data + who was signed in
  Net.i.start();                    // online / offline watcher
  await Net.i.check();              // know right away if we start offline, so saved data shows instantly
  try { await Push.init(); } catch (_) {}
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

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  Map<String, dynamic>? profile;
  String? loadedFor;
  bool loading = false;
  Object? loadError;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = sb.auth.onAuthStateChange.listen((s) {
      final sess = s.session;
      if (sess != null) { Identity.save(sess); }                                   // remember who is signed in, for offline start
      if (s.event == AuthChangeEvent.signedOut) { Identity.clear(); LocalCache.wipe(); }
      _load();
    });
    profileReload.addListener(_reload);
    Net.i.addListener(_onNet);
    WidgetsBinding.instance.addObserver(this);
    _load();
    _onNet();
  }
  @override
  void dispose() { _sub?.cancel(); profileReload.removeListener(_reload); Net.i.removeListener(_onNet); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) { Net.i.check(); } }

  bool _recovering = false;
  /// Opened offline with an expired login: when the internet is back, sign in again silently with the saved session.
  Future<void> _onNet() async {
    if (!Net.i.online || sb.auth.currentSession != null || Identity.sessionJson == null || _recovering) { return; }
    _recovering = true;
    try { await sb.auth.recoverSession(Identity.sessionJson!); _reload(); }
    on AuthException catch (e) {
      if (e.statusCode == '400' || e.statusCode == '401' || e.statusCode == '403') { await Identity.clear(); await LocalCache.wipe(); if (mounted) { setState(() { profile = null; loadedFor = null; }); } }
    } catch (_) {}
    _recovering = false;
  }

  void _reload() { loadedFor = null; _load(); }

  Future<void> _load() async {
    final uid = myUidOrNull;
    if (uid == null) {
      Lookup.i.stop();
      if (mounted) { setState(() { profile = null; loadedFor = null; loading = false; loadError = null; }); }
      return;
    }
    if (uid == loadedFor && profile != null) { return; }
    setState(() { loading = true; loadError = null; });
    try {
      final p = await cachedRow('profile', () => sb.from('profiles').select().eq('id', uid).maybeSingle());
      if (!mounted) { return; }
      setState(() { profile = p; loadedFor = uid; loading = false; });
      if (p != null && p['onboarded'] == true) { Lookup.i.start(); Push.register(); }
    } catch (e) {
      if (mounted) { setState(() { loadError = e; loading = false; }); }
    }
  }

  @override
  Widget build(BuildContext c) {
    if (myUidOrNull == null) { return const LoginScreen(); }
    if (loadError != null && profile == null) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off, size: 56), const SizedBox(height: 12), Text(errorText(loadError!), textAlign: TextAlign.center), const SizedBox(height: 16),
        FilledButton(onPressed: _reload, child: const Text('Try again')), TextButton(onPressed: () => appSignOut(), child: const Text('Sign out')),
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
