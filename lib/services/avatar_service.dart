import '../config/supabase_config.dart';
import 'storage_photo_service.dart';

/// Avatar base64 by uid dengan cache — dipakai list chat & header chat
/// supaya foto profil user lain tampil (avatar = path storage atau base64).
class AvatarB64Service {
  AvatarB64Service._();
  static final instance = AvatarB64Service._();

  final Map<String, String> _cache = {};
  final Map<String, String> _pathCache = {};
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
      if (avatar.isNotEmpty &&
          StoragePhotoService.instance.isAvatarPath(avatar)) {
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

  /// Clear cache untuk uid tertentu (dipanggil saat avatar di-update)
  /// agar fetch berikutnya dapat avatar yang baru.
  /// Path `avatars/$uid.jpg` selalu sama → harus clear _pathCache juga
  /// kalau tidak getByPath return base64 lama.
  void clearForUid(String uid) {
    _cache.remove(uid);
    _pathCache.remove('avatars/$uid.jpg');
    _inflight.remove(uid);
    _inflight.remove('avatars/$uid.jpg');
  }

  /// Clear cache untuk path tertentu (avatar path berubah / dihapus)
  void clearForPath(String path) {
    _pathCache.remove(path);
    _inflight.remove(path);
  }

  void setForUid(String uid, String base64) {
    if (uid.isEmpty) return;
    if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
    _cache[uid] = base64;
    final path = 'avatars/$uid.jpg';
    if (_pathCache.length >= _maxCache) _pathCache.remove(_pathCache.keys.first);
    _pathCache[path] = base64;
  }

  void setForPath(String path, String base64) {
    if (path.isEmpty) return;
    if (_pathCache.length >= _maxCache) _pathCache.remove(_pathCache.keys.first);
    _pathCache[path] = base64;
  }

  /// Ambil avatar langsung dari path storage (tanpa query profil) —
  /// dipakai timeline yang sudah membawa authorAvatar di payload.
  Future<String> getByPath(String path) async {
    if (path.isEmpty) return '';
    final cached = _pathCache[path];
    if (cached != null) return cached;
    if (_inflight.contains(path)) return '';
    _inflight.add(path);
    try {
      var b64 = await StoragePhotoService.instance.download(path) ?? '';
      if (_pathCache.length >= _maxCache)
        _pathCache.remove(_pathCache.keys.first);
      _pathCache[path] = b64;
      return b64;
    } catch (_) {
      _pathCache[path] = '';
      return '';
    } finally {
      _inflight.remove(path);
    }
  }
}
