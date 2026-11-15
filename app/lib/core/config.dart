// Pass real values at build time:  flutter build apk --dart-define=SUPABASE_URL=... (see GitHub workflow)
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://cnhs-api.onrender.com');
  static const oauthRedirect = 'io.cnhs.portal://login-callback';
}
