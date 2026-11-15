import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config.dart';
import 'core/api.dart';
import 'core/push.dart';
import 'screens/login.dart';
import 'screens/onboarding.dart';
import 'screens/teacher/teacher_home.dart';
import 'screens/student/student_home.dart';
import 'screens/parent/parent_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  if (Platform.isAndroid) { try { await Firebase.initializeApp(); } catch (_) {} }   // needs google-services.json
  runApp(const CnhsApp());
}

class CnhsApp extends StatelessWidget {
  const CnhsApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'CNHS Portal', debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E3B), useMaterial3: true),
        home: const AuthGate());
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<AuthState>(
        stream: sb.auth.onAuthStateChange,
        builder: (c, _) {
          if (sb.auth.currentSession == null) return const LoginScreen();
          return FutureBuilder<Map<String, dynamic>?>(
            key: ValueKey(sb.auth.currentSession!.accessToken),
            future: sb.from('profiles').select().eq('id', sb.auth.currentUser!.id).maybeSingle(),
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
              final p = s.data;
              if (p == null || p['onboarded'] != true) return const OnboardingScreen();   // forms come first
              Push.register();                                                           // phone notifications
              switch (p['role']) {
                case 'teacher': return TeacherHome(profile: p);
                case 'student': return StudentHome(profile: p);
                default: return ParentHome(profile: p);
              }
            });
        });
}
