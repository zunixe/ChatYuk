import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
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

  Future<void> _loadDisk() async {
    try {
      // Cold start: tampilkan cache disk dulu (<50ms) sebelum fetch network.
      // Avatar di-merge dari kv per-uid (sama seperti pesan foto) supaya
      // list langsung tampil FOTO — bukan inisial → tidak ada pop-in blink.
      final cached = await MessageCache.instance.loadRawList('online_users');
      if (cached.isNotEmpty && _users.isEmpty) {
        try {
          _users = cached
              .map((e) => UserModel.fromMap(
                  '${e['uid'] ?? e['id'] ?? ''}', Map<String, dynamic>.from(e)))
              .toList();
          await _mergeAvatarsFromDisk();
          _loaded = true;
          notifyListeners();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Gabungkan avatar tersimpan (kv per-uid) ke list — cold start instan.
  Future<void> _mergeAvatarsFromDisk() async {
    if (_users.isEmpty) return;
    for (int i = 0; i < _users.length; i++) {
      if (_users[i].avatar.isNotEmpty) continue;
      try {
        final obj = await MessageCache.instance.loadRawObj('avatar:${_users[i].uid}');
        final a = obj['a'] as String?;
        if (a != null && a.isNotEmpty) {
          _users[i] = _users[i].copyWith(avatar: a);
        }
      } catch (_) {}
    }
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
        if (_users.isNotEmpty) {
          final prev = {for (final u in _users) u.uid: u.avatar};
          deduped = deduped
              .map((u) {
                final old = prev[u.uid];
                if (old == null || old.isEmpty) return u;
                final newIsEmptyOrPath = u.avatar.isEmpty ||
                    u.avatar.startsWith('avatars/');
                return newIsEmptyOrPath ? u.copyWith(avatar: old) : u;
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
            _users = deduped;
            _error = null;
            notifyListeners();
          });
          return;
        }
        _debounce?.cancel();
        _users = deduped;
        _error = null;
        notifyListeners();
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
        notifyListeners();
      },
    );
  }

  void updateAvatarForUid(String uid, String base64) {
    final idx = _users.indexWhere((u) => u.uid == uid);
    if (idx >= 0 && _users[idx].avatar != base64) {
      _users[idx] = _users[idx].copyWith(avatar: base64);
      _persistAvatars([_users[idx]]);
      notifyListeners();
    }
  }

  void removeAvatarForUid(String uid) {
    final idx = _users.indexWhere((u) => u.uid == uid);
    if (idx >= 0 && _users[idx].avatar.isNotEmpty) {
      _users[idx] = _users[idx].copyWith(avatar: '');
      _avatarWritten.remove(uid);
      MessageCache.instance.removeRawObj('avatar:$uid');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
