import 'dart:async';
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
  final Set<String> _bgRefreshed = {};
  static const _maxCache = 100;

  /// Kembalikan base64 avatar user ('' jika tidak ada / gagal).
  /// Urutan: RAM → DISK (instan, anti-kedip) → network. Disk ditulis
  /// saat upload (setForUid) maupun setelah fetch network berhasil.
  Future<String> get(String uid) async {
    if (uid.isEmpty) return '';
    final cached = _cache[uid];
    if (cached != null) return cached;
    // DISK dulu — sesi sebelumnya sudah simpan → tampil tanpa network.
    // Tunggu prewarm siap dulu (bounded) supaya tidak salah vonis
    // disk-miss lalu fetch network sia-sia saat boot. Background refresh
    // jalan supaya perubahan dari device lain tersusul di kunjungan
    // berikutnya.
    try {
      await MediaDiskCache.instance.waitReady();
      final disk = MediaDiskCache.instance.readSync('avatars/$uid.jpg');
      if (disk != null && disk.isNotEmpty) {
        final b64 = base64Encode(disk);
        if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
        _cache[uid] = b64;
        if (_bgRefreshed.add(uid)) unawaited(_refreshInBackground(uid));
        return b64;
      }
    } catch (_) {}
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
      // Simpan disk — sesi berikutnya instan tanpa network.
      if (avatar.isNotEmpty) {
        try {
          await MediaDiskCache.instance.write(
            'avatars/$uid.jpg',
            Uint8List.fromList(base64Decode(avatar)),
          );
        } catch (_) {}
      }
      return avatar;
    } catch (e) {
      _cache[uid] = '';
      return '';
    } finally {
      _inflight.remove(uid);
    }
  }

  /// Fetch ulang avatar satu uid di background (fire-and-forget) —
  /// hanya update RAM+disk, tidak me-repaint UI sesi ini.
  Future<void> _refreshInBackground(String uid) async {
    if (_inflight.contains(uid)) return;
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
      if (avatar.isNotEmpty) {
        try {
          await MediaDiskCache.instance.write(
            'avatars/$uid.jpg',
            Uint8List.fromList(base64Decode(avatar)),
          );
        } catch (_) {}
      }
    } catch (_) {
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
    // Fetch serentak untuk path yang sama: antre bounded (bukan '' langsung)
    // supaya pemanggil tanpa retry (FutureBuilder timeline) tetap dapat
    // hasil asli, bukan fallback permanen.
    if (_inflight.contains(path)) {
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final done = _pathCache[path];
        if (done != null) return done;
        if (!_inflight.contains(path)) break;
      }
      return _pathCache[path] ?? '';
    }
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
