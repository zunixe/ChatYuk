import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/media_disk_cache.dart';
import '../../core/cache/message_cache.dart';
import '../../core/perf/perf_probe.dart';
import '../../models/user_model.dart';
import '../../services/chat_service.dart';
import '../../services/rt_resilient.dart';
import '../../utils.dart';

bool _usersEqual(List<UserModel> a, List<UserModel> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].uid != b[i].uid ||
        a[i].status != b[i].status ||
        a[i].lastSeen != b[i].lastSeen ||
        a[i].avatar != b[i].avatar) {
      return false;
    }
  }
  return true;
}

/// State daftar online (immutable).
class OnlineUsersState {
  final List<UserModel> users;
  final String? error;
  final bool loaded;
  final int? totalRegistered;
  final int? totalAnon;
  final Set<String> hiddenUids;

  const OnlineUsersState({
    this.users = const [],
    this.error,
    this.loaded = false,
    this.totalRegistered,
    this.totalAnon,
    this.hiddenUids = const {},
  });

  int get hiddenCount => hiddenUids.length;
  bool isHidden(String uid) => hiddenUids.contains(uid);
  bool get hasLoaded => loaded;
}

/// Daftar user online (Riverpod) — migrasi dari ChangeNotifier.
/// Logika sama persis (debounce commit, hold-grace, empty-grace, disk).
/// Global (persist sepanjang sesi).
class OnlineUsersNotifier extends Notifier<OnlineUsersState> {
  final ChatService _service;

  OnlineUsersNotifier({ChatService? service})
      : _service = service ?? ChatService();

  List<UserModel> _users = [];
  StreamSubscription? _sub;
  String? _error;
  bool _loaded = false;
  Timer? _debounce;
  Timer? _emptyGrace;
  final Map<String, DateTime> _holdSince = {};
  Timer? _holdSweep;
  static const _holdGrace = Duration(seconds: 10);

  @visibleForTesting
  static DateTime Function() holdNow = DateTime.now;
  Completer<void>? _warmCompleter;

  int? _totalRegistered;
  int? _totalAnon;

  final Set<String> _hiddenUids = {};
  String? _ownerUid;

  final Map<String, String> _diskAvatars = {};
  final Map<String, String> _avatarWritten = {};

  @override
  OnlineUsersState build() {
    ref.onDispose(_disposeAll);
    unawaited(warmup());
    _sub = listenResilient<List<UserModel>>(
      () => _service.getOnlineUsers(),
      _onUsers,
      isDisposed: () => false,
      onError: (e) {
        dlog('[OnlineUsersProvider] stream error: $e');
        _loaded = true;
        _error = e.toString();
        _emit();
      },
    );
    return const OnlineUsersState();
  }

  void _emit() {
    state = OnlineUsersState(
      users: List.unmodifiable(_users),
      error: _error,
      loaded: _loaded,
      totalRegistered: _totalRegistered,
      totalAnon: _totalAnon,
      hiddenUids: Set.unmodifiable(_hiddenUids),
    );
  }

  // ── Getter kompat (baca aksi tanpa watch) ──
  List<UserModel> get users => _users;
  String? get error => _error;
  bool get hasLoaded => _loaded;
  int? get totalRegistered => _totalRegistered;
  int? get totalAnon => _totalAnon;
  bool isHidden(String uid) => _hiddenUids.contains(uid);
  int get hiddenCount => _hiddenUids.length;
  Set<String> get hiddenUids => Set.unmodifiable(_hiddenUids);
  Future<void> get warmFuture => warmup();

  Future<void> fetchUserCounts() async {
    if (_totalRegistered != null) return;
    final c = await _service.userCounts();
    if (c == null) return;
    _totalRegistered = c.registered;
    _totalAnon = c.anon;
    _emit();
  }

  String _hiddenKeyFor(String owner) => 'hidden_online_$owner';

  Future<void> setOwner(String? uid) async {
    if (_ownerUid == uid) return;
    _ownerUid = uid;
    _hiddenUids.clear();
    if (uid == null || uid.isEmpty) {
      _emit();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_hiddenKeyFor(uid)) ?? const [];
      for (final id in list) {
        if (id.isNotEmpty) _hiddenUids.add(id);
      }
    } catch (_) {}
    _emit();
  }

  Future<void> _saveHidden() async {
    final owner = _ownerUid;
    if (owner == null || owner.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_hiddenKeyFor(owner), _hiddenUids.toList());
    } catch (_) {}
  }

  Future<void> hideUser(String uid) async {
    if (uid.isEmpty || _hiddenUids.contains(uid)) return;
    _hiddenUids.add(uid);
    _emit();
    await _saveHidden();
  }

  Future<void> unhideUser(String uid) async {
    if (!_hiddenUids.remove(uid)) return;
    _emit();
    await _saveHidden();
  }

  @visibleForTesting
  void setHiddenForTest(Set<String> uids) {
    _hiddenUids
      ..clear()
      ..addAll(uids);
  }

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
    await MediaDiskCache.instance.prewarm();
    try {
      final cached = await PerfProbe.timed(
        'online.diskLoad',
        () => MessageCache.instance.loadRawList('online_users'),
      );
      if (cached.isNotEmpty) {
        final seenUids = <String>{};
        final seenNicks = <String>{};
        var diskUsers = <UserModel>[];
        for (final e in cached) {
          final uid = '${e['uid'] ?? e['id'] ?? ''}';
          if (uid.isEmpty || !seenUids.add(uid)) continue;
          final u = UserModel.fromMap(uid, Map<String, dynamic>.from(e));
          final nk = u.nickname.toLowerCase();
          if (!seenNicks.add(nk)) continue;
          diskUsers.add(u);
        }
        if (_users.isEmpty) {
          diskUsers = diskUsers
              .where((u) => ChatService.isVisibleOnline(u.status, u.lastSeen))
              .toList();
          _users = _reorderStable([], diskUsers);
          _loaded = true;
          _emit();
          unawaited(_loadDiskAvatars(diskUsers));
          return;
        }
      }
      _loaded = true;
      _emit();
    } catch (_) {}
  }

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
      final streamWon =
          _users.any((u) => !diskUsers.any((d) => d.uid == u.uid));
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
        _emit();
      }
    } catch (_) {}
  }

  bool _isRenderableAvatar(String a) =>
      a.isNotEmpty && !a.startsWith('avatars/');

  int _statusRank(String s) {
    if (s == 'online') return 0;
    if (s == 'idle') return 1;
    return 2;
  }

  List<UserModel> _reorderStable(List<UserModel> prev, List<UserModel> next) {
    int cmpUser(UserModel a, UserModel b) {
      final r = _statusRank(a.status).compareTo(_statusRank(b.status));
      if (r != 0) return r;
      return b.lastSeen.compareTo(a.lastSeen);
    }

    final sorted = List<UserModel>.of(next);
    sorted.sort(cmpUser);
    return sorted;
  }

  void _persistAvatars(List<UserModel> users) {
    for (final u in users) {
      if (u.uid.isEmpty || u.avatar.isEmpty) continue;
      if (_avatarWritten[u.uid] == u.avatar) continue;
      _avatarWritten[u.uid] = u.avatar;
      _diskAvatars[u.uid] = u.avatar;
      MessageCache.instance.saveRawObj('avatar:${u.uid}', {'a': u.avatar});
    }
  }

  void resubscribeOnline() {
    _sub?.cancel();
    _sub = listenResilient<List<UserModel>>(
      () => _service.getOnlineUsers(),
      _onUsers,
      isDisposed: () => false,
      onError: (e) {
        dlog('[OnlineUsersProvider] stream error: $e');
        _loaded = true;
        _error = e.toString();
        _emit();
      },
    );
  }

  void _onUsers(List<UserModel> users) {
    _loaded = true;
    if (users.isEmpty && _users.isNotEmpty) {
      _emptyGrace?.cancel();
      _emptyGrace = Timer(const Duration(seconds: 8), () {
        _debounce?.cancel();
        _users = [];
        _error = null;
        _emit();
      });
      return;
    }
    if (users.isNotEmpty) {
      _emptyGrace?.cancel();
      _emptyGrace = null;
    }

    final seen = <String>{};
    var deduped =
        users.where((u) => u.uid.isNotEmpty && seen.add(u.uid)).toList();
    final emittedBad = <String>{
      for (final u in deduped)
        if (!ChatService.isVisibleOnline(u.status, u.lastSeen)) u.uid,
    };
    deduped = deduped
        .where((u) => ChatService.isVisibleOnline(u.status, u.lastSeen))
        .toList();
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

  static const Duration _avatarDebounce = Duration(milliseconds: 180);
  static const Duration _statusDebounce = Duration(milliseconds: 32);

  void _scheduleCommit(List<UserModel> next, Duration delay) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      PerfProbe.notifyCount('onlineUsers');
      _users = _reorderStable(_users, next);
      _error = null;
      _emit();
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
      _emit();
    }
  }

  void removeAvatarForUid(String uid) {
    final idx = _users.indexWhere((u) => u.uid == uid);
    if (idx >= 0 && _users[idx].avatar.isNotEmpty) {
      _users[idx] = _users[idx].copyWith(avatar: '');
      _avatarWritten.remove(uid);
      _diskAvatars.remove(uid);
      MessageCache.instance.removeRawObj('avatar:$uid');
      _emit();
    }
  }

  void _armHoldSweep() {
    _holdSweep?.cancel();
    if (_holdSince.isEmpty) return;
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
    if (_holdSince.isEmpty) return;
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
    if (_users.length != before) _emit();
    _armHoldSweep();
  }

  void _disposeAll() {
    _debounce?.cancel();
    _emptyGrace?.cancel();
    _holdSweep?.cancel();
    _sub?.cancel();
  }
}

final onlineUsersProvider =
    NotifierProvider<OnlineUsersNotifier, OnlineUsersState>(
        OnlineUsersNotifier.new);
