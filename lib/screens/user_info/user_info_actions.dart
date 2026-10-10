part of '../user_info_screen.dart';

// Analyzer limitation: pada `part`+mixin, method yang dideklarasikan stubs di
// base tampak 'unused' walau dipanggil lintas-mixin. Aman diabaikan.
// ignore_for_file: unused_element

mixin _UiActionsMx on _UserInfoBase {
  Future<void> _startCall(BuildContext ctx, String callType) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final profile = auth.profile;
    final name = _profile?.nickname ?? widget.fallbackName;
    if (ProviderScope.containerOf(
      context,
      listen: false,
    ).read(callProvider.notifier).inCall) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text(s.msgCallInProgress)));
      return;
    }
    final messenger = ScaffoldMessenger.of(ctx);
    // Nelp pakai COIN (tanpa gratis). Saldo < tarif 1 menit → edukasi + topup.
    {
      final pp = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(pointsProvider.notifier);
      if (pp.enabled && pp.callBillingPublished) {
        final ok = await pp.ensureEnoughForCall(context, callType, s.isId);
        if (!ok) return;
      }
    }
    // Privasi panggilan penerima: bila menolak, jangan tembak DB sama sekali.
    // Server RLS tetap penjaga akhir.
    final allowed = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(privacyServiceProvider).canView(widget.userId, 'call');
    if (!mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text(s.callNotAllowed)));
      return;
    }
    // Izin kamera/mikrofon WAJIB sebelum getUserMedia — tanpa ini video call
    // pertama (izin belum ada) langsung gagal senyap (CallPhase.error).
    final perm = await ensureCallPermissions(video: callType == 'video');
    if (perm != CallPermissionResult.granted) {
      if (!mounted) return;
      showCallPermissionDialog(
        context,
        video: callType == 'video',
        permanentlyDenied: perm == CallPermissionResult.permanentlyDenied,
      );
      return;
    }
    try {
      // Chat dibuat/diambil dulu supaya overlay & banner punya rumah.
      final chatId = await ProviderScope.containerOf(context, listen: false)
          .read(chatProvider.notifier)
          .startPrivateChat(
            myUid: auth.uid!,
            otherUid: widget.userId,
            myName: profile?.nickname ?? '',
            otherName: name,
            myGender: profile?.gender ?? '',
          );
      if (!mounted) return;
      final session = await ProviderScope.containerOf(context, listen: false)
          .read(callProvider.notifier)
          .startSession(
            callId: await ProviderScope.containerOf(
              context,
              listen: false,
            ).read(callProvider.notifier).startCall(widget.userId, callType),
            remoteUid: widget.userId,
            remoteName: name,
            callType: callType,
            isCaller: true,
            mode: callType == 'video' ? CallMode.chat : CallMode.fullscreen,
            myName: profile?.nickname ?? '',
            myGender: profile?.gender ?? 'other',
            notifBody: callType == 'video'
                ? s.callNotifActiveVideo
                : s.callNotifActiveAudio,
            notifChannel: s.callNotifActiveAudio,
            notifDesc: s.callNotifActiveAudio,
            chatId: chatId,
          );
      final pp0 = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(pointsProvider.notifier);
      session.setBillingPerMinute(
        (pp0.enabled && pp0.callBillingPublished)
            ? pp0.callCostPerMin(callType)
            : 0,
      );
      if (!mounted) return;
      final navKey = navKeyChat(chatId);
      if (!tryClaimNav(navKey)) return;
      if (callType == 'video') {
        Navigator.of(ctx)
            .push(
              MaterialPageRoute(
                settings: RouteSettings(name: privateChatRoute(chatId)),
                builder: (_) => PrivateChatScreen(
                  chatId: chatId,
                  otherName: name,
                  otherUid: widget.userId,
                ),
              ),
            )
            .then((_) => releaseNav(navKey));
      } else {
        Navigator.of(ctx).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            settings: const RouteSettings(name: kCallScreenRoute),
            builder: (_) => CallScreen(
              callId: session.callId,
              remoteUid: widget.userId,
              remoteName: name,
              callType: callType,
              isCaller: true,
              chatId: chatId,
              session: session,
            ),
          ),
        );
      }
    } catch (e) {
      // Jangan telan error mentah-mentah: tulis ke logcat (dlog di-strip di
      // release) + petakan ke pesan yang menjelaskan penyebab (RLS/jaringan).
      debugPrint('[CALL-START] _startCall gagal ($callType): $e');
      final low = e.toString().toLowerCase();
      final denied =
          low.contains('policy') ||
          low.contains('permission denied') ||
          low.contains('unauthorized') ||
          low.contains('401') ||
          low.contains('403') ||
          low.contains('jwt');
      final offline =
          low.contains('socketexception') ||
          low.contains('failed host lookup') ||
          low.contains('network is unreachable') ||
          low.contains('connection refused') ||
          low.contains('timeout');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? s.msgCallRegisterOnly
                : offline
                ? s.errCallNetwork
                : s.errGeneric,
          ),
        ),
      );
    }
  }

  /// Buka chat pribadi dengan user yang sedang dilihat.
  /// Buat/ambil chatId dulu, lalu push PrivateChatScreen.
  Future<void> _startChat() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final chat = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatProvider.notifier);
    final profile = _profile;
    final name = profile?.nickname ?? widget.fallbackName;
    final myUid = auth.uid;
    if (myUid == null) return;
    try {
      final active = await chat.isUserActive(widget.userId);
      if (!mounted) return;
      if (!active) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
        return;
      }
      final chatId = await chat.startPrivateChat(
        myUid: myUid,
        otherUid: widget.userId,
        myName: auth.profile?.nickname ?? '',
        otherName: name,
        myGender: auth.profile?.gender ?? '',
        otherGender: profile?.gender ?? '',
        myCountry: auth.profile?.country ?? '',
        otherCountry: profile?.country ?? '',
        myAge: auth.profile?.age ?? 0,
        otherAge: profile?.age ?? 0,
      );
      if (!mounted) return;
      final navKey = navKeyChat(chatId);
      if (!tryClaimNav(navKey)) return;
      await Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => PrivateChatScreen(
                chatId: chatId,
                otherName: name,
                otherUid: widget.userId,
                otherGender: profile?.gender ?? '',
                otherCountry: profile?.country ?? '',
                otherCity: profile?.city ?? '',
                otherAge: profile?.age ?? 0,
                otherRegistered: profile?.isRegistered ?? false,
              ),
            ),
          )
          .then((_) => releaseNav(navKey));
      // Refresh status sosial setelah balik dari chat (bisa follow dari sana).
      if (mounted) _loadSocial();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!mounted) return;
      if (msg.contains('23503') ||
          msg.contains('foreign key') ||
          msg.contains('42501')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    }
  }

  /// Subscribe status dengan seed dari profil yang baru di-fetch,
  /// supaya dot status benar sejak frame pertama tanpa query tambahan.
  void _subscribeStatus(UserModel? fresh) {
    _statusSub?.cancel();
    final known = fresh == null
        ? null
        : ChatNotifier.effectiveStatusOf(
            fresh.status,
            fresh.lastSeen.toIso8601String(),
          );
    _statusSub = ProviderScope.containerOf(context, listen: false)
        .read(chatProvider.notifier)
        .getUserStatus(widget.userId, initialStatus: known)
        .listen(
          (status) {
            if (!mounted) return;
            setState(() => _status = status);
          },
          onError: (e) {
            // OFFLINE: stream status error → jangan tak tertangkap.
            debugPrint('[NAV] status stream error user-info: $e');
          },
        );
  }

  Future<void> _load() async {
    // INSTAN dari cache SQLite (memori) → info teman/pengikut tampil di frame
    // pertama, tanpa "keload dulu". Refresh server menyusul.
    if (_profile == null) {
      final cached = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier).peekProfileCache(widget.userId);
      if (cached != null && mounted) {
        setState(() {
          _profile = cached;
          _loading = false;
        });
      }
    }
    UserModel? p;
    // Retry sekali: timeout/gangguan jaringan sesaat tidak boleh langsung
    // memvonis gagal (kasus "tadi tidak, sekarang muncul").
    for (var attempt = 0; attempt < 2 && p == null; attempt++) {
      try {
        p = await ProviderScope.containerOf(context, listen: false)
            .read(authProvider.notifier)
            .getOtherProfile(widget.userId)
            .timeout(_loadTimeout);
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      if (p != null) _profile = p;
      _loading = false;
      // Profil tetap null = gagal total (bukan user tanpa data).
      _loadError = _profile == null;
    });
    _subscribeStatus(p);
    // Avatar menyusul — tidak menahan tampilnya profil. Selalu resolve:
    // getByPath memakai cache (RAM/disk/uid) sehingga instan bila sudah ada,
    // dan menjadwalkan refresh server di background kalau perlu.
    final path = _profile?.avatar ?? '';
    if (path.isNotEmpty && path != _avatarPath) {
      _avatarRetried = false;
      _loadAvatar(path);
    }
  }

  /// Muat foto profil (path → base64) setelah profil tampil. Kegagalan di
  /// sini hanya berarti avatar kosong (inisial), BUKAN layar error.
  ///
  /// ANTI-HILANG: kalau gagal sesaat, coba SEKALI lagi setelah jeda pendek.
  /// Dulu sekali gagal = inisial permanen sampai layar dibuka ulang; kalau
  /// kebetulan decoding/network sedang sibuk saat masuk, foto tampak
  /// "hilang" padahal ada di server.
  Future<void> _loadAvatar(String path) async {
    _avatarPath = path;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!mounted) return;
      try {
        final b64 = await ProviderScope.containerOf(context, listen: false)
            .read(authProvider.notifier)
            .getAvatarByPath(path)
            .timeout(_loadTimeout);
        if (!mounted) return;
        if (b64.isNotEmpty) {
          setState(() => _avatarB64 = b64);
          dlog(
            '[AVATAR] info ${widget.userId.substring(0, 8)} load OK '
            'len=${b64.length} attempt=$attempt',
          );
          return;
        }
        dlog(
          '[AVATAR] info ${widget.userId.substring(0, 8)} kosong '
          'attempt=$attempt',
        );
      } catch (e) {
        dlog(
          '[AVATAR] info ${widget.userId.substring(0, 8)} gagal '
          'attempt=$attempt err=$e',
        );
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    _avatarRetried = true;
    // Selesai mencoba tapi tidak dapat foto → tampil inisial (lihat carousel).
  }

  /// Bytes avatar ter-decode, cache per-string — decode SEKALI saat b64
  /// berubah, bukan tiap build. Mengembalikan null bila tidak ada/gagal.
  Uint8List? _decodedAvatarBytes() {
    if (_avatarB64.isEmpty) {
      _avatarB64Cached = '';
      _avatarBytesCached = null;
      return null;
    }
    if (_avatarB64 != _avatarB64Cached) {
      try {
        _avatarBytesCached = base64Decode(_avatarB64);
      } catch (_) {
        _avatarBytesCached = null;
      }
      _avatarB64Cached = _avatarB64;
    }
    return _avatarBytesCached;
  }

  /// Ambil bytes galeri dari cache (decode sekali per photo-id).
  Uint8List? _galleryBytesOf(UserPhoto photo) {
    final hit = _galleryBytes[photo.id];
    if (hit != null) return hit;
    if (photo.photo.isEmpty) return null;
    try {
      final b = base64Decode(photo.photo);
      if (b.isEmpty) return null;
      // Galeri per user kecil; buang yang paling lama bila penuh supaya
      // tidak tumbuh tanpa batas.
      if (_galleryBytes.length >= 20) {
        _galleryBytes.remove(_galleryBytes.keys.first);
      }
      _galleryBytes[photo.id] = b;
      return b;
    } catch (_) {
      return null;
    }
  }

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    _galleryBytes.clear();
    _load();
    _loadPhotos();
    _loadSocial();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await ProviderScope.containerOf(context, listen: false)
          .read(authProvider.notifier)
          .getPhotosWithAccess(widget.userId)
          .timeout(_loadTimeout);
      if (!mounted) return;
      // Daftar diganti → cache bytes lama dibuang (isi foto bisa berubah,
      // mis. setelah paywall dibuka). Decode ulang terjadi sekali per foto.
      _galleryBytes.clear();
      setState(() => _photos = photos);
    } catch (_) {}
  }

  void _showPhotoViewer(List<UserPhoto> photos, int index) {
    // Hanya foto terbuka yang bisa dilihat penuh.
    final unlockedPhotos = photos.where((p) => p.unlocked).toList();
    if (unlockedPhotos.isEmpty) return;
    final target = photos[index];
    final viewerIndex = unlockedPhotos.indexWhere((p) => p.id == target.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserPhotoViewer(
          photos: unlockedPhotos,
          initialIndex: viewerIndex < 0 ? 0 : viewerIndex,
        ),
      ),
    );
  }
}
