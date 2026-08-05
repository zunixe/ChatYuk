import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://fohcucyyejdryryoxitm.supabase.co';
  static const String anonKey = 'sb_publishable_aFQQbXscy1mqVq5jHX7p2w_wzs2GAKg';

  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
