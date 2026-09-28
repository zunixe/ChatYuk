import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../core/nav_guard.dart';
import '../utils.dart';
import '../models/user_model.dart';
import '../models/user_photo.dart';
import '../providers/chat_provider.dart';
import '../providers/call_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/social_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/async_photo.dart';
import '../widgets/call_permission_dialog.dart';
import '../core/call/call_permissions.dart';
import '../providers/theme_provider.dart';
import 'call_screen.dart';
import 'private_chat_screen.dart';
import 'social_list_screen.dart';
import '../core/perf/perf_probe.dart';

class UserInfoScreen extends StatefulWidget {
  final String userId;
  final String fallbackName;
  const UserInfoScreen({
    super.key,
    required this.userId,
    required this.fallbackName,
  });

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  UserModel? _profile;
  bool _loading = true;
  // Gagal total (timeout/network) saat profil masih null — tampilkan
  // error + tombol retry, jangan spinner selamanya.
  bool _loadError = false;
  // Avatar (base64) dimuat TERPISAH dari profil: profil teks muncul duluan,
  // foto menyusul. Dulu avatar diunduh di dalam getProfileById → kalau
  // lambat, SELURUH profil kena timeout 10 dtk → layar "Coba lagi"
  // (keluhan "profilnya ga muncul" padahal datanya ada).
  String _avatarB64 = '';
  // Path avatar terakhir + penanda sudah pernah dicoba, supaya kegagalan
  // sesaat bisa dicoba ulang sekali (foto tidak "menghilang" permanen
  // selama layar terbuka).
  String _avatarPath = '';
  bool _avatarRetried = false;
  List<UserPhoto> _photos = [];
  String _status = 'offline';
  StreamSubscription<String>? _statusSub;

  // Status sosial terhadap user ini.
  bool _following = false;
  bool _friend = false;
  bool _friendRequestSent = false;
  bool _subscribed = false;
  bool _busySocial = false;

  // Carousel foto: geser kiri-kanan (avatar + foto terbuka).
  late final PageController _carouselCtrl = PageController();
  int _carouselIndex = 0;

  @override
  void initState() {
    super.initState();
    // Seed SINKRON dari cache RAM/disk: foto yang sudah tampil di daftar/
    // header chat ATAU tersimpan di disk (cold start) langsung terlihat pada
    // frame pertama — tanpa fase inisial → foto (anti-kedip).
    _avatarB64 =
        context.read<AuthProvider>().cachedAvatarSyncDeep(widget.userId) ?? '';
    _load();
    _loadPhotos();
    _loadSocial();
    // Ambil nominal biaya buka foto untuk label harga.
    context.read<PointsProvider>().refreshPhotoCosts();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _carouselCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSocial() async {
    try {
      final st = await context.read<SocialProvider>()
          .mySocialStatus(widget.userId)
          .timeout(_loadTimeout);
      if (!mounted) return;
      setState(() {
        _following = st['following'] == true;
        _friend = st['friend'] == true;
        _friendRequestSent = st['friend_request_sent'] == true;
        _subscribed = st['subscribed'] == true;
      });
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final targetRegistered = _profile?.isRegistered ?? false;
    if (auth.isAnonymous || !(auth.profile?.isRegistered ?? false)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgRegisterToFollow)));
      return;
    }
    if (!targetRegistered) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgTargetNotRegistered)));
      return;
    }
    final social = context.read<SocialProvider>();
    setState(() => _busySocial = true);
    final ok = _following
        ? await social.unfollow(widget.userId)
        : await social.follow(widget.userId);
    if (!mounted) return;
    setState(() {
      // Hanya toggle kalau RPC sukses — kalau gagal, biarkan state tetap
      // sinkron dengan server (tidak menampilkan tombol yang menyesatkan).
      if (ok) {
        _following = !_following;
        if (!_following) _friend = false;
      }
      _busySocial = false;
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_following ? s.btnFollow : s.btnUnfollow)),
      );
    }
  }

  Future<void> _addFriend() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final targetRegistered = _profile?.isRegistered ?? false;
    if (auth.isAnonymous || !(auth.profile?.isRegistered ?? false)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgRegisterToFollow)));
      return;
    }
    if (!targetRegistered) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgTargetNotRegistered)));
      return;
    }
    final social = context.read<SocialProvider>();
    setState(() => _busySocial = true);
    final status = await social.sendFriendRequest(widget.userId);
    if (!mounted) return;
    setState(() {
      if (status == 'pending') _friendRequestSent = true;
      _busySocial = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.friendRequestSent)));
  }

  Future<void> _subscribe() async {
    final s = context.read<LocaleProvider>().s;
    final profile = _profile;
    if (profile == null) return;
    final price = profile.subscriptionPrice;
    if (price <= 0) return;
    final auth = context.read<AuthProvider>();
    if (!auth.canUsePaid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
      return;
    }
    final points = context.read<PointsProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            Icon(Icons.star_rounded, color: Color(0xFFB8860B)),
            SizedBox(width: 8),
            Expanded(child: Text(s.subscribeConfirmTitle)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.subscribeConfirmBody(profile.nickname, price, 1),
              style: AppText.bodyStrong,
            ),
            SizedBox(height: 12),
            Text(
              s.subscribeFansHint,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnSubscribe,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busySocial = true);
    try {
      await points.subscribeCreator(widget.userId);
      if (!mounted) return;
      setState(() => _subscribed = true);
      points.refreshWallet();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.subscribeSuccess)));
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('registered')
          ? s.subscribeNeedRegister
          : msg.contains('Not enough paid') || msg.contains('Not enough')
          ? s.subscribeNeedPaid
          : s.errGeneric;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(show)));
    } finally {
      if (mounted) setState(() => _busySocial = false);
    }
  }

  /// Mulai panggilan audio/video (caller) ke user yang sedang dilihat.
  /// Video darat di dalam chat (overlay), audio di layar penuh.
  Future<void> _startCall(BuildContext ctx, String callType) async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    final name = _profile?.nickname ?? widget.fallbackName;
    if (CallProvider.instance.inCall) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text(s.msgCallInProgress)));
      return;
    }
    final messenger = ScaffoldMessenger.of(ctx);
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
      final chatId = await context.read<ChatProvider>().startPrivateChat(
        myUid: auth.uid!,
        otherUid: widget.userId,
        myName: profile?.nickname ?? '',
        otherName: name,
        myGender: profile?.gender ?? '',
      );
      if (!mounted) return;
      final session = await CallProvider.instance.startSession(
        callId: await context.read<CallProvider>().startCall(widget.userId, callType),
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
      if (!mounted) return;
      final navKey = navKeyChat(chatId);
      if (!tryClaimNav(navKey)) return;
      if (callType == 'video') {
        Navigator.of(ctx).push(
          MaterialPageRoute(
            settings: RouteSettings(name: privateChatRoute(chatId)),
            builder: (_) => PrivateChatScreen(
              chatId: chatId,
              otherName: name,
              otherUid: widget.userId,
            ),
          ),
        ).then((_) => releaseNav(navKey));
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
      final denied = low.contains('policy') ||
          low.contains('permission denied') ||
          low.contains('unauthorized') ||
          low.contains('401') ||
          low.contains('403') ||
          low.contains('jwt');
      final offline = low.contains('socketexception') ||
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
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
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
      await Navigator.of(context).push(
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
      ).then((_) => releaseNav(navKey));
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
        : ChatProvider.effectiveStatusOf(
            fresh.status,
            fresh.lastSeen.toIso8601String(),
          );
    _statusSub = context
        .read<ChatProvider>()
        .getUserStatus(widget.userId, initialStatus: known)
        .listen((status) {
          if (!mounted) return;
          setState(() => _status = status);
        }, onError: (e) {
          // OFFLINE: stream status error → jangan tak tertangkap.
          debugPrint('[NAV] status stream error user-info: $e');
        });
  }

  static const _loadTimeout = Duration(seconds: 10);

  Future<void> _load() async {
    UserModel? p;
    // Retry sekali: timeout/gangguan jaringan sesaat tidak boleh langsung
    // memvonis gagal (kasus "tadi tidak, sekarang muncul").
    for (var attempt = 0; attempt < 2 && p == null; attempt++) {
      try {
        p = await context.read<AuthProvider>()
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
        final b64 = await context
            .read<AuthProvider>()
            .getAvatarByPath(path)
            .timeout(_loadTimeout);
        if (!mounted) return;
        if (b64.isNotEmpty) {
          setState(() => _avatarB64 = b64);
          dlog('[AVATAR] info ${widget.userId.substring(0, 8)} load OK '
              'len=${b64.length} attempt=$attempt');
          return;
        }
        dlog('[AVATAR] info ${widget.userId.substring(0, 8)} kosong '
            'attempt=$attempt');
      } catch (e) {
        dlog('[AVATAR] info ${widget.userId.substring(0, 8)} gagal '
            'attempt=$attempt err=$e');
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    _avatarRetried = true;
  }

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    _load();
    _loadPhotos();
    _loadSocial();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await context.read<AuthProvider>()
          .getPhotosWithAccess(widget.userId)
          .timeout(_loadTimeout);
      if (mounted) setState(() => _photos = photos);
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
        builder: (_) => _UserPhotoViewer(
          photos: unlockedPhotos,
          initialIndex: viewerIndex < 0 ? 0 : viewerIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('UserInfo');
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final profile = _profile;
    final pointsEnabled = context.watch<PointsProvider>().enabled;
    // Tombol sosial (pengikut/mengikuti/subscriber + ikuti/tambah teman)
    // SELALU tampil — viewer anon yang mengetuk diberi snackbar daftar
    // (guard di _toggleFollow/_addFriend). Jangan disembunyikan.
    final auth = context.watch<AuthProvider>();
    final isAnonViewer = auth.isAnonymous;

    final name = profile?.nickname ?? widget.fallbackName;
    final genderLabel = profile?.gender == 'male'
        ? s.genderLabelMale
        : profile?.gender == 'female'
        ? s.genderLabelFemale
        : s.genderLabelOther;
    final status = _status;
    final statusLabel = status == 'online'
        ? s.statusOnline
        : status == 'idle'
        ? s.statusIdle
        : s.statusOffline;
    final statusColor = AppTheme.statusColor(status);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.titleProfile),
        actions: [
          // Tombol call: default hanya untuk viewer terdaftar & target
          // terdaftar. Admin bisa membukanya ke SEMUA user via panel
          // (app_settings.call_all_enabled).
          if (auth.callAllEnabled ||
              (!isAnonViewer && profile?.isRegistered == true)) ...[
            PopupMenuButton<String>(
              icon: Icon(Icons.call, size: 22),
              color: AppTheme.bgCard,
              tooltip: s.callAudio,
              onSelected: (val) => _startCall(context, val),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'audio',
                  child: Row(
                    children: [
                      Icon(Icons.call, size: 18),
                      const SizedBox(width: 12),
                      Text(s.callAudio),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'video',
                  child: Row(
                    children: [
                      Icon(Icons.videocam, size: 18),
                      const SizedBox(width: 12),
                      Text(s.callVideo),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _loading
          ? _LoadingPlaceholder(name: widget.fallbackName)
          : (_loadError && _profile == null)
              ? _LoadErrorView(onRetry: _retryLoad)
              : Builder(builder: (_) {
              // Foto masih kosong padahal profil punya path → coba sekali lagi
              // (kegagalan pertama bisa sesaat). Guard `_avatarRetried` supaya
              // tidak memicu loop kalau memang tidak ada fotonya.
              if (_avatarB64.isEmpty &&
                  _avatarPath.isNotEmpty &&
                  !_avatarRetried) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _avatarB64.isEmpty) _loadAvatar(_avatarPath);
                });
              }
              return SingleChildScrollView(
              // padding bawah + tinggi nav bar Android supaya card galeri
              // (terakhir) tidak tertutup gesture bar / 3-tombol.
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                children: [
                  SizedBox(height: 8),

                  // Galeri geser: avatar + foto terbuka, slide kiri-kanan.
                  // Ketuk foto = tampil penuh.
                  _profileCarousel(
                    avatarB64: _avatarB64,
                    avatarBg: profile?.gender == 'male'
                        ? AppTheme.male
                        : profile?.gender == 'female'
                        ? AppTheme.female
                        : AppTheme.accent,
                    initial: (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                    statusColor: statusColor,
                    unlocked: _photos.where((p) => p.unlocked).toList(),
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: AppText.headline.copyWith(
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (profile?.isRegistered == true) ...[
                        SizedBox(width: 5),
                        Icon(
                          Icons.verified,
                          size: 20,
                          color: Color(0xFF4A90E2),
                        ),
                      ],
                      // Ikon chat kecil di samping username — klik langsung chat.
                      // Anon BOLEH chat (sama dengan perilaku menu online) —
                      // dulu disembunyikan untuk anon = inkonsisten.
                      if (auth.uid != widget.userId) ...[
                        SizedBox(width: 8),
                        _ChatIconButton(onTap: _startChat),
                      ],
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        genderLabel,
                        style: AppText.bodyStrong.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (profile?.age != null && profile!.age > 0) ...[
                        SizedBox(width: 12),
                        Text(
                          '${profile.age} ${s.labelYears}',
                          style: AppText.bodyStrong.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 24),

                  if (profile != null && profile.hashtags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: profile.hashtags
                          .map(
                            (tag) => Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.accent.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                '#$tag',
                                style: AppText.label.copyWith(letterSpacing: 0),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    SizedBox(height: 24),
                  ],

                  // Info card
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _infoRow(s.labelStatus, statusLabel),
                          if (profile != null) ...[
                            Divider(color: AppTheme.divider),
                            _infoRow(
                              s.labelCountry,
                              profile.country.isEmpty ? '-' : profile.country,
                            ),
                            Divider(color: AppTheme.divider),
                            _infoRow(
                              s.labelCity,
                              profile.city.isEmpty ? '-' : profile.city,
                            ),
                          ],
                          Divider(color: AppTheme.divider),
                          _infoRow(
                            s.labelUserId,
                            widget.userId.substring(0, 8),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Sosial kompak: stat mini + tombol ikon kecil, langsung
                  // terlihat tanpa scroll. Selalu tampil (termasuk viewer
                  // anon) — guard daftar ada di tiap aksi.
                  if (profile != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _miniStat(
                          Icons.favorite_rounded,
                          const Color(0xFFE91E63),
                          profile.followersCount,
                          s.socialFollowers,
                          onTap: () => _openSocialList('followers'),
                        ),
                        _miniStat(
                          Icons.person_rounded,
                          AppTheme.primary,
                          profile.followingCount,
                          s.socialFollowing,
                          onTap: () => _openSocialList('following'),
                        ),
                        _miniStat(
                          Icons.star_rounded,
                          const Color(0xFFB8860B),
                          profile.subscriberCount,
                          s.socialSubscribers,
                          onTap: () => _openSocialList('subscribers'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_busySocial)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _friend
                              ? _iconActionBtn(
                                  icon: Icons.group_rounded,
                                  label: s.btnFriends,
                                  color: Colors.green,
                                  active: true,
                                  onTap: () {},
                                )
                              : _friendRequestSent
                              ? _iconActionBtn(
                                  icon: Icons.schedule_rounded,
                                  label: s.btnFriendRequested,
                                  color: Colors.orange,
                                  active: true,
                                  onTap: () {},
                                )
                              : _iconActionBtn(
                                  icon: Icons.group_add_rounded,
                                  label: s.btnAddFriend,
                                  color: Colors.green,
                                  active: false,
                                  onTap: _addFriend,
                                ),
                          const SizedBox(width: 12),
                          _iconActionBtn(
                            icon: _following
                                ? Icons.check_rounded
                                : Icons.person_add_alt_1_rounded,
                            label: _following ? s.btnUnfollow : s.btnFollow,
                            color: _following
                                ? AppTheme.textSecondary
                                : AppTheme.primary,
                            active: _following,
                            onTap: _toggleFollow,
                          ),
                          if (pointsEnabled &&
                              profile.subscriptionPrice > 0) ...[
                            const SizedBox(width: 12),
                            _subscribed
                                ? _iconActionBtn(
                                    icon: Icons.star_rounded,
                                    label: s.btnSubscribed,
                                    color: const Color(0xFFB8860B),
                                    active: true,
                                    onTap: () {},
                                  )
                                : _iconActionBtn(
                                    icon: Icons.star_rounded,
                                    label:
                                        '${s.btnSubscribe} · ${s.subscribePrice(profile.subscriptionPrice)}',
                                    color: const Color(0xFFB8860B),
                                    active: false,
                                    onTap: _subscribe,
                                  ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 8),
                  ],

                  // Galeri Foto Profil dihapus sesuai permintaan — tidak
                  // ditampilkan lagi di halaman profil orang lain.
                  const SizedBox.shrink(),
                ],
              ),
              );
              }),
    );
  }

  /// Carousel foto profil: avatar + foto terbuka, geser kiri-kanan.
  /// Tanpa foto sama sekali → lingkaran inisial (tidak bisa digeser).
  Widget _profileCarousel({
    required String avatarB64,
    required Color avatarBg,
    required String initial,
    required Color statusColor,
    required List<UserPhoto> unlocked,
  }) {
    final hasAvatar = avatarB64.isNotEmpty;
    Uint8List? avatarBytes;
    if (hasAvatar) {
      try {
        avatarBytes = base64Decode(avatarB64);
      } catch (_) {}
    }
    final pageCount = (avatarBytes != null ? 1 : 0) + unlocked.length;
    if (pageCount == 0) {
      return CircleAvatar(
        radius: 60,
        backgroundColor: avatarBg,
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: AppGlyph.avatarInitial(120),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    if (_carouselIndex >= pageCount) _carouselIndex = 0;
    Widget avatarPage() {
      final b = avatarBytes;
      final img = b == null
          ? Container(
              color: avatarBg,
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppGlyph.avatarInitial(120),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          // Carousel 280px — cap 720px (bukan full-res).
          : Image.memory(
              b,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: 720,
            );
      return GestureDetector(
        onTap: b == null ? null : () => _showFullscreenPhoto(b),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox.expand(child: img),
        ),
      );
    }

    Widget galleryPage(UserPhoto photo) {
      Uint8List? b;
      try {
        b = base64Decode(photo.photo);
      } catch (_) {}
      return GestureDetector(
        onTap: () => _showPhotoViewer(unlocked, unlocked.indexOf(photo)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox.expand(
            child: b == null
                ? Container(color: AppTheme.bgCard)
                : Image.memory(
                    b,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: 720,
                  ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 280,
          width: double.infinity,
          child: Stack(
            children: [
              PageView.builder(
                controller: _carouselCtrl,
                onPageChanged: (i) =>
                    setState(() => _carouselIndex = i),
                itemCount: pageCount,
                itemBuilder: (_, i) {
                  if (avatarBytes != null && i == 0) return avatarPage();
                  final photo =
                      unlocked[i - (avatarBytes != null ? 1 : 0)];
                  return galleryPage(photo);
                },
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (pageCount > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              pageCount,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _carouselIndex == i ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _carouselIndex == i
                      ? AppTheme.primary
                      : AppTheme.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showFullscreenPhoto(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                // Cap 1080px: dialog zoom tidak butuh full-res 12MP.
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  cacheWidth: 1080,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Keluarkan bitmap zoom dari ImageCache (pola PhotoViewerScreen).
      if (bytes.isNotEmpty) {
        try {
          PaintingBinding.instance.imageCache.evict(MemoryImage(bytes));
        } catch (_) {}
      }
    });
  }

  /// Stat mini di bawah nama: ikon kecil + angka (tanpa kartu besar).
  Widget _miniStat(
    IconData icon,
    Color color,
    int value,
    String label, {
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: row,
    );
  }

  void _openSocialList(String kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialListScreen(kind: kind, userId: widget.userId),
      ),
    );
  }

  /// Tombol aksi ikon kecil (ikuti/teman/subscribe): lingkaran + tulisan
  /// mungil di bawahnya supaya jelas maksud ikonnya. Nonaktif saat sibuk
  /// / sudah aktif.
  Widget _iconActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool active,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: color.withValues(alpha: active ? 0.14 : 1),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _busySocial ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: _busySocial
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: active ? color : Colors.white,
                        ),
                      )
                    : Icon(
                        icon,
                        size: 20,
                        color: active ? color : Colors.white,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 76,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.micro.copyWith(
                color: active ? color : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textSecondary)),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

}

class _ChatIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ChatIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return Tooltip(
      message: s.btnChatNow,
      child: Material(
        color: AppTheme.primary.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.chat_bubble_rounded,
              size: 18,
              color: AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserPhotoViewer extends StatefulWidget {
  final List<UserPhoto> photos;
  final int initialIndex;
  const _UserPhotoViewer({required this.photos, required this.initialIndex});

  @override
  State<_UserPhotoViewer> createState() => _UserPhotoViewerState();
}

class _UserPhotoViewerState extends State<_UserPhotoViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.photos.length}'),
      ),
      // SafeArea: foto portrait tinggi TANPA ini mencapai belakang menu
      // navigasi bawah (kasus sama seperti preview video chat).
      body: SafeArea(
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (ctx, i) => Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: AsyncPhotoViewer(base64: widget.photos[i].photo),
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading instan: nama + inisial langsung tampil dari fallback, spinner
/// kecil di bawah — tidak ada layar kosong muter-muter.
class _LoadingPlaceholder extends StatelessWidget {
  final String name;
  const _LoadingPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: AppTheme.accent,
            child: Text(
              (name.isNotEmpty ? name[0] : '?').toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: AppGlyph.avatarInitial(100),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name.isNotEmpty ? name : '…',
            style: AppText.headline.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gagal total (timeout/network) — pesan jelas + tombol coba lagi.
class _LoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              s.msgServerError,
              style: AppText.bodyStrong.copyWith(
                color: AppTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              s.msgServerErrorHint,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(s.btnRetry),
            ),
          ],
        ),
      ),
    );
  }
}
