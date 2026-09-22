import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils.dart';
import '../core/cache/media_disk_cache.dart';
import 'storage_photo_service.dart';

/// Avatar base64 by uid dengan cache — dipakai list chat & header chat
/// supaya foto profil user lain tampil (avatar = path storage atau base64).
///
/// Urutan cache: RAM → DISK (MediaDiskCache, per serverPath) → network.
/// Setelah download dari network, bytes ditulis ke disk — buka app
/// berikutnya avatar tampil instan tanpa network (anti-blink).
class AvatarB64Service {
  /// Client opsional (LAZY) — test menyuntik client palsu.
  final SupabaseClient? _injected;
  AvatarB64Service._([SupabaseClient? sb]) : _injected = sb;

  static AvatarB64Service instance = AvatarB64Service._();

  @visibleForTesting
  factory AvatarB64Service.forTest(SupabaseClient sb) =>
      AvatarB64Service._(sb);

  @visibleForTesting
  static void overrideInstance(AvatarB64Service s) => instance = s;

  @visibleForTesting
  static void restoreInstance() => instance = AvatarB64Service._();

  SupabaseClient get _sb => _injected ?? SupabaseConfig.client;

  final Map<String, String> _cache = {};
  final Map<String, String> _pathCache = {};
  // Job in-flight per-uid: caller kedua MENUNGGU hasil yang sama, bukan
  // dapat '' instan (dulu `if (_inflight.contains(uid)) return ''` bikin
  // avatar kedip-hilang saat dua widget minta uid yang sama bersamaan).
  final Map<String, Future<String>> _uidJobs = {};
  final Set<String> _bgRefreshed = {};
  // In-flight dedup: caller kedua MENUNGGU hasil yang sama, bukan return
  // '' instan — dulu penyebab race "inisial → foto" saat halaman profil
  // mem-fetch avatar yang sama dari 2 titik sekaligus.
  final Map<String, Future<String>> _pathJobs = {};
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
        if (_bgRefreshed.add(uid)) {
          // Cap: set ini dedupe bg-refresh per-uid tapi tidak pernah dibersihkan
          // → tumbuh 1 entry per user yang pernah dilihat. Bounded FIFO.
          if (_bgRefreshed.length > _maxCache) {
            _bgRefreshed.remove(_bgRefreshed.first);
          }
          unawaited(_refreshInBackground(uid));
        }
        return b64;
      }
    } catch (_) {}
    // Dedup: caller kedua menunggu job yang sama (bukan '' instan).
    final job = _uidJobs[uid];
    if (job != null) return job;
    final future = _fetchUid(uid);
    _uidJobs[uid] = future;
    try {
      return await future;
    } finally {
      _uidJobs.remove(uid);
    }
  }

  /// Fetch avatar 1 uid dari RPC ber-privacy + download bila path.
  Future<String> _fetchUid(String uid) async {
    try {
      // Kolom profiles.avatar sudah di-revoke dari SELECT publik (hardening
      // 2026-09-22) → baca lewat RPC ber-privacy avatar_for.
      var avatar = await _sb.rpc('avatar_for', params: {'p_uid': uid}) as String?;
      avatar ??= '';
      if (avatar.isNotEmpty &&
          StoragePhotoService.instance.isAvatarPath(avatar)) {
        avatar = await _downloadWithDisk(avatar);
      }
      // HANYA simpan hasil berisi — '' (gagal sesaat) tidak boleh dihafal
      // permanen, kalau tidak avatar "hilang" sampai app di-restart.
      if (avatar.isNotEmpty && _cache.length < _maxCache) _cache[uid] = avatar;
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
      return '';
    }
  }

  /// Fetch ulang avatar satu uid di background (fire-and-forget) —
  /// hanya update RAM+disk, tidak me-repaint UI sesi ini.
  Future<void> _refreshInBackground(String uid) async {
    if (_uidJobs.containsKey(uid)) return;
    final future = _fetchUid(uid);
    _uidJobs[uid] = future;
    try {
      await future;
    } finally {
      _uidJobs.remove(uid);
    }
  }

  /// Clear cache untuk uid tertentu (dipanggil saat avatar di-update)
  /// agar fetch berikutnya dapat avatar yang baru.
  void clearForUid(String uid) {
    _cache.remove(uid);
    _pathCache.remove('avatars/$uid.jpg');
    _uidJobs.remove(uid);
    _pathJobs.remove('avatars/$uid.jpg');
  }

  /// Clear cache untuk path tertentu (avatar path berubah / dihapus)
  void clearForPath(String path) {
    _pathCache.remove(path);
    _pathJobs.remove(path);
  }

  /// Batch prefetch avatar untuk banyak uid sekaligus (1 query `in` ganti
  /// N+1 select per-uid). Dipakai daftar user (leaderboard, social, dll)
  /// supaya tiap kartu tak memicu query sendiri. Fire-and-forget: yang
  /// sudah ada di cache dilewati; hasil masuk RAM+disk lewat setForUid.
  Future<void> prefetch(List<String> uids) async {
    final need = uids
        .where((u) => u.isNotEmpty && !_cache.containsKey(u))
        .toSet()
        .toList();
    if (need.isEmpty) return;
    try {
      // Cek disk dulu (instan) supaya tidak query yang sudah tersedia lokal.
      await MediaDiskCache.instance.waitReady();
      final missing = <String>[];
      for (final uid in need) {
        final disk = MediaDiskCache.instance.readSync('avatars/$uid.jpg');
        if (disk != null && disk.isNotEmpty) {
          final b64 = base64Encode(disk);
          if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
          _cache[uid] = b64;
        } else {
          missing.add(uid);
        }
      }
      if (missing.isEmpty) return;
      // RPC batch ber-privacy (avatar di-mask sesuai profile_photo_visibility).
      final res = await _sb.rpc('avatars_for', params: {'p_uids': missing});
      for (final row in (res as List? ?? const [])) {
        final uid = '${(row as Map)['id'] ?? ''}';
        var avatar = '${row['avatar'] ?? ''}';
        if (uid.isEmpty) continue;
        if (avatar.isNotEmpty &&
            StoragePhotoService.instance.isAvatarPath(avatar)) {
          avatar = await _downloadWithDisk(avatar);
        }
      if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
      // HANYA simpan hasil berisi — '' (gagal sesaat) tidak boleh dihafal
      // permanen, kalau tidak avatar "hilang" sampai app di-restart.
      if (avatar.isNotEmpty) _cache[uid] = avatar;
      }
    } catch (e) {
      dlog('[avatar] prefetch error: $e');
    }
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
    // Tunggu prewarm disk siap (bounded) — tanpa ini `read` bisa throw saat
    // boot sehingga avatar gagal padahal filenya ada di disk.
    try {
      await MediaDiskCache.instance.waitReady();
    } catch (_) {}
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
    final job = _pathJobs[path];
    if (job != null) return job;
    final future = _downloadPath(path);
    _pathJobs[path] = future;
    return future;
  }

  Future<String> _downloadPath(String path) async {
    try {
      final b64 = await _downloadWithDisk(path);
      // HANYA cache hasil yang BERISI. Kegagalan ('' karena jaringan putus
      // sesaat / media-cache belum siap) TIDAK boleh dihafal permanen —
      // dulu `_pathCache[path] = ''` di catch membuat avatar "hilang" sampai
      // app di-restart (gejala: kadang muncul kadang ilang).
      if (b64.isNotEmpty) {
        if (_pathCache.length >= _maxCache) {
          _pathCache.remove(_pathCache.keys.first);
        }
        _pathCache[path] = b64;
      }
      return b64;
    } catch (_) {
      return '';
    } finally {
      _pathJobs.remove(path);
    }
  }
}
