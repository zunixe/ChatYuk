import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils.dart';

/// Data ringan profil (nama + gender) untuk KARTU KONTAK.
///
/// Sengaja HANYA nama + gender: avatar mengikuti cache avatar (yang sudah
/// menghormati pengaturan privasi foto) dan nomor telepon TIDAK pernah diambil
/// — payload kontak ChatYuk hanya berisi uid.
class ProfileLite {
  final String name;
  final String gender;
  const ProfileLite(this.name, this.gender);
}

class ProfileLiteService {
  static const int _ttlSec = 600;
  static const int _maxEntries = 500;

  final Map<String, ProfileLite> _cache = {};
  final Map<String, DateTime> _at = {};

  SupabaseClient get _sb => Supabase.instance.client;

  Future<ProfileLite?> forUid(String uid) async {
    if (uid.isEmpty) return null;
    final cached = _cache[uid];
    final at = _at[uid];
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at).inSeconds < _ttlSec) {
      return cached;
    }
    try {
      final row = await _sb
          .from('profiles')
          .select('nickname,gender')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      final p = ProfileLite('${row['nickname'] ?? ''}', '${row['gender'] ?? ''}');
      _cache[uid] = p;
      _at[uid] = DateTime.now();
      if (_cache.length > _maxEntries) {
        _cache.clear();
        _at.clear();
      }
      return p;
    } catch (e) {
      dlog('[ProfileLite] error: $e');
      return null;
    }
  }
}
