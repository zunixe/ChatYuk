import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://fohcucyyejdryryoxitm.supabase.co';
  static const String publishableKey =
      'sb_publishable_aFQQbXscy1mqVq5jHX7p2w_wzs2GAKg';

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
