part of 'chat_service.dart';

/// Domain **presence** — pisah dari monolit ChatService (Fase 4).
/// Satu library (`part`): field privat `ChatBase` tetap bisa diakses,
/// member mixin jadi bagian interface `ChatService` (mock aman).
mixin ChatServicePresenceMx on ChatBase {
  Future<String?> _fetchInvisibleUid() async {
    final last = _invisibleFetchedAt;
    if (last != null &&
        DateTime.now().difference(last).inMinutes < 5) {
      return _invisibleUidCache;
    }
    try {
      final setting = await _sb
          .from('app_settings')
          .select('invisible_enabled,invisible_admin_uid')
          .eq('id', 'global')
          .maybeSingle()
          .timeout(const Duration(seconds: 2));
      _invisibleFetchedAt = DateTime.now();
      final enabled = setting?['invisible_enabled'];
      if (enabled == true) {
        final v = setting?['invisible_admin_uid'];
        _invisibleUidCache = v is String ? v : null;
      } else {
        _invisibleUidCache = null;
      }
    } catch (_) {}
    return _invisibleUidCache;
  }

  Future<String?> _fetchOwnCountry() async {
    if (_ownCountryCache != null) return _ownCountryCache;
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) return null;
      final row = await _sb
          .from('profiles')
          .select('country')
          .eq('id', me)
          .maybeSingle()
          .timeout(const Duration(seconds: 2));
      final c = (row?['country'] as String?)?.trim();
      if (c != null && c.isNotEmpty) _ownCountryCache = c;
    } catch (_) {}
    return _ownCountryCache;
  }

  /// Stream status realtime satu user (online/idle/offline).
  /// Pakai channel postgres changes pada profiles — ringan, hanya 1 row.
  /// Status dihitung efektif: last_seen basi (> 30 menit) dianggap offline,
  /// supaya sinkron dengan daftar pengguna online di list chat.
  /// [initialStatus] membuat stream langsung emit status yang sudah diketahui
  /// (misal dari profil yang baru di-fetch) tanpa query DB tambahan.
  Stream<String> getUserStatus(String uid, {String? initialStatus}) {
    final controller = StreamController<String>.broadcast();
    String _current = initialStatus ?? 'offline';
    if (initialStatus != null && initialStatus != 'offline') {
      Future.microtask(() {
        if (!controller.isClosed) controller.add(_current);
      });
    }

    Future<void> fetchStatus() async {
      try {
        // Kolom status/last_seen sudah di-revoke dari SELECT publik (hardening
        // 2026-09-22) → baca lewat RPC ber-privacy presence_for.
        final res = await measuredRpc(_sb, 
          'presence_for',
          params: {
            'p_uids': [uid],
          },
        );
        final list = res is List ? res : <dynamic>[];
        if (list.isEmpty || controller.isClosed) return;
        final row = Map<String, dynamic>.from(list.first as Map);
        final s = ChatService.effectiveStatusOf(
          row['status'] as String?,
          row['last_seen'] as String?,
        );
        if (s != _current) {
          _current = s;
          controller.add(_current);
        }
      } catch (e) {
        dlog('[chat] fetchStatus error: $e');
      }
    }

    // Nama channel harus UNIK per instance — 2 screen bisa menonton user
    // T3b (2026-10-11): SATU channel realtime per uid + refcount penonton.
    // Dulu nama channel pakai instanceId unik tiap subscribe → banyak channel
    // untuk uid sama (chat + info + list) = overhead join & boros. Sekarang
    // channel dibagi; callback meneruskan status ke SEMUA controller uid itu.
    final uidControllers = _statusControllers.putIfAbsent(
      uid,
      () => <StreamController<String>>[],
    );
    uidControllers.add(controller);
    _statusChannelRefs[uid] = (_statusChannelRefs[uid] ?? 0) + 1;

    var channel = _statusChannels[uid];
    if (channel == null) {
      channel = _sb.channel('user-status-$uid');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'profiles',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: uid,
        ),
        callback: (payload) {
          final s = ChatService.effectiveStatusOf(
            payload.newRecord['status'] as String?,
            payload.newRecord['last_seen'] as String?,
          );
          for (final c in List<StreamController<String>>.from(
            _statusControllers[uid] ?? const [],
          )) {
            if (!c.isClosed) c.add(s);
          }
        },
      );
      channel.subscribe((status, err) {
        if (err != null) dlog('[Presence] status realtime error: $err');
      });
      _statusChannels[uid] = channel;
    }
    if (initialStatus == null) fetchStatus();

    controller.onCancel = () {
      // Keluar dari daftar controller uid ini.
      final list = _statusControllers[uid];
      if (list != null) {
        list.remove(controller);
        if (list.isEmpty) _statusControllers.remove(uid);
      }
      // Refcount: putus channel hanya saat penonton TERAKHIR lepas.
      final refs = (_statusChannelRefs[uid] ?? 1) - 1;
      if (refs <= 0) {
        _statusChannelRefs.remove(uid);
        final ch = _statusChannels.remove(uid);
        if (ch != null) _sb.removeChannel(ch);
      } else {
        _statusChannelRefs[uid] = refs;
      }
    };
    return controller.stream;
  }

  /// Ambil last_seen satu user (untuk "terakhir dilihat" di header chat).
  /// Lewat RPC presence_for (kolom last_seen sudah di-revoke dari publik).
  Future<DateTime?> getUserLastSeen(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final res = await measuredRpc(_sb, 
        'presence_for',
        params: {
          'p_uids': [uid],
        },
      );
      final list = res is List ? res : <dynamic>[];
      if (list.isEmpty) return null;
      final v = (list.first as Map)['last_seen'] as String?;
      return v == null ? null : DateTime.tryParse(v)?.toLocal();
    } catch (e) {
      dlog('[chat] getUserLastSeen error: $e');
      return null;
    }
  }

  /// Total user (agregat): {registered, anon} dari RPC publik `user_counts`.
  /// Untuk header menu Online. Gagal → null (UI menyembunyikan baris ini).
  Future<({int registered, int anon})?> userCounts() async {
    try {
      final res = await measuredRpc(_sb, 'user_counts');
      if (res is Map) {
        return (
          registered: (res['registered'] as num?)?.toInt() ?? 0,
          anon: (res['anon'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (e) {
      dlog('[chat] userCounts error: $e');
    }
    return null;
  }

  Stream<List<UserModel>> getOnlineUsers() {
    final controller = StreamController<List<UserModel>>.broadcast();
    List<UserModel> cached = [];
    Timer? debounce;
    // Map uid→path dibangun ulang tiap stream dibuka — tanpa clear, tumbuh
    // seumur instance (1 entry per user yang pernah online).
    _onlinePathByUid.clear();
    // Coalesce fallback: kapan sync terakhir jalan (sumber mana pun).
    DateTime? lastSyncAt;

    Future<void> syncFromPresence() async {
      lastSyncAt = DateTime.now();
      try {
        final state = RealtimeHub.instance.onlinePresenceState;
        // Fast path per-country shard: ambil max 50 uid tanpa expand full O(N) (jangan values.expand untuk 1M)
        List<String> firstNPresenceUids(int n) {
          final out = <String>[];
          for (final list in state.values) {
            for (final m in list as List) {
              final uid = '${(m as Map)['uid'] ?? ''}';
              if (uid.isEmpty) continue;
              out.add(uid);
              if (out.length >= n) return out;
            }
            if (out.length >= n) break;
          }
          return out;
        }

        final presenceUidsFast = firstNPresenceUids(50);
        if (presenceUidsFast.isNotEmpty) {
          try {
            // status/avatar/last_seen sudah di-revoke dari SELECT publik →
            // ambil lewat RPC ber-privacy presence_for (bukan profiles mentah).
            final res = await _sb
                .rpc('presence_for', params: {'p_uids': presenceUidsFast})
                .timeout(const Duration(seconds: 3));
            final fastRows = res is List
                ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                : <Map<String, dynamic>>[];
            if (fastRows.isNotEmpty && !controller.isClosed) {
              // Emit cepat dari presence
              final seenFast = <String>{};
              final pendingFast = <UserModel>[];
              for (final row in fastRows) {
                try {
                  var u = UserModel.fromMap('${row['id']}', snakeToCamel(row));
                  if (!seenFast.add(u.uid)) continue;
                  // Invisible/offline/basi tidak ikut emission cepat.
                  if (!ChatService.isVisibleOnline(u.status, u.lastSeen)) continue;
                  if (u.avatar.isNotEmpty &&
                      StoragePhotoService.instance.isAvatarPath(u.avatar)) {
                    _onlinePathByUid[u.uid] = u.avatar;
                  }
                  if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
                    final cachedB64 = ChatService.avatarB64Peek(u.avatar);
                    if (cachedB64 != null && cachedB64.isNotEmpty) {
                      u = u.copyWith(avatar: cachedB64);
                    } else {
                      // Belum ada b64 di cache: pakai avatar dari emission
                      // sebelumnya (per uid) — string avatar tidak berubah
                      // antar-emission → tidak memicu decode ulang/blink.
                      final prev = cached.where((c) => c.uid == u.uid).firstOrNull;
                      if (prev != null && prev.avatar.isNotEmpty &&
                          !StoragePhotoService.instance.isAvatarPath(prev.avatar)) {
                        u = u.copyWith(avatar: prev.avatar);
                      }
                    }
                  } else if (u.avatar.isEmpty) {
                    final prev = cached.where((c) => c.uid == u.uid).firstOrNull;
                    if (prev != null && prev.avatar.isNotEmpty &&
                        !StoragePhotoService.instance.isAvatarPath(prev.avatar)) {
                      u = u.copyWith(avatar: prev.avatar);
                    }
                  }
                  pendingFast.add(u);
                } catch (_) {}
              }
              if (pendingFast.isNotEmpty) {
                // Urutan SAMA dengan RPC (last_seen desc) — emission awal dan
                // emission RPC tidak memindahkan posisi card di layar.
                pendingFast.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
                cached = List.of(pendingFast);
                if (!controller.isClosed) controller.add(List.unmodifiable(cached));
                // Background download avatar batch (sama seperti slow path).
                // Lewati path yang sudah ada di cache avatar (tidak download
                // ulang tiap tick); index via Map biar O(1), bukan indexWhere.
                const avatarBatch = 20;
                bool avatarUpdated = false;
                final cachedIdx = <String, int>{
                  for (var k = 0; k < cached.length; k++) cached[k].uid: k,
                };
                for (var i = 0; i < pendingFast.length; i += avatarBatch) {
                  final chunk = pendingFast.skip(i).take(avatarBatch).toList();
                  final results = await Future.wait(chunk.map((u) async {
                    if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
                      final hit = ChatService.avatarB64Peek(u.avatar);
                      if (hit != null && hit.isNotEmpty) {
                        return u.copyWith(avatar: hit);
                      }
                      final b64 = await _avatarB64(u.avatar);
                      if (b64.isNotEmpty) return u.copyWith(avatar: b64);
                    }
                    return u;
                  }));
                  for (var j = 0; j < chunk.length; j++) {
                    final idx = cachedIdx[chunk[j].uid] ?? -1;
                    if (idx >= 0 && results[j].avatar != cached[idx].avatar) {
                      cached[idx] = results[j];
                      avatarUpdated = true;
                    }
                  }
                }
                if (avatarUpdated) {
                  if (!controller.isClosed) controller.add(List.unmodifiable(cached));
                }
              }
            }
          } catch (_) {}
        }
        // Coba RPC ringan dulu (1 RTT, server-side, tanpa IN 500).
        // K6 skala: global limit 200 + merge shard country sendiri
        // (index per-country) — user sekota selalu terlihat walau
        // >200 online global bersamaan; user baru online (last_seen
        // terbaru) selalu masuk top list.
        List<dynamic> rpcRows = [];
        bool usedRpc = false;
        bool rpcFailed = false;
        try {
          final data = await PerfProbe.timed(
            'online.rpc',
            () => _sb
                .rpc('get_online_users', params: {'p_limit': 200})
                // 6s (dulu 2s): timeout 2s terbukti memutus RPC di jaringan
                // HP ber-blip → catch menelan error → jatuh ke fallback
                // presence_for yang HANYA memuat user ber-socket → dummy AI
                // (tanpa socket) hilang dari daftar padahal online.
                .timeout(const Duration(seconds: 6)),
          );
          if (data is List && data.isNotEmpty) {
            rpcRows = data;
            usedRpc = true;
          } else if (data is List) {
            // RPC sukses tapi kosong = memang sepi. Jangan tandai gagal.
            usedRpc = true;
          }
        } catch (e) {
          rpcFailed = true;
          dlog('[ONLINE-EMIT] RPC FAILED: $e');
        }
        // Merge shard country sendiri (ringan, index per-country) — menutup
        // celah user yang tidak masuk top-200 global.
        try {
          final ownCountry = await _fetchOwnCountry();
          if (ownCountry != null && ownCountry.isNotEmpty) {
            final local = await PerfProbe.timed(
              'online.rpcCountry',
              () => _sb
                  .rpc('get_online_users', params: {
                    'p_country': ownCountry,
                    'p_limit': 100,
                  })
                  .timeout(const Duration(seconds: 2)),
            );
            if (local is List && local.isNotEmpty) {
              final ids = rpcRows.map((r) => '${r['id'] ?? ''}').toSet();
              for (final r in local) {
                if (!ids.contains('${r['id'] ?? ''}')) rpcRows.add(r);
              }
              if (rpcRows.isNotEmpty) usedRpc = true;
            }
          }
        } catch (_) {}
        List<dynamic> rows;
        if (usedRpc) {
          // ── PRESENCE CROSS-REFERENCE ────────────────────────────────────
          // RPC return user berdasarkan DB (status + last_seen). Kalau app
          // di-kill tanpa lifecycle event, profiles.status tetap 'online'/
          // 'idle' dan last_seen masih fresh → user zombie muncul di list.
          final presenceUids = <String>{};
          for (final list in state.values) {
            for (final m in list) {
              final uid = '${(m as Map)['uid'] ?? ''}';
              if (uid.isNotEmpty) presenceUids.add(uid);
            }
          }
          rows = ChatService.filterRpcOnlineRows(rpcRows, presenceUids);
        } else if (rpcFailed && cached.isNotEmpty) {
          // RPC gagal/timeout TAPI kita sudah punya list dari RPC sebelumnya
          // (berisi user DB termasuk dummy tanpa socket). JANGAN jatuh ke
          // fallback presence_for: jalur itu hanya memuat user ber-socket,
          // sehingga dummy AI yang online akan hilang begitu saja. Pertahankan
          // cache; tick 30s berikutnya akan memperbarui saat jaringan pulih.
          return;
        } else {
          // Fallback hybrid lama jika RPC get_online_users belum deploy/gagal.
          // status/last_seen sudah di-revoke dari SELECT publik → jalur
          // dbUids lama TIDAK mungkin; pakai presence_for (ber-privacy) atas
          // uid yang memang punya presence realtime saja.
          final uids = firstNPresenceUids(50);
          if (uids.isEmpty) {
            // Jangan kosongkan list yang sudah tampil (emit kosong bikin
            // list online kedip hilang-muncul) — biarkan fallback tick
            // yang mengoreksi kalau memang sepi sungguhan.
            return;
          }
          String? invisibleUid2 = await _fetchInvisibleUid();
          final filtered2 = invisibleUid2 == null
              ? uids
              : uids.where((id) => id != invisibleUid2).toList();
          if (filtered2.isEmpty) {
            return;
          }
          final res = await _sb
              .rpc('presence_for', params: {'p_uids': filtered2})
              .timeout(const Duration(seconds: 6));
          rows = res is List
              ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : <Map<String, dynamic>>[];
        }
        // Invisible filter untuk path RPC juga (cache 5 mnt, bukan per tick)
        String? invisibleUid = await _fetchInvisibleUid();
        if (invisibleUid != null) {
          rows = rows.where((r) => '${(r as Map)['id']}' != invisibleUid).toList();
        }
        final seen = <String>{};
        final pending = <UserModel>[];
        for (final row in rows) {
          try {
            var u = UserModel.fromMap('${row['id']}', snakeToCamel(row));
            if (!seen.add(u.uid)) continue;
            // Invisible/offline/basi tidak ikut daftar tayang & cache.
            if (!ChatService.isVisibleOnline(u.status, u.lastSeen)) continue;
            if (u.avatar.isNotEmpty &&
                StoragePhotoService.instance.isAvatarPath(u.avatar)) {
              _onlinePathByUid[u.uid] = u.avatar;
            }
            if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
              final cachedB64 = ChatService.avatarB64Peek(u.avatar);
              if (cachedB64 != null && cachedB64.isNotEmpty) {
                u = u.copyWith(avatar: cachedB64);
              } else {
                final prev = cached.where((c) => c.uid == u.uid).firstOrNull;
                if (prev != null && prev.avatar.isNotEmpty &&
                    !StoragePhotoService.instance.isAvatarPath(prev.avatar)) {
                  u = u.copyWith(avatar: prev.avatar);
                }
              }
            } else if (u.avatar.isEmpty) {
              final prev = cached.where((c) => c.uid == u.uid).firstOrNull;
              if (prev != null && prev.avatar.isNotEmpty &&
                  !StoragePhotoService.instance.isAvatarPath(prev.avatar)) {
                u = u.copyWith(avatar: prev.avatar);
              }
            }
            pending.add(u);
          } catch (e) {
            dlog('[getOnlineUsers] skip bad row: $e');
          }
        }
        // Progressive: emit dulu tanpa avatar (instant), avatar nyusul background
        pending.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
        // Anti-hilang-semua: hasil slow path KOSONG saat cache sebelumnya
        // terisi → jangan timpa (kemungkinan network blip), biarkan
        // fallback tick retry. Timer grace di provider sebagai lapis 2.
        if (pending.isEmpty && cached.isNotEmpty) {
          return;
        }
        cached = List.of(pending);
        // Simpan kv list online: avatar = SERVER PATH (ringan). Bytes foto
        // sudah ada di MediaDiskCache per path — cold start berikutnya
        // memuat foto dari disk, tanpa network.
        try {
          final rows = pending
              .map((u) => {'uid': u.uid, ...u.toMap(), 'avatar': _onlinePathByUid[u.uid] ?? ''})
              .toList();
          if (rows.isNotEmpty) {
            MessageCache.instance.saveRawList('online_users', rows);
          }
        } catch (_) {}
        if (!controller.isClosed) controller.add(List.unmodifiable(cached));
        // Background download avatar batch 20 (index Map O(1)).
        const avatarBatch = 20;
        bool avatarUpdated = false;
        final cachedIdx2 = <String, int>{
          for (var k = 0; k < cached.length; k++) cached[k].uid: k,
        };
        for (var i = 0; i < pending.length; i += avatarBatch) {
          final chunk = pending.skip(i).take(avatarBatch).toList();
          final results = await Future.wait(chunk.map((u) async {
            if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
              final b64 = await _avatarB64(u.avatar);
              if (b64.isNotEmpty) return u.copyWith(avatar: b64);
            }
            return u;
          }));
          for (var j = 0; j < chunk.length; j++) {
            final idx = cachedIdx2[chunk[j].uid] ?? -1;
            if (idx >= 0 && results[j].avatar != cached[idx].avatar) {
              cached[idx] = results[j];
              avatarUpdated = true;
            }
          }
        }
        if (avatarUpdated && !controller.isClosed) controller.add(List.unmodifiable(cached));
      } catch (e) {
        dlog('[getOnlineUsers] presence fetch error: $e');
        if (!controller.isClosed) controller.addError(e);
      }
    }

    final sub = RealtimeHub.instance.onlinePresence.listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 1200), syncFromPresence);
    }, onError: (e) {
      // OFFLINE: presence stream error → jangan tak tertangkap.
      dlog('[getOnlineUsers] presence stream error: $e');
    });
    // Realtime profiles UPDATE: user lain yang baru online (termasuk dummy
    // yang di-set dari admin panel — tanpa device/presence) harus langsung
    // muncul di daftar. Dulu: sync hanya via presence event sendiri +
    // fallback saat list kosong → perubahan status dari admin terlihat
    // sangat terlambat.
    final profileSyncSub = _sb
        .channel('online-list-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            if (controller.isClosed) return;
            final st = payload.newRecord['status'] as String?;
            final changedUid = '${payload.newRecord['id'] ?? ''}';
            // Realtime OFFLINE: user (termasuk dummy tanpa presence socket
            // yang di-offline-kan tick server) langsung dibuang dari list
            // tayang — tanpa menunggu full resync. Idempoten: uid yang
            // memang tak ada di list = no-op. Event online/idle di bawah
            // tetap full resync seperti semula.
            if (ChatService.shouldDropOnlineUid(st)) {
              if (changedUid.isNotEmpty &&
                  cached.any((c) => c.uid == changedUid)) {
                cached = cached.where((c) => c.uid != changedUid).toList();
                if (!controller.isClosed) {
                  controller.add(List.unmodifiable(cached));
                }
              }
              return;
            }
            // Hanya re-sync saat ada yang masuk jadi online/idle.
            if (st != 'online' && st != 'idle') return;
            final ls = DateTime.tryParse(
              '${payload.newRecord['last_seen'] ?? ''}',
            );
            if (ls == null) return;
            if (ls.toUtc().isBefore(
              DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
            )) {
              return;
            }
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 1200), syncFromPresence);
          },
        )
        .subscribe((status, err) {
          if (err != null) dlog('[Presence] online realtime error: $err');
        });
    // initial sync — DEFER: RPC get_online_users bisa ~1.5s (query DB berat).
    // Dulu dipanggil langsung saat stream dibuka → menyerobot frame pertama
    // layar Online/chat (jank build max ~324ms terukur). Tunda 400ms supaya
    // frame pertama bersih; list tetap tampil dulu dari cache disk (provider).
    Timer(const Duration(milliseconds: 400), syncFromPresence);
    // also periodic fallback if presence empty (cold start before track)
    // + TRUTH-CHECK berkala: socket realtime bisa mati diam-diam (blip
    // jaringan) sehingga event join/update tidak pernah sampai — dulu
    // tick hanya jalan saat cache kosong → user baru online tidak muncul
    // sampai restart app. Sekarang sync tetap jalan tiap 30s (RPC 1 RTT,
    // murah; provider anti-kedip mencegah flicker).
    // Coalesce: tick dilewati bila sync baru jalan <45 dtk (dari event
    // presence/profile) — fallback hanya untuk socket mati (tak ada event
    // = tak ada sync = tick tetap jalan tiap ~60 dtk).
    final fallbackTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (lastSyncAt != null &&
          DateTime.now().difference(lastSyncAt!).inSeconds < 45) {
        return; // baru sync — hemat 1 RPC.
      }
      dlog('[ONLINE-EMIT] fallback 30s tick cachedEmpty=${cached.isEmpty}');
      syncFromPresence();
    });
    controller.onCancel = () {
      debounce?.cancel();
      fallbackTimer.cancel();
      sub.cancel();
      _sb.removeChannel(profileSyncSub);
    };
    return controller.stream;
  }

  Stream<List<UserModel>> getOnlineUsersInRoom(String roomId) {
    return _sb
        .from('room_presence')
        .stream(primaryKey: ['room_id', 'user_id'])
        .eq('room_id', roomId)
        .map((rows) {
          // Presensi basi (joined_at > 5 menit, heartbeat 60 detik tidak jalan
          // lagi karena app di-kill/background) dianggap sudah keluar room.
          final cutoff = DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          );
          return rows
              .where((row) {
                final joined = DateTime.tryParse('${row['joined_at']}');
                return joined != null && joined.toUtc().isAfter(cutoff);
              })
              .map((row) {
                final d = snakeToCamel(row);
                return UserModel(
                  uid: d['userId'] ?? '',
                  nickname: d['nickname'] ?? 'Anon',
                  gender: d['gender'] ?? 'other',
                  age: (d['age'] as num?)?.toInt() ?? 0,
                  // room_presence tidak menyimpan lokasi (hanya profil); biarkan
                  // kosong agar tidak query kolom nir-skema.
                  country: '',
                  city: '',
                  ipAddress: '',
                  status: 'online',
                  avatar: '',
                  isRegistered: d['isRegistered'] == true,
                  loginAt: DateTime.now(),
                  createdAt: DateTime.now(),
                  lastSeen: parseDate(d['joinedAt']),
                );
              })
              // Dedupe by uid — update event dari supabase stream bisa
              // menduplikasi row (bug stream multi-column PK) sehingga
              // "Kamu" muncul 2x setelah keluar-masuk room.
              .fold<Map<String, UserModel>>({}, (acc, u) {
                acc[u.uid] = u;
                return acc;
              })
              .values
              .toList();
        });
  }
}
