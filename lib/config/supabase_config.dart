import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

class SupabaseConfig {
  // Nilai dari lib/config/env.dart (dart-define, fallback prod).
  static String get url => AppEnv.supabaseUrl;
  static String get publishableKey => AppEnv.supabaseAnonKey;

  /// Link share aplikasi — langsung ke Google Play.
  /// (Dulu: edge function /r dengan uid untuk tracking klik; tracking
  /// dimatikan sesuai permintaan — semua share kini ke listing Play Store.)
  static const String shareLink =
      'https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';

  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      anonKey: publishableKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
