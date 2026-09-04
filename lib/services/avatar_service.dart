import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';
import 'media_disk_cache.dart';
import 'storage_photo_service.dart';

/// Avatar base64 by uid dengan cache — dipakai list chat & header chat
/// supaya foto profil user lain tampil (avatar = path storage atau base64).
///
/// Urutan cache: RAM → DISK (MediaDiskCache, per serverPath) → network.
/// Setelah download dari network, bytes ditulis ke disk — buka app
/// berikutnya avatar tampil instan tanpa network (anti-blink).
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
        avatar = await _downloadWithDisk(avatar);
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
    // Tulis disk — sesi berikutnya avatar tetap tersedia tanpa network.
    if (base64.isNotEmpty) {
      try {
        MediaDiskCache.instance.write(
          path,
          Uint8List.fromList(base64Decode(base64)),
        );
      } catch (_) {}
    }
  }

  void setForPath(String path, String base64) {
    if (path.isEmpty) return;
    if (_pathCache.length >= _maxCache) _pathCache.remove(_pathCache.keys.first);
    _pathCache[path] = base64;
    if (base64.isNotEmpty) {
      try {
        MediaDiskCache.instance.write(
          path,
          Uint8List.fromList(base64Decode(base64)),
        );
      } catch (_) {}
    }
  }

  /// Download path → base64, DISK FIRST (instan untuk sesi berikutnya).
  Future<String> _downloadWithDisk(String path) async {
    final disk = await MediaDiskCache.instance.read(path);
    if (disk != null && disk.isNotEmpty) {
      return base64Encode(disk);
    }
    final b64 = await StoragePhotoService.instance.download(path) ?? '';
    if (b64.isNotEmpty) {
      try {
        await MediaDiskCache.instance.write(
          path,
          Uint8List.fromList(base64Decode(b64)),
        );
      } catch (_) {}
    }
    return b64;
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
      final b64 = await _downloadWithDisk(path);
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
