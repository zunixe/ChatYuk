import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/media_disk_cache.dart';
import '../services/message_cache.dart';

bool _usersEqual(List<UserModel> a, List<UserModel> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].uid != b[i].uid ||
        a[i].status != b[i].status ||
        a[i].lastSeen != b[i].lastSeen ||
        a[i].avatar != b[i].avatar)
      return false;
  }
  return true;
}

class OnlineUsersProvider extends ChangeNotifier {
  bool _disposed = false;

  final ChatService _service = ChatService();
  List<UserModel> _users = [];
  StreamSubscription? _sub;
  String? _error;
  bool _loaded = false;
  Timer? _debounce;
  Completer<void>? _warmCompleter;

  List<UserModel> get users => _users;
  String? get error => _error;
  bool get hasLoaded => _loaded;

  /// Tunggu disk cache siap (SQLite + Keystore) — dipakai auth gate supaya
  /// skeleton tetap tampil sampai data hangat, tanpa blink abu skeleton.
  Future<void> warmup() {
    final existing = _warmCompleter;
    if (existing != null) return existing.future;
    final c = Completer<void>();
    _warmCompleter = c;
    _loadDisk().whenComplete(() {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  /// Avatar dari disk (kv per-uid) — fallback PERMANEN untuk emission
  /// stream yang avatarnya masih path/kosong. Diisi sekali oleh _loadDisk,
  /// dipakai merge stream kapan pun disk selesai (stream bisa menang race).
  final Map<String, String> _diskAvatars = {};

  Future<void> _loadDisk() async {
    // Warm-up MediaDiskCache SEBELUM apa pun — readSync butuh _docs siap.
    await MediaDiskCache.instance.prewarm();
    try {
      // Cold start: tampilkan cache disk dulu (<50ms) sebelum fetch network.
      // SKIP avatar batch load di cold start — _AsyncAvatar resolve dari
      // disk sendiri, tidak perlu dimuat ke _diskAvatars dulu. Ini memotong
      // _loadDisk dari ~6s jadi ~1s di Xiaomi cold start.
      final cached = await MessageCache.instance.loadRawList('online_users');
      if (cached.isNotEmpty) {
        final diskUsers = cached
            .map((e) => UserModel.fromMap(
                '${e['uid'] ?? e['id'] ?? ''}', Map<String, dynamic>.from(e)))
            .toList();
        if (_users.isEmpty) {
          // Disk menang race → tampilkan langsung list disk.
          // Avatar resolve via _AsyncAvatar (disk-first, keepProvider).
          _users = diskUsers;
        } else {
          // Stream menang race → jangan buang hasil disk.
        }
      }
      // SELALU tandai loaded — walau cache kosong (skeleton jangan
      // menggantung menunggu network).
      _loaded = true;
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  bool _isRenderableAvatar(String a) =>
      a.isNotEmpty && !a.startsWith('avatars/');

  /// Bekukan urutan kartu: posisi dari [_users] dipertahankan, emission
  /// baru hanya menambah user baru di bawah & membuang yang tak lagi online.
  /// Dulu: sort last_seen desc tiap emission → kartu pindah posisi → terlihat
  /// kedip/refresh padahal fotonya stabil.
  List<UserModel> _reorderStable(List<UserModel> prev, List<UserModel> next) {
    if (prev.isEmpty) return next;
    final byUid = {for (final u in next) u.uid: u};
    final result = <UserModel>[];
    // 1) Posisi lama dipertahankan (in-place update data).
    for (final u in prev) {
      final updated = byUid.remove(u.uid);
      if (updated != null) result.add(updated);
    }
    // 2) User baru (belum ada posisi) ditambahkan di bawah.
    for (final u in next) {
      final exists = result.any((r) => r.uid == u.uid);
      if (!exists) result.add(u);
    }
    return result;
  }

  /// Simpan avatar per-uid ke kv (fire-and-forget). Hanya tulis kalau avatar
  /// BERUBAH dari yang terakhir ditulis sesi ini — hemat IO, avatar lama
  /// yang sama tidak ditulis ulang tiap emit stream.
  final Map<String, String> _avatarWritten = {};
  void _persistAvatars(List<UserModel> users) {
    for (final u in users) {
      if (u.uid.isEmpty || u.avatar.isEmpty) continue;
      if (_avatarWritten[u.uid] == u.avatar) continue;
      _avatarWritten[u.uid] = u.avatar;
      _diskAvatars[u.uid] = u.avatar;
      MessageCache.instance.saveRawObj('avatar:${u.uid}', {'a': u.avatar});
    }
  }

  OnlineUsersProvider() {
    unawaited(warmup());
    _sub = _service.getOnlineUsers().listen(
      (users) {
        _loaded = true;
        // Dedupe by uid — pertahanan kedua terhadap duplikat dari stream.
        final seen = <String>{};
        var deduped = users.where((u) => seen.add(u.uid)).toList();
        // Merge monotonic: stream bisa emit fast-path TANPA avatar (belum
        // terdownload) setelah emit dengan avatar — tanpa ini foto yang
        // sudah tampil tertimpa kosong lalu balik lagi = kedip-kedip.
        // Avatar lama dipertahankan selama yang baru kosong ATAU masih
        // path storage (avatars/… — belum jadi base64 siap tampil).
        // Fallback kedua: avatar disk (_diskAvatars) — cover emission awal
        // cold start saat _users masih kosong/path (stream menang race).
        if (_users.isNotEmpty) {
          final prev = {for (final u in _users) u.uid: u.avatar};
          deduped = deduped
              .map((u) {
                final newIsEmptyOrPath = !_isRenderableAvatar(u.avatar);
                if (!newIsEmptyOrPath) return u;
                final old = prev[u.uid];
                if (old != null && _isRenderableAvatar(old)) {
                  return u.copyWith(avatar: old);
                }
                final disk = _diskAvatars[u.uid];
                if (disk != null && disk.isNotEmpty) {
                  return u.copyWith(avatar: disk);
                }
                return u;
              })
              .toList();
        } else if (_diskAvatars.isNotEmpty) {
          deduped = deduped
              .map((u) {
                if (_isRenderableAvatar(u.avatar)) return u;
                final disk = _diskAvatars[u.uid];
                return (disk != null && disk.isNotEmpty)
                    ? u.copyWith(avatar: disk)
                    : u;
              })
              .toList();
        }
        if (_usersEqual(_users, deduped)) return;
        // Debounce avatar-only churn di cold start (fast 50→ slow 100→ avatar batch 20)
        // biar list tidak rebuild 3-4x beruntun yang terlihat kedip.
        final isAvatarOnlyChange = _users.length == deduped.length &&
            _users.isNotEmpty &&
            _users.every((old) {
              final idx = deduped.indexWhere((n) => n.uid == old.uid);
              if (idx < 0) return false;
              final n = deduped[idx];
              return old.status == n.status && old.lastSeen == n.lastSeen;
            });
        if (isAvatarOnlyChange) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 180), () {
            _users = _reorderStable(_users, deduped);
            _error = null;
            if (!_disposed) notifyListeners();
          });
          return;
        }
        _debounce?.cancel();
        _users = _reorderStable(_users, deduped);
        _error = null;
        if (!_disposed) notifyListeners();
        // Simpan ke disk untuk cold start berikutnya (tanpa avatar base64 biar kecil).
        // Avatar disimpan TERPISAH per-uid (kv terenkripsi, pola sama seperti
        // pesan foto) supaya cold start langsung tampil foto — tanpa pop-in
        // dan tanpa download ulang dari network (network hanya bawa update).
        if (deduped.isNotEmpty) {
          final rows = deduped.map((u) => {'uid': u.uid, ...u.toMap(), 'avatar': ''}).toList();
          MessageCache.instance.saveRawList('online_users', rows);
          _persistAvatars(deduped);
        }
      },
      onError: (e) {
        debugPrint('[OnlineUsersProvider] stream error: $e');
        _loaded = true;
        _error = e.toString();
        if (!_disposed) notifyListeners();
      },
    );
  }

  void updateAvatarForUid(String uid, String base64) {
    final idx = _users.indexWhere((u) => u.uid == uid);
    if (idx >= 0 && _users[idx].avatar != base64) {
      _users[idx] = _users[idx].copyWith(avatar: base64);
      _persistAvatars([_users[idx]]);
      if (!_disposed) notifyListeners();
    }
  }

  void removeAvatarForUid(String uid) {
    final idx = _users.indexWhere((u) => u.uid == uid);
    if (idx >= 0 && _users[idx].avatar.isNotEmpty) {
      _users[idx] = _users[idx].copyWith(avatar: '');
      _avatarWritten.remove(uid);
      _diskAvatars.remove(uid);
      MessageCache.instance.removeRawObj('avatar:$uid');
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
