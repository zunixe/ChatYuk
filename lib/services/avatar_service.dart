import '../config/supabase_config.dart';
import 'storage_photo_service.dart';

/// Avatar base64 by uid dengan cache — dipakai list chat & header chat
/// supaya foto profil user lain tampil (avatar = path storage atau base64).
class AvatarB64Service {
  AvatarB64Service._();
  static final instance = AvatarB64Service._();

  final Map<String, String> _cache = {};
  final Set<String> _inflight = {};
  static const _maxCache = 100;

  /// Kembalikan base64 avatar user ('' jika tidak ada / gagal).
  Future<String> get(String uid) async {
    if (uid.isEmpty) return '';
    final cached = _cache[uid];
    if (cached != null) return cached;
    if (_inflight.contains(uid)) return '';
    _inflight.add(uid);
    try {
      final res = await SupabaseConfig.client
          .from('profiles')
          .select('avatar')
          .eq('id', uid)
          .maybeSingle();
      var avatar = (res?['avatar'] as String?) ?? '';
      if (avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(avatar)) {
        avatar = await StoragePhotoService.instance.download(avatar) ?? '';
      }
      if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
      _cache[uid] = avatar;
      return avatar;
    } catch (e) {
      _cache[uid] = '';
      return '';
    } finally {
      _inflight.remove(uid);
    }
  }
}
