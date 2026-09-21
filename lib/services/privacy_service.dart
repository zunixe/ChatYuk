import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/privacy_settings.dart';

class PrivacyService {
  final SupabaseClient _sb;
  PrivacyService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  Future<PrivacySettings> fetch() async {
    final res = await _sb.rpc('my_privacy_settings');
    return PrivacySettings.fromMap(
      res is Map ? Map<String, dynamic>.from(res) : const {},
    );
  }

  Future<PrivacySettings> update({
    PrivacyVisibility? presence,
    PrivacyVisibility? lastSeen,
    PrivacyVisibility? profilePhoto,
    PrivacyVisibility? about,
    PrivacyVisibility? story,
    bool? readReceipts,
  }) async {
    final res = await _sb.rpc(
      'update_privacy_settings',
      params: {
        'p_presence': presence?.wireKey,
        'p_last_seen': lastSeen?.wireKey,
        'p_profile_photo': profilePhoto?.wireKey,
        'p_about': about?.wireKey,
        'p_story': story?.wireKey,
        'p_read_receipts': readReceipts,
      },
    );
    return PrivacySettings.fromMap(
      res is Map ? Map<String, dynamic>.from(res) : const {},
    );
  }

  Future<PrivacySettings> replaceExclusions(
    String field,
    Set<String> uids,
  ) async {
    final res = await _sb.rpc(
      'replace_privacy_exclusions',
      params: {'p_field': field, 'p_uids': uids.toList()},
    );
    return PrivacySettings.fromMap(
      res is Map ? Map<String, dynamic>.from(res) : const {},
    );
  }

  /// Daftar yang bisa dikecualikan untuk opsi "kecuali...": TEMAN (mutual
  /// follow — definisi sama dengan `privacy_can_view`) + ANON yang pernah
  /// chat dengan saya. Dipakai picker baik untuk "Semua kecuali" maupun
  /// "Teman kecuali".
  Future<List<Map<String, dynamic>>> excludableUsers() async {
    if (_sb.auth.currentUser?.id == null) return const [];
    try {
      final res = await _sb.rpc('privacy_excludable_users');
      if (res is List) {
        return res
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }
}
