import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/rt_resilient.dart';
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
  // Grace emit kosong (anti list kedip hilang) — lihat _onUsers.
  Timer? _emptyGrace;
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
        // Dedupe by uid + buang row tanpa uid — cache lama (sebelum fix
        // chat_service save tanpa 'uid') bisa berisi row uid='' yang membuat
        // kartu sendiri tidak terfilter & dedupe kacau → user tampil 2x.
        final seenUids = <String>{};
        final seenNicks = <String>{};
        var diskUsers = <UserModel>[];
        for (final e in cached) {
          final uid = '${e['uid'] ?? e['id'] ?? ''}';
          if (uid.isEmpty || !seenUids.add(uid)) continue;
          final u = UserModel.fromMap(uid, Map<String, dynamic>.from(e));
          // Row uid='' lama disimpan tanpa uid — dedupe per nickname sebagai
          // pertahanan kedua supaya 2 row sama tidak dirender 2 kartu.
          final nk = u.nickname.toLowerCase();
          if (!seenNicks.add(nk)) continue;
          diskUsers.add(u);
        }
        // Batch-load avatar base64 per-uid dari kv — _persistAvatars menulis
        // tiap sesi TAPI tidak pernah dibaca balik saat cold start, sehingga
        // _diskAvatars selalu kosong dan avatar selalu flash dari inisial.
        // Dengan ini frame pertama langsung foto (tanpa placeholder huruf).
        try {
          final avatars = await Future.wait(
            diskUsers.map((u) => u.uid.isEmpty
                ? Future.value(<String>['', ''])
                : MessageCache.instance
                    .loadRawObj('avatar:${u.uid}')
                    .then((m) => <String>[u.uid, '${m['a'] ?? ''}'],
                        onError: (_) => <String>[u.uid, ''])),
          );
          for (final e in avatars) {
            if (e[0].isNotEmpty && e[1].isNotEmpty) {
              _diskAvatars[e[0]] = e[1];
            }
          }
          diskUsers = diskUsers.map((u) {
            final a = _diskAvatars[u.uid];
            return (a != null && _isRenderableAvatar(a))
                ? u.copyWith(avatar: a)
                : u;
          }).toList();
        } catch (_) {}
        if (_users.isEmpty) {
          // Disk menang race → tampilkan langsung list disk (deduped di atas),
          // tapi tetap lewat sort bucket supaya frame pertama sudah rapi
          // (online di atas, paling lama offline di bawah).
          // Avatar resolve via _AsyncAvatar (disk-first, keepProvider).
          _users = _reorderStable([], diskUsers);
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

  /// Rank status untuk urutan kartu: online paling atas, lalu idle,
  /// lalu offline/lainnya paling bawah.
  int _statusRank(String s) {
    if (s == 'online') return 0;
    if (s == 'idle') return 1;
    return 2;
  }

  /// Urutan kartu: online di atas, lalu idle, lalu offline — di dalam
  /// bucket yang sama yang paling lama tidak online paling bawah
  /// (lastSeen terlama).
  /// Anti-kedip: posisi dalam bucket yang sama DIPERTAHANKAN antar-emission
  /// (heartbeat tiap 120 dtk mengubah lastSeen user aktif — tanpa ini kartu
  /// online bertukar posisi terus). Kartu hanya pindah saat status bucket-nya
  /// berubah (baru online naik, baru offline turun), atau user baru muncul
  /// (menempel di ujung bucket-nya, urut lastSeen desc antar sesama baru).
  List<UserModel> _reorderStable(List<UserModel> prev, List<UserModel> next) {
    int cmpUser(UserModel a, UserModel b) {
      final r = _statusRank(a.status).compareTo(_statusRank(b.status));
      if (r != 0) return r;
      return b.lastSeen.compareTo(a.lastSeen);
    }

    // Load pertama (belum ada posisi): sort penuh bucket + lastSeen desc.
    if (prev.isEmpty) {
      final sorted = List<UserModel>.of(next);
      sorted.sort(cmpUser);
      return sorted;
    }
    final byUid = {for (final u in next) u.uid: u};
    final prevByUid = {for (final u in prev) u.uid: u};
    // 1) User lama yang bucket-nya TETAP: update data, posisi dipertahankan.
    final buckets = <List<UserModel>>[[], [], []];
    for (final u in prev) {
      final updated = byUid.remove(u.uid);
      if (updated == null) continue; // hilang dari stream → buang
      final old = prevByUid[u.uid]!;
      if (_statusRank(old.status) == _statusRank(updated.status)) {
        buckets[_statusRank(updated.status)].add(updated);
      } else {
        // 2) Status bucket BERUBAH: masuk antrean pindah (di bawah).
        byUid[u.uid] = updated;
      }
    }
    // 3) Pindahan + pendatang baru: urut lastSeen desc, tempel di ujung
    // bucket-nya (baru online = bawah section online, dst — tidak
    // menggeser kartu lama yang sudah stabil).
    final moved = byUid.values.toList()..sort(cmpUser);
    for (final u in moved) {
      buckets[_statusRank(u.status)].add(u);
    }
    return [...buckets[0], ...buckets[1], ...buckets[2]];
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
    // Resilient: error channel me-restart subscription otomatis (dulu:
    // list online freeze sampai restart).
    _sub = listenResilient<List<UserModel>>(
      () => _service.getOnlineUsers(),
      _onUsers,
      isDisposed: () => _disposed,
      onError: (e) {
        dlog('[OnlineUsersProvider] stream error: $e');
        _loaded = true;
        _error = e.toString();
        if (!_disposed) notifyListeners();
      },
    );
  }

  void _onUsers(List<UserModel> users) {
        _loaded = true;
        // ── ANTI-HILANG-SEMUA (grace period emit kosong) ──
        // Fast-path presence bisa emit KOSONG sesaat (belum sync) — dulu
        // itu menimpa list yang sudah terisi → seluruh list kedip hilang,
        // muncul lagi saat RPC slow path balik. Sekarang: emit kosong saat
        // list terisi ditahan 8 detik; emit berisi sebelum timer habis
        // membatalkannya (nol kedip). Timer habis = memang sepi sungguhan.
        if (users.isEmpty && _users.isNotEmpty) {
          _emptyGrace?.cancel();
          _emptyGrace = Timer(const Duration(seconds: 8), () {
            if (_disposed || _users.isNotEmpty) return;
            _debounce?.cancel();
            _error = null;
            if (!_disposed) notifyListeners();
          });
          return;
        }
        if (users.isNotEmpty) {
          // Emit berisi datang → batalkan pending kosong.
          _emptyGrace?.cancel();
          _emptyGrace = null;
        }
        // Dedupe by uid + buang row tanpa uid — pertahanan terhadap duplikat
        // dari stream maupun cache disk berformat lama (uid='').
        final seen = <String>{};
        var deduped = users
            .where((u) => u.uid.isNotEmpty && seen.add(u.uid))
            .toList();
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
    _emptyGrace?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
