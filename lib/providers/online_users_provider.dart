import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/rt_resilient.dart';
import '../services/media_disk_cache.dart';
import '../services/message_cache.dart';
import '../services/perf_probe.dart';

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

  final ChatService _service;
  List<UserModel> _users = [];
  StreamSubscription? _sub;
  String? _error;
  bool _loaded = false;
  Timer? _debounce;
  // Grace emit kosong (anti list kedip hilang) — lihat _onUsers.
  Timer? _emptyGrace;
  // Hold-grace per user (anti SATU user kedip hilang-muncul): emission
  // fast-path presence-only / socket blip bisa menghilangkan user idle
  // sekilas padahal last_seen masih segar (< 30 mnt). Uid → kapan mulai
  // hilang dari emission. Sweep di bawah melepasnya bila lewat grace.
  final Map<String, DateTime> _holdSince = {};
  Timer? _holdSweep;
  static const _holdGrace = Duration(seconds: 90);
  // Jam hold-grace — non-final supaya test bisa memakai jam palsu
  // (FakeAsync TIDAK memalsukan DateTime.now; prinsip sama seperti
  // jitterRandom di rt_resilient.dart).
  @visibleForTesting
  static DateTime Function() holdNow = DateTime.now;
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
      final cached = await PerfProbe.timed(
        'online.diskLoad',
        () => MessageCache.instance.loadRawList('online_users'),
      );
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
        // Batch-load avatar base64 per-uid dari kv sudah dipindah ke
        // `_loadDiskAvatars` (dipanggil setelah list tampil — lihat bawah).
        if (_users.isEmpty) {
          // Saring baris basi (invisible/offline/last_seen basi) dari cache
          // lama — jangan tampilkan akun yang sudah tidak online.
          diskUsers = diskUsers
              .where((u) => ChatService.isVisibleOnline(u.status, u.lastSeen))
              .toList();
          // ── TAMPILKAN LIST DULU, AVATAR MENYUSUL (fix #6) ──
          // Dulu batch avatar di-`await` SEBELUM list dipasang, sehingga
          // frame pertama menunggu N pembacaan kv (satu per uid). List tanpa
          // foto masih jauh lebih baik daripada list yang belum muncul —
          // `_AsyncAvatar` sudah resolve sendiri dari disk saat render.
          // Jadi: pasang list sekarang, lalu isi avatar di latar.
          _users = _reorderStable([], diskUsers);
          _loaded = true;
          if (!_disposed) notifyListeners();
          unawaited(_loadDiskAvatars(diskUsers));
          return;
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

  /// Muat avatar base64 dari disk untuk [diskUsers] di LATAR (setelah list
  /// tampil), lalu emit sekali bila ada yang berubah. Non-blocking: kegagalan
  /// apa pun diabaikan karena `_AsyncAvatar` tetap punya fallback inisial.
  Future<void> _loadDiskAvatars(List<UserModel> diskUsers) async {
    try {
      final avatars = await Future.wait(
        diskUsers.map((u) => u.uid.isEmpty
            ? Future.value(<String>['', ''])
            : MessageCache.instance
                .loadRawObj('avatar:${u.uid}')
                .then((m) => <String>[u.uid, '${m['a'] ?? ''}'],
                    onError: (_) => <String>[u.uid, ''])),
      );
      if (_disposed) return;
      // Guard balapan: kalau stream sudah mengisi list (atau disk sudah
      // tidak lagi jadi sumber), jangan sentuh `_users` — cukup simpan
      // avatar ke `_diskAvatars` supaya merge berikutnya ikut memakainya.
      final streamWon = _users.any((u) => !diskUsers.any((d) => d.uid == u.uid));
      for (final e in avatars) {
        if (e[0].isNotEmpty && e[1].isNotEmpty) {
          _diskAvatars[e[0]] = e[1];
        }
      }
      if (streamWon) return;
      var changed = false;
      final next = _users.map((u) {
        final a = _diskAvatars[u.uid];
        if (a != null && _isRenderableAvatar(a) && u.avatar != a) {
          changed = true;
          return u.copyWith(avatar: a);
        }
        return u;
      }).toList();
      if (changed) {
        _users = next;
        notifyListeners();
      }
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

  /// Buka-ulang subscription online (dipanggil saat app resume) —
  /// socket realtime bisa mati diam-diam saat background; controller
  /// baru = initial sync + timer segar, user yang baru online langsung
  /// terlihat tanpa harus keluar-masuk app.
  void resubscribeOnline() {
    if (_disposed) return;
    _sub?.cancel();
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

  OnlineUsersProvider({ChatService? service})
      : _service = service ?? ChatService() {
    unawaited(warmup());
    // Resilient: error channel me-restart subscription otomatis (dulu:
    // list online freeze sampai restart).
    _sub = listenResilient<List<UserModel>>(      () => _service.getOnlineUsers(),
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
            if (_disposed) return;
            // Timer habis = memang sepi sungguhan: bersihkan list basi
            // (mis. semua user jadi invisible/offline) supaya akun yang
            // sudah tidak online tidak nempel selamanya.
            _debounce?.cancel();
            _users = [];
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
        // Baris invisible/offline/basi tidak boleh masuk daftar tayang
        // (maupun cache disk di bawah) — lapis pertahanan terakhir.
        // Catat uid yang HADIR tapi gugur filter (offline eksplisit) agar
        // hold-grace di bawah tidak menahannya (beda dengan hilang/blip).
        final emittedBad = <String>{
          for (final u in deduped)
            if (!ChatService.isVisibleOnline(u.status, u.lastSeen)) u.uid,
        };
        deduped = deduped
            .where((u) => ChatService.isVisibleOnline(u.status, u.lastSeen))
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
        // Tahan user yang hilang dari emission: status terakhir terlihat
        // (online/idle) + last_seen segar + baru hilang < grace → sisipkan
        // kembali (posisi & avatar lama ikut, tanpa rebuild bila tak berubah).
        // Trade-off: yang benar-benar offline ikut tertahan s.d. grace.
        final now = holdNow();
        final incoming = {for (final u in deduped) u.uid};
        _holdSince.removeWhere((uid, _) => incoming.contains(uid));
        _holdSince.removeWhere(
          (uid, since) => now.difference(since) >= _holdGrace,
        );
        for (final old in _users) {
          if (incoming.contains(old.uid)) continue;
          if (emittedBad.contains(old.uid)) {
            _holdSince.remove(old.uid);
            continue;
          }
          if (_holdSince.containsKey(old.uid)) {
            deduped.add(old);
            continue;
          }
          if (old.status != 'online' && old.status != 'idle') continue;
          if (!ChatService.isVisibleOnline(old.status, old.lastSeen)) {
            continue;
          }
          _holdSince[old.uid] = now;
          deduped.add(old);
        }
        _armHoldSweep();
        if (_usersEqual(_users, deduped)) return;
        // ── SATU JALUR COMMIT (anti 2× notify berurutan) ──
        // Dulu ada 2 jalur: debounce 180ms untuk avatar-only churn, dan
        // jalur langsung untuk perubahan lain. Keduanya bisa jalan berurutan
        // (mis. emit avatar-only lalu emit status) → 2 notifyListeners() →
        // halaman di-rebuild 2× dalam satu frame.
        //
        // Sekarang SEMUA perubahan lewat satu debounce. Delay-nya dibedakan:
        // - avatar-only churn → 180ms (cold start: fast 50 → slow 100 →
        //   avatar batch 20; ditahan supaya list tidak kedip 3-4×).
        // - perubahan nyata (status/anggota berubah) → 32ms, cukup untuk
        //   menggabungkan beberapa emission yang datang hampir bersamaan
        //   TANPA terasa lag (setara 2 frame @120Hz).
        final isAvatarOnlyChange = _users.length == deduped.length &&
            _users.isNotEmpty &&
            _users.every((old) {
              final idx = deduped.indexWhere((n) => n.uid == old.uid);
              if (idx < 0) return false;
              final n = deduped[idx];
              return old.status == n.status && old.lastSeen == n.lastSeen;
            });
        _scheduleCommit(
          deduped,
          isAvatarOnlyChange ? _avatarDebounce : _statusDebounce,
        );
  }

  /// Debounce terpisah untuk dua sifat perubahan (lihat _onUsers).
  static const Duration _avatarDebounce = Duration(milliseconds: 180);
  static const Duration _statusDebounce = Duration(milliseconds: 32);

  /// Satu-satunya tempat yang menulis `_users` + notify + simpan disk.
  /// Dipanggil lewat debounce supaya burst emission jadi SATU rebuild.
  void _scheduleCommit(List<UserModel> next, Duration delay) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      if (_disposed) return;
      PerfProbe.notifyCount('onlineUsers');
      _users = _reorderStable(_users, next);
      _error = null;
      if (!_disposed) notifyListeners();
      // Simpan ke disk untuk cold start berikutnya (tanpa avatar base64 biar
      // kecil). Avatar disimpan TERPISAH per-uid (kv terenkripsi, pola sama
      // seperti pesan foto) supaya cold start langsung tampil foto — tanpa
      // pop-in dan tanpa download ulang dari network.
      if (next.isNotEmpty) {
        final rows =
            next.map((u) => {'uid': u.uid, ...u.toMap(), 'avatar': ''}).toList();
        MessageCache.instance.saveRawList('online_users', rows);
        _persistAvatars(next);
      }
    });
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

  /// Jadwalkan sapu hold-grace pada deadline terdekat (tanpa emission
  /// baru pun user yang lewat grace tetap dilepas).
  void _armHoldSweep() {
    _holdSweep?.cancel();
    if (_holdSince.isEmpty || _disposed) return;
    final now = holdNow();
    var wait = _holdGrace;
    for (final since in _holdSince.values) {
      final remain = _holdGrace - now.difference(since);
      if (remain < wait) wait = remain;
    }
    if (wait <= Duration.zero) {
      _sweepHolds();
      return;
    }
    _holdSweep = Timer(wait, _sweepHolds);
  }

  void _sweepHolds() {
    _holdSweep = null;
    if (_disposed || _holdSince.isEmpty) return;
    final now = holdNow();
    final expired = <String>{};
    _holdSince.removeWhere((uid, since) {
      if (now.difference(since) >= _holdGrace) {
        expired.add(uid);
        return true;
      }
      return false;
    });
    if (expired.isEmpty) {
      _armHoldSweep();
      return;
    }
    final before = _users.length;
    _users = _users.where((u) => !expired.contains(u.uid)).toList();
    if (_users.length != before && !_disposed) notifyListeners();
    _armHoldSweep();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _emptyGrace?.cancel();
    _holdSweep?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
