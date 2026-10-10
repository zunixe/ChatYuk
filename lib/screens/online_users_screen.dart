import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../models/user_model.dart';
import '../models/room_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_riverpod/flutter_riverpod.dart' as rv;
import '../providers/riverpod/online_users_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../providers/riverpod/room_provider.dart';
import 'online_users/widgets/my_status_sheet.dart';
import 'online_users/widgets/unread_bubble.dart';
import 'online_users/widgets/user_list_section.dart';
import 'online_users/widgets/online_app_bar.dart';
import 'online_users/widgets/online_channel.dart';
import 'online_users/widgets/story_tray_section.dart';
import 'online_users/widgets/chat_nav.dart';
import 'online_users/widgets/avatar_zoom.dart';
import 'online_users/widgets/avatar_upload.dart';
import '../core/cache/media_disk_cache.dart';
import '../core/nav_guard.dart';
import '../widgets/quick_side_menu.dart';
import '../models/story_model.dart';
import '../providers/riverpod/social_provider.dart';
import 'nearby_screen.dart';
import '../widgets/user_avatar.dart' as ua;
import 'room_chat_screen.dart';
import 'lobby_screen.dart';
import 'group_screen.dart';
import 'story_composer_screen.dart';
import 'story_camera_capture_screen.dart';
import 'story_camera_picker_screen.dart';
import 'story_viewer_screen.dart';
import '../providers/riverpod/story_provider.dart';
import '../providers/riverpod/privacy_provider.dart';
import '../models/privacy_settings.dart';
import '../core/perf/perf_probe.dart';
import '../widgets/anon_prompt_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import '../providers/riverpod/location_provider.dart';

// Cache render avatar (bytes + ImageProvider stabil per-uid) kini MODULAR di
// `widgets/user_avatar.dart` (dipakai lintas halaman user-facing). Layar ini
// hanya menyisakan helper cap-decode untuk avatar SENDIRI (tile tray & zoom).
//
// `clearAllAvatarCaches` & peek `_avatarBytesByUid` dulu: sekarang
// `clearAllAvatarCaches` (di user_avatar.dart) + `cachedUserAvatarBytes(uid)`.

/// Lebar decode maksimum avatar di list (px). 96 = cukup untuk avatar 40px
/// di layar 2-3× DPI tanpa blur, ~25× lebih kecil dari decode full-res.
const int _avatarDecodePx = 96;

/// Bungkus MemoryImage dengan cap decode. Provider STABIL per-uid (instance
/// sama dipakai terus) supaya ImageCache hit & tidak kedip.
ImageProvider _cappedAvatarImage(Uint8List bytes) =>
    ResizeImage(MemoryImage(bytes), width: _avatarDecodePx);

/// Bersihkan cache avatar (delegasi ke modul user_avatar) — dipertahankan
/// sebagai API layar ini supaya pemanggil eksternal tidak berubah.
void clearAllAvatarCaches() => ua.clearAllAvatarCaches();

/// Proses avatar (crop 1:1 sudah dilakukan cropper) → resize 640 + JPEG q85.
/// Kini di NATIVE via `NativeImage.processSquare` (fallback Dart di
/// chat_photo_helper.dart). Konstanta kontrak diekspos untuk test.

// Avatar SELALU JPEG (sama seperti profile_screen & foto chat). Dulu memakai
// encoder WebP native FlutterImageCompress, tapi hasilnya membawa ICC
// profile/krominansi yang tidak konsisten antar-device → avatar tampil
// "biro-biro" saat dilihat dari HP lain lewat CDN. JPEG polos universal.
// Kompresi kini di NATIVE via `NativeImage.processSquare` (fallback ke
// `processAvatarImage` Dart) — lihat lib/core/media/native_image.dart.


class OnlineUsersScreen extends ConsumerStatefulWidget {
  const OnlineUsersScreen({super.key});

  @override
  ConsumerState<OnlineUsersScreen> createState() => _OnlineUsersScreenState();
}

class _OnlineUsersScreenState extends ConsumerState<OnlineUsersScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  // Multi-select negara: kosong = Semua. Persist via prefs (JSON list).
  List<String> _negaraSel = const [];
  // Single-select gender: all | male | female. Persist via prefs.
  String _gender = 'all';
  // Channel daftar Online: Semua (all) | Teman (friends). Persist via prefs.
  OnlineChannel _channel = OnlineChannel.all;
  String _search = '';
  bool _isSearching = false;
  int _page = 1;
  static const _prefKeyNegara = 'filter_negara'; // legacy single
  static const _prefKeyNegaraList = 'filter_negara_multi';
  static const _prefKeyGender = 'filter_gender';
  static const _prefKeyChannel = 'filter_channel';
  // Snapshot set teman terakhir — dipakai agar filter channel "Teman" memakai
  // data terkini tanpa rebuild storm (dibandingkan via setEquals).
  Set<String> _friendSet = const {};
  // Saat channel "Teman" dipilih, presence-visibility DIRI SENDIRI di-override
  // ke `friends` (biar "Status kamu terlihat oleh" = Teman). Simpan nilai asli
  // (dari Kelola Privasi) di sini supaya channel "Semua" bisa mengembalikannya.
  static const _prefKeyPresenceOverrideBefore = 'channel_presence_before';
  /// GPS hanya dijalankan SEKALI per install (lihat _requestGpsOnce).
  static const _gpsRequestedKey = 'gps_requested_once';
  PrivacyVisibility? _presenceBeforeFriends;
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  StreamSubscription<List<PrivateChatInfo>>? _unreadSub;
  // Entry bubble unread yang sedang tampil (overlay). Disimpan supaya bisa
  // dipaksa-remove saat pindah rute / dispose — mencegah penghalang tap.
  OverlayEntry? _unreadBubbleEntry;
  Map<String, int> _unreadMap = {};
  String? _hiddenOwner;
  bool _showHidden = false;

  // Cache decode avatar sendiri — persis pola tile story: bytes di-decode
  // SEKALI per foto baru; rebuild sebanyak apa pun memakai instance bytes
  // yang sama → MemoryImage identik → ImageCache hit → tidak kedip
  // (dulu: base64Decode di dalam build tiap rebuild = decode ulang = kedip).
  String _ownAvatarB64 = '';
  Uint8List? _ownAvatarBytes;

  /// Resolve bytes avatar sendiri dengan cache — decode hanya saat string
  /// base64 BERUBAH (upload foto baru), bukan tiap rebuild.
  Uint8List? _resolveOwnAvatar(String b64) {
    if (b64.isEmpty) {
      _ownAvatarB64 = '';
      _ownAvatarBytes = null;
      return null;
    }
    if (b64 != _ownAvatarB64) {
      try {
        _ownAvatarBytes = base64Decode(b64);
        _ownAvatarB64 = b64;
      } catch (_) {
        _ownAvatarBytes = null;
        _ownAvatarB64 = '';
      }
    }
    return _ownAvatarBytes;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Balik dari background → sinkron ulang tray (tangkap delete/update
    // story yang terjadi saat channel realtime mati) + buka-ulang
    // subscription online (socket bisa mati saat background — tanpa ini
    // user yang baru online tidak terlihat sampai restart app).
    if (state == AppLifecycleState.resumed && mounted) {
      try {
        ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier).refresh(silent: true);
      } catch (_) {}
      try {
        ProviderScope.containerOf(context, listen: false).read(onlineUsersProvider.notifier).resubscribeOnline();
      } catch (_) {}
    }
  }

  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _loadFilter();
    // Story tray refresh DITUNDA ke post-frame pertama (bukan saat
    // provider dibuat) — RPC + realtime subscribe jangan berebut
    // dengan raster frame pertama.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier).refresh(silent: true);
      } catch (_) {}
      // Total user (registered + anon) — agregat ringan, ditunda ke
      // post-frame supaya tak berebut dengan raster pertama.
      try {
        ProviderScope.containerOf(context, listen: false).read(onlineUsersProvider.notifier).fetchUserCounts();
      } catch (_) {}
      // Rekonsiliasi efek channel ke privasi: kalau terakhir channel "Teman"
      // (persisted) tapi override presence belum tercatat (mis. app baru
      // dibuka), terapkan sekarang supaya konsisten.
      _reconcileChannelPresence();
    });
    _requestGpsOnce();
  }

  /// Pastikan efek channel ke presence-visibility diri sendiri konsisten dgn
  /// channel yang tersimpan (dipanggil sekali saat layar dibuka).
  Future<void> _reconcileChannelPresence() async {
    if (_channel != OnlineChannel.friends) return;
    final notifier = ref.read(privacyProvider.notifier);
    if (ref.read(privacyProvider).loading) {
      await notifier.load();
    }
    if (!mounted) return;
    final current = ref.read(privacyProvider).settings.presence;
    if (current != PrivacyVisibility.friends) {
      _presenceBeforeFriends ??= current;
      await notifier.update(presence: PrivacyVisibility.friends);
      await _saveFilter();
    }
  }

  /// Minta izin GPS saat masuk menu pengguna online (dialog native muncul
  /// sekali; kalau ditolak, user tetap bisa aktifkan lewat "bagikan lokasi").
  ///
  /// PERF (terukur): GPS hanya dijalankan SEKALI per install, bukan tiap
  /// layar dibuka. Alasan: menu Online adalah TAB DEFAULT → dipanggil tiap
  /// app dibuka/resume. Setiap panggilan membuat
  /// `GeolocatorLocationService` ter-BIND ke proses → MIUI menganggap app
  /// "aktif terus" (proses tak pernah di-freeze, oom_score_adj=0) → panel
  /// tidak masuk mode hemat → frame pertama setelah resume menunggu panel
  /// bangun ~180ms (framestats: ui_work=0ms, Vsync melompat). App yang mulus
  /// di HP ini (Shopee/WhatsApp) justru CACHED (oom 701).
  /// Posisi sudah tersimpan server-side; Nearby memanggil updateMyLocation
  /// sendiri saat dibuka (butuh akurasi saat itu juga).
  Future<void> _requestGpsOnce() async {
    final loc = ProviderScope.containerOf(context, listen: false).read(locationProvider).location;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_gpsRequestedKey) ?? false) return;
      final ok = await loc.requestPermission();
      if (!ok) return;
      await prefs.setBool(_gpsRequestedKey, true);
      await loc.updateMyLocation();
    } catch (_) {}
  }

  /// Bandingkan dua peta unread (uid→count) — supaya emit chat-list yang tidak
  /// mengubah badge unread TIDAK me-rebuild seluruh halaman Online.
  bool _unreadMapEquals(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unreadSub?.cancel();
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    if (_hiddenOwner != auth.uid) {
      _hiddenOwner = auth.uid;
      try {
        ProviderScope.containerOf(context, listen: false).read(onlineUsersProvider.notifier).setOwner(auth.uid);
      } catch (_) {}
    }
    if (auth.uid != null) {
      _unreadSub = ProviderScope.containerOf(context, listen: false)
          .read(chatProvider.notifier)
          .getMyPrivateChats(auth.uid!)
          .listen((chats) {
            if (!mounted) return;
            final map = <String, int>{};
            for (final c in chats) {
              final otherUid = c.participants.firstWhere(
                (p) => p != auth.uid,
                orElse: () => '',
              );
              if (otherUid.isNotEmpty) {
                final count = c.unreadCounts[auth.uid] ?? 0;
                if (count > 0) map[otherUid] = count;
              }
            }
            // PERF: dulu setState TIAP emit chat list (pesan baru/read/pin dari
            // chat mana pun) → SELURUH halaman Online (story tray + 20 kartu +
            // avatar) rebuild — terukur `build Online=170` dalam sesi singkat.
            // Sekarang hanya rebuild bila peta unread benar-benar BERUBAH.
            if (_unreadMapEquals(_unreadMap, map)) return;
            setState(() => _unreadMap = map);
          }, onError: (e) {
            // OFFLINE: stream chat-list error → jangan tak tertangkap.
            debugPrint('[NAV] unread stream error online: $e');
          });
    }
  }

  Future<void> _loadFilter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Migrasi legacy single ('all' | 1 negara) → list.
      final legacy = prefs.getString(_prefKeyNegara);
      _negaraSel =
          prefs.getStringList(_prefKeyNegaraList) ??
          (legacy != null && legacy != 'all' ? [legacy] : const []);
      _gender = prefs.getString(_prefKeyGender) ?? 'all';
      _channel = OnlineChannel.fromWire(prefs.getString(_prefKeyChannel));
      final before = prefs.getString(_prefKeyPresenceOverrideBefore);
      _presenceBeforeFriends = (before == null || before.isEmpty)
          ? null
          : PrivacyVisibility.fromWire(before);
    });
  }

  Future<void> _saveFilter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKeyNegaraList, _negaraSel);
    await prefs.setString(_prefKeyGender, _gender);
    await prefs.setString(_prefKeyChannel, _channel.wire);
    final before = _presenceBeforeFriends;
    if (before == null) {
      await prefs.remove(_prefKeyPresenceOverrideBefore);
    } else {
      await prefs.setString(_prefKeyPresenceOverrideBefore, before.wireKey);
    }
  }

  bool _uploadingAvatar = false;

  Future<void> _pickAndUploadAvatar() async {
    return pickAndUploadAvatarFromOnline(
      context,
      onUploadingChanged: (v) {
        if (mounted) setState(() => _uploadingAvatar = v);
      },
    );
  }


  void _showAvatarZoom(String b64, Color bgColor, String initial) {
    showAvatarZoomDialog(
      context,
      b64: b64,
      bgColor: bgColor,
      initial: initial,
    );
  }


  /// Sheet "Status kamu" — jawab: "bagaimana orang lain melihatku?".
  ///
  /// Menampilkan DUA dimensi yang sengaja DIPISAH (tidak disatukan):
  ///   1. STATUS asli (fakta teknis): Online / Idle / Offline.
  ///   2. TERLIHAT OLEH (efek privasi per-audiens) — chip + subbaris.
  ///
  /// `invisible` (ghost) BUKAN status: user tetap Online, hanya tampak
  /// Offline ke sebagian/semua orang. Karena itu ia muncul sebagai badge
  /// terpisah + efeknya dinyatakan di baris visibilitas (bukan ditulis
  /// "Invisible" yang menyesatkan).
  Future<void> _showMyStatusSheet() async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    // Muat visibilitas bila belum pernah dimuat (lazy; tak ada RPC baru bila
    // sudah ter-cache di provider).
    unawaited(ref.read(privacyProvider.notifier).load());

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgScreen,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => MyStatusSheet(
        s: s,
        uid: auth.uid ?? '',
        nickname: auth.profile?.nickname ?? '-',
        avatar: auth.profile?.avatar ?? '',
        gender: auth.profile?.gender ?? '',
        status: auth.profile?.status ?? 'offline',
        invisible: auth.invisibleEnabled,
        // Tap avatar header → zoom besar (dialog foto). Pakai bytes cache
        // avatar sendiri bila ada, else b64 dari profil.
        onAvatarTap: () {
          final nick = auth.profile?.nickname ?? '-';
          final init = (nick.isEmpty ? '?' : nick)[0].toUpperCase();
          Uint8List? bytes = ua.cachedUserAvatarBytes(auth.uid ?? '');
          final src = auth.profile?.avatar ?? '';
          if (bytes == null && src.isNotEmpty && !src.startsWith('avatars/')) {
            try {
              bytes = base64Decode(src);
            } catch (_) {}
          }
          _showAvatarZoom(
            bytes != null ? base64Encode(bytes) : '',
            AppTheme.primary,
            init,
          );
        },
      ),
    );
  }

  /// Zoom foto profil user lain: pakai bytes cache global kalau ada (b64
  /// langsung / path dari disk), else download path → tampilkan dialog.
  Future<void> _zoomUserAvatar(UserModel user, Color color) async {
    Uint8List? bytes = ua.cachedUserAvatarBytes(user.uid);
    final src = user.avatar;
    if (bytes == null && src.isNotEmpty && !src.startsWith('avatars/')) {
      try {
        bytes = base64Decode(src);
      } catch (_) {}
    }
    if (bytes == null && src.startsWith('avatars/')) {
      try {
        bytes =
            MediaDiskCache.instance.readSync(src) ??
            await MediaDiskCache.instance.read(src) ??
            await ProviderScope.containerOf(context, listen: false).read(storageProvider).downloadBytes(src);
      } catch (_) {}
    }
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      _showAvatarZoom(base64Encode(bytes), color, user.initial);
    } else {
      _showAvatarZoom('', color, user.initial);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _unreadSub?.cancel();
    _dismissUnreadBubble();
    super.dispose();
  }

  // ── Story: buka komposer (kamera + galeri satu halaman → composer) ──
  /// Buka "Orang Sekitar". Registered only — anon dapat popup "lengkapi email"
  /// (form modular sama dengan aksi lain; teks khusus konteks Orang Sekitar).
  void _openNearby() {
    final s = ref.read(localeProvider).s;
    final registered = ref.read(authProvider).profile?.isRegistered ?? false;
    if (!registered) {
      showAnonPromptDialog(
        context,
        title: s.promptCompleteEmailNearbyTitle,
        message: s.promptCompleteEmailNearbyMsg,
        icon: Icons.explore_outlined,
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NearbyScreen()),
    );
  }

  /// Terapkan efek channel ke setelan privasi DIRI SENDIRI:
  /// - channel "Teman" → override presence jadi `friends` (Status kamu
  ///   terlihat oleh = Teman). Nilai asli (Kelola Privasi) disimpan dulu.
  /// - channel "Semua"  → kembalikan presence ke nilai asli tadi.
  /// Restore hanya dilakukan bila memang ada override aktif (tak menimpa
  /// perubahan manual di Kelola Privasi saat channel "Semua").
  Future<void> _applyChannelPresence(OnlineChannel next) async {
    final notifier = ref.read(privacyProvider.notifier);
    // Pastikan setelan termuat sebelum menyimpan nilai asli.
    if (!ref.read(privacyProvider).loading &&
        ref.read(privacyProvider).settings == const PrivacySettings()) {
      await notifier.load();
    }
    if (next == OnlineChannel.friends) {
      final current = ref.read(privacyProvider).settings.presence;
      if (current != PrivacyVisibility.friends) {
        // Simpan nilai asli SEKALI (kalau sudah ter-override, jangan timpa).
        _presenceBeforeFriends ??= current;
        await notifier.update(presence: PrivacyVisibility.friends);
        await _saveFilter();
      }
    } else {
      // Channel "Semua" → pulihkan setelan default.
      final before = _presenceBeforeFriends;
      if (before != null) {
        _presenceBeforeFriends = null;
        await notifier.update(presence: before);
        await _saveFilter();
      }
    }
  }

  /// Snackbar keterangan channel — menjelaskan beda "Semua" vs "Teman"
  /// (termasuk efek ke visibilitas status diri). Gaya konsisten dgn snackbar
  /// lain (ikon + teks, durasi pendek).
  void _showChannelInfo(OnlineChannel c) {
    if (!c.isFilter) return;
    final s = ref.read(localeProvider).s;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    // Floating snackbar OTOMATIS berada di atas bottomNavigationBar — cukup
    // jarak kecil. Jangan tambah inset lagi (dulu dobel → snackbar naik ke
    // tengah layar).
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        content: Row(
          children: [
            Icon(c.icon, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c == OnlineChannel.friends
                    ? s.channelFriendsDesc
                    : s.channelAllDesc,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openStoryComposer() async {
    // Picker ala IG: preview kamera live + strip galeri di bawah —
    // jepret ATAU pilih foto galeri dalam satu halaman.
    final picked = await Navigator.push<Object>(
      context,
      MaterialPageRoute(builder: (_) => const StoryCameraPickerScreen()),
    );
    if (picked == null || !mounted) return;
    // Penanda video EKSPLISIT dari kamera (galeri selalu foto) — jangan
    // tebak dari ekstensi file (kamera Xiaomi bisa beda ekstensi).
    final File file;
    final bool isVideo;
    if (picked is StoryCaptureResult) {
      file = picked.file;
      isVideo = picked.isVideo;
    } else if (picked is File) {
      file = picked;
      isVideo = false;
    } else {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StoryComposerScreen(picked: XFile(file.path), isVideo: isVideo),
      ),
    );
    if (mounted) {
      // Refresh tray (optimistic di provider sudah jalan; ini sinkron
      // ulang untuk urutan + unseen dari server).
      ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier).refresh(silent: true);
    }
  }



  void _openViewer(List<StoryTrayItem> items, int index) {
    if (items.isEmpty) return;
    final tapped =
        items[index.clamp(0, items.length - 1)];
    // Yang dibenamkan tidak ikut paging otomatis — buka hanya author itu
    // bila memang tile-nya yang diketuk sengaja.
    final visible = tapped.muted
        ? [tapped]
        : items.where((t) => !t.muted).toList();
    if (visible.isEmpty) return;
    final target = tapped.muted
        ? 0
        : visible.indexWhere((t) => t.authorId == tapped.authorId).clamp(
            0,
            visible.length - 1,
          );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(items: visible, initialIndex: target),
      ),
    );
  }

  bool _scrollDebounce = false;

  void _onScroll() {
    if (_scrollDebounce) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 100) {
      _scrollDebounce = true;
      _page++;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _scrollDebounce = false;
      });
    }
  }

  Future<void> _startChat(BuildContext context, UserModel user) async {
    return startPrivateChatFromOnline(
      context,
      user,
      onBeforeNav: _dismissUnreadBubble,
    );
  }


  // Sembunyikan TANPA snackbar: swipe beruntun + bar transient = bar
  // seolah nempel/muncul terus. Feedback-nya = kotak bawah otomatis
  // terbuka menampilkan orangnya + tombol Tampilkan per kartu (tanpa
  // timeout, jauh lebih jelas daripada snackbar 3 detik).
  Future<void> _hideUser(UserModel user) async {
    if (!mounted) return;
    try {
      await ProviderScope.containerOf(context, listen: false).read(onlineUsersProvider.notifier).hideUser(user.uid);
    } catch (_) {}
    if (!mounted) return;
    // Langsung buka kotak bawah supaya user MELIHAT ke mana perginya.
    // Tanpa reset `_page`: hide 1 user tidak boleh melempar scroll ke atas.
    setState(() => _showHidden = true);
  }

  Future<void> _unhideUser(UserModel user) async {
    if (!mounted) return;
    // Box ikut rebuild lewat notify provider; tidak perlu setState khusus.
    try {
      await ProviderScope.containerOf(context, listen: false).read(onlineUsersProvider.notifier).unhideUser(user.uid);
    } catch (_) {}
  }

  Future<void> _showUnreadBubble(
    BuildContext cardCtx,
    UserModel user,
    int unreadCount,
    Offset globalPos,
    Rect cardRect,
  ) async {
    final entry = await showUnreadBubbleOverlay(
      cardCtx: cardCtx,
      user: user,
      unreadCount: unreadCount,
      globalPos: globalPos,
      cardRect: cardRect,
    );
    if (entry == null) return;
    // Simpan referensi supaya bisa dipaksa-remove saat halaman di-pop / user
    // membuka chat — TIDAK hanya mengandalkan timer 4 dtk. Kalau overlay
    // tertinggal (timer belum jalan / entry.mounted false), `Positioned.fill`
    // transparannya menelan tap → gejala "balik dari chat, list Online susah
    // diklik". _unreadBubbleEntry lama di-remove dulu (anti tumpuk).
    _unreadBubbleEntry?.remove();
    _unreadBubbleEntry = entry;
    // Auto-tutup 4 dtk. `remove()` dibungkus try/catch: overlay yang sudah
    // di-unmount bisa melempar saat remove().
    Future.delayed(const Duration(seconds: 4), () {
      try {
        if (identical(_unreadBubbleEntry, entry)) _unreadBubbleEntry = null;
        entry.remove();
      } catch (_) {}
    });
  }

  /// Buang bubble unread overlay kalau masih ada (anti penghalang tap).
  void _dismissUnreadBubble() {
    final e = _unreadBubbleEntry;
    _unreadBubbleEntry = null;
    if (e != null) {
      try {
        e.remove();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Online');
    // select (bukan watch): heartbeat presence AuthNotifier berubah tiap
    // beberapa detik — watch membuat SELURUH halaman (Scaffold + tray story
    // + ListView) rebuild tiap kali walau tak ada yang terlihat berubah.
    // Hanya field yang dipakai untuk render yang di-listen.
    final authUid = ref.watch(authProvider.select((a) => a.uid));
    final myAvatar = ref.watch(
      authProvider.select((a) => a.profile?.avatar ?? ''),
    );
    final myNickname = ref.watch(
      authProvider.select((a) => a.profile?.nickname ?? '-'),
    );
    final myRegistered = ref.watch(
      authProvider.select((a) => a.profile?.isRegistered ?? false),
    );
    // Status diri sendiri + ghost mode — untuk dot badge di avatar sendiri.
    final myStatus = ref.watch(
      authProvider.select((a) => a.profile?.status ?? 'offline'),
    );
    final myInvisible = ref.watch(
      authProvider.select((a) => a.invisibleEnabled),
    );
    // Set teman (mutual follow) — sumber filter channel "Teman". Di-watch
    // granular (hanya Set-nya) supaya perubahan lain di SocialProvider tak
    // me-rebuild halaman. Sinkron ke `_friendSet` saat berubah saja.
    final friends = ref.watch(socialProvider.select((sp) => sp.friends));
    if (!setEquals(friends, _friendSet)) {
      _friendSet = Set.of(friends);
    }
    super.build(context);
    final s = ref.watch(localeProvider).s;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppTheme.bgScreen,
      appBar: OnlineAppBar(
        s: s,
        authUid: authUid,
        friendSet: _friendSet,
        channel: _channel,
        isSearching: _isSearching,
        search: _search,
        searchCtrl: _searchCtrl,
        storyTray: StoryTraySection(
          resolveOwnAvatar: _resolveOwnAvatar,
          imageForBytes: _cappedAvatarImage,
          myAvatar: myAvatar,
          myNickname: myNickname,
          myRegistered: myRegistered,
          myStatus: myStatus,
          invisible: myInvisible,
          uploadingAvatar: _uploadingAvatar,
          onShowMyStatus: () => _showMyStatusSheet(),
          onAvatarZoom: _showAvatarZoom,
          onPickAndUploadAvatar: _pickAndUploadAvatar,
          onOpenStoryComposer: _openStoryComposer,
          onOpenViewer: _openViewer,
        ),
        onToggleSearch: () {
          setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) {
              _searchCtrl.clear();
              _search = '';
              _page = 1;
            }
          });
        },
        onClearSearch: () {
          _searchCtrl.clear();
          setState(() {
            _search = '';
            _page = 1;
          });
        },
        onSearchChanged: (v) => setState(() {
          _search = v;
          _page = 1;
        }),
        onOpenStoryComposer: _openStoryComposer,
        onChannelSelected: (v) {
          // "Orang Sekitar" = aksi navigasi (bukan filter channel).
          if (v == OnlineChannel.nearby) {
            _openNearby();
            return;
          }
          setState(() {
            _channel = v;
            _page = 1;
          });
          _saveFilter();
          // Efek ke privasi diri: Teman → override, Semua → restore.
          _applyChannelPresence(v);
          // Keterangan singkat beda tiap channel.
          _showChannelInfo(v);
        },
      ),
      body: Stack(
        children: [
          rv.Consumer(
            builder: (ctx, ref, __) {
              final provider = ref.watch(onlineUsersProvider);
              PerfProbe.buildCount('Online.list');
              final chat = ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier);
              // Ukur biaya filter per emission (kandidat optimasi QA).
              // Partisi: utama = filter penuh + !hidden; kotak bawah =
              // semua hidden (abaikan negara/gender/search, hormati blokir)
              // supaya yang dibenam tetap di bawah walau online.
              late List<UserModel> users;
              late List<UserModel> hiddenUsers;
              PerfProbe.measure('Online.filter', () {
                final allUsers = provider.users
                    .where((u) => u.uid != authUid && !chat.isBlocked(u.uid))
                    .toList();

                // Pertahanan tampilan: dedupe by uid (dan nickname) — jika ada
                // duplikat lolos dari stream/cache, kartu tidak boleh tampil 2x.
                final seenU = <String>{};
                final seenN = <String>{};
                final base = allUsers.where((u) {
                  if (!seenU.add(u.uid)) return false;
                  if (!seenN.add(u.nickname.toLowerCase())) return false;
                  return true;
                }).toList();
                // Channel "Teman": hanya teman (mutual follow) yang tampil —
                // termasuk kotak "dibenam" (hidden). "Semua" = tanpa saringan
                // channel (privasi presence tetap dijaga server).
                final onlyFriends = _channel == OnlineChannel.friends;
                hiddenUsers = base
                    .where((u) =>
                        provider.isHidden(u.uid) &&
                        (!onlyFriends || _friendSet.contains(u.uid)))
                    .toList();
                users = base.where((u) {
                  if (provider.isHidden(u.uid)) return false;
                  if (onlyFriends && !_friendSet.contains(u.uid)) {
                    return false;
                  }
                  if (_negaraSel.isNotEmpty &&
                      !_negaraSel.contains(u.country)) {
                    return false;
                  }
                  if (_gender != 'all' && u.gender != _gender) {
                    return false;
                  }
                  if (_search.isNotEmpty &&
                      !u.nickname
                          .toLowerCase()
                          .contains(_search.toLowerCase())) {
                    return false;
                  }
                  return true;
                }).toList();
              });

              return OnlineUserListSection(
                s: s,
                channel: _channel,
                friendSet: _friendSet,
                users: users,
                hiddenUsers: hiddenUsers,
                unreadMap: _unreadMap,
                hasLoaded: provider.hasLoaded,
                showHidden: _showHidden,
                page: _page,
                scrollCtrl: _scrollCtrl,
                negaraSel: _negaraSel,
                gender: _gender,
                search: _search,
                onNegaraChanged: (v) {
                  setState(() {
                    _negaraSel = v;
                    _page = 1;
                  });
                  _saveFilter();
                },
                onGenderChanged: (v) => _applyGenderFilter(v, s),
                onToggleHidden: () =>
                    setState(() => _showHidden = !_showHidden),
                onOutOfPoints: ({required outOfPoints, required s}) {},
                onHideUser: _hideUser,
                onUnhideUser: _unhideUser,
                onStartChat: _startChat,
                onZoomAvatar: _zoomUserAvatar,
                onShowUnread: _showUnreadBubble,
              );
            },
          ),
          // Menu cepat tepi kanan: dua pintasan (Timeline + Global Room).
          // Menggantikan kapsul lama yang bergantian tiap jam.
          // PENTING: dibungkus Positioned.fill AGAR dapat constraints penuh
          // (widget mengembalikan Stack + Positioned sendiri). Bila dipasang
          // langsung sebagai anak Stack non-positioned, constraints longgar →
          // menu tidak ter-layout / tak tampil.
          Positioned.fill(
            child: QuickSideMenu(
              onOpenRoom: () => _openGeneralRoom(context),
              onCreateGroup: () => showCreateGroupDialog(context),
              ownerUid: authUid,
            ),
          ),
        ],
      ),
    );
  }

  /// ID room General Indonesia (global room resmi). Pintasan "Global Room"
  /// di halaman Online SELALU membuka room ini — TIDAK memakai `rooms.first`
  /// yang urutannya berubah mengikuti jumlah online (dulu kadang masuk
  /// "room faisol" user-made, kadang "General" — tidak konsisten).
  static const String _kGlobalRoomId = 'Indonesia_general';

  /// Buka Global Room kategori General NEGARA INDONESIA (selalu room yang sama).
  Future<void> _openGeneralRoom(BuildContext context) async {
    final rp = ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier);

    // 1) Prioritas: room resmi dari daftar explore yang sudah termuat.
    var room = rp.exploreRoomById(_kGlobalRoomId);
    // 2) Belum termuat (mis. negara user bukan Indonesia) → ambil langsung.
    if (room == null) {
      final raw = await rp.fetchRoomById(_kGlobalRoomId);
      if (raw != null) {
        room = RoomModel.fromMap('${raw['id']}', raw);
      }
    }
    if (!context.mounted) return;

    if (room != null) {
      final target = room;
      unawaited(rp.markRoomRead(target.id));
      final navKey = navKeyRoom(target.id);
      if (!tryClaimNav(navKey)) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RoomChatScreen(room: target)),
      ).then((_) => releaseNav(navKey));
      return;
    }

    // Room resmi belum ada (seeding belum jalan) → buka HALAMAN Global Room
    // dengan kategori General terpilih.
    rp.setExploreCategory('general');
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LobbyScreen(initialCategory: 'general'),
      ),
    );
  }

  /// Terapkan filter gender (dari SearchDropdown). Filter gender berbayar
  /// (harian) — gate server saat fitur sudah dipublish. Pilih 'all' = gratis.
  Future<void> _applyGenderFilter(String v, S s) async {
    if (v != 'all') {
      final pp = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(pointsProvider.notifier);
      if (pp.genderFilterPublished) {
        try {
          await pp.gateFeature(
            'gender_filter',
            priceFeature: 'filter_gender',
          );
        } on PostgrestException catch (e) {
          if (!mounted) return;
          if (e.message.contains('tidak cukup') ||
              e.message.contains('Not enough')) {
            pp.showOutOfPointsDialog(context, s.isId);
          } else {
            dlog('[ONLINE] gate gender error: $e');
          }
          return;
        } catch (e) {
          if (!mounted) return;
          dlog('[ONLINE] gate gender error: $e');
          return;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _gender = v;
      _page = 1;
    });
    _saveFilter();
  }
}
