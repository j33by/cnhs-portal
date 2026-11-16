import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();
void toast(String m) => messengerKey.currentState?..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m)));

/// Short, readable message for any error (no "PostgrestException(message: ..., code: ...)" noise).
String errorText(Object e) {
  if (e is PostgrestException) {
    if (e.code == 'PGRST201') return 'Could not load this list. Please update the app.';
    if (e.code == '42501') return 'You do not have permission to do that.';
    return e.message;
  }
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) return 'No internet connection. Please try again.';
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}
void toastError(Object e) => toast(errorText(e));
