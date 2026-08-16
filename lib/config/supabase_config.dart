import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://fohcucyyejdryryoxitm.supabase.co';
  static const String publishableKey = 'sb_publishable_aFQQbXscy1mqVq5jHX7p2w_wzs2GAKg';

  // Base URL edge function referral redirect (tracking share).
  static const String referralBase =
      'https://fohcucyyejdryryoxitm.functions.supabase.co/r';

  /// Link share personal — menyisipkan uid pengirim untuk tracking klik.
  static String shareLink(String uid) => '$referralBase?u=$uid';

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
