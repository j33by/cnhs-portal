// Real values are passed at build time:  --dart-define=SUPABASE_URL=...  (see .github/workflows/build.yml)
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://cnhs-api.onrender.com');
  static const mobileRedirect = 'io.cnhs.portal://login-callback';        // Android deep link
  static const windowsPort = 54321;                                       // Windows loopback sign-in
  static const windowsRedirect = 'http://localhost:$windowsPort/callback';
  // Firebase (phone push). Leave empty to run without push.
  static const fbApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const fbAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const fbSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const fbProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
}
