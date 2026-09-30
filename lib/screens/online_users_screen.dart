import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/storage_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/online_users_provider.dart';
import '../providers/points_provider.dart';
import '../providers/room_provider.dart';
import '../widgets/search_dropdown.dart';
import '../widgets/skeleton_card.dart';
import 'online_users/widgets/hidden_box_widgets.dart';
import '../core/cache/media_disk_cache.dart';
import '../core/nav_guard.dart';
import '../core/ui/online_pill_mode.dart';
import '../models/story_model.dart';
import '../providers/social_provider.dart';
import '../providers/timeline_provider.dart';
import '../utils/bounded_cache.dart';
import '../models/message_model.dart';
import 'private_chat_screen.dart';
import 'nearby_screen.dart';
import 'room_chat_screen.dart';
import 'lobby_screen.dart';
import 'story_composer_screen.dart';
import 'story_camera_capture_screen.dart';
import 'story_camera_picker_screen.dart';
import 'story_viewer_screen.dart';
import '../providers/story_provider.dart';
import '../providers/call_provider.dart';
import '../core/perf/perf_probe.dart';
import '../widgets/app_gesture.dart';
import '../widgets/anon_prompt_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

final _avatarCache = BoundedCache<String, Uint8List>(80);

// Cache byte avatar per-UID GLOBAL — bertahan antar state/widget rebuild.
// Urutan list bisa berubah tiap event presence; tanpa cache global, state
// widget ter-recycle → decode ulang → inisial sebentar = kedip.
final Map<String, Uint8List> _avatarBytesByUid = {};
final Map<String, String> _avatarLastSrcByUid = {};

// MemoryImage instance STABIL per-UID — dipisahkan total dari data
// pengguna online yang berganti-ganti tiap event presence. Bitmap di-decode
// SEKALI per foto; rebuild list berapapun tidak menyentuh bitmap.
final Map<String, MemoryImage> _avatarImageByUid = {};

void clearAllAvatarCaches() {
  _avatarCache.clear();
  _avatarBytesByUid.clear();
  _avatarLastSrcByUid.clear();
  _avatarImageByUid.clear();
}

// Batas ukuran map avatar global — tanpa ini, 3 map tumbuh seumur sesi
// (1 entry per user yang pernah terlihat) → risiko memori besar di HP
// low-end saat sesi panjang. Evict FIFO (urutan insert) kalau lewat cap.
const _avatarMapCap = 200;

void _boundAvatarMap(Map<String, Object?> m) {
  while (m.length > _avatarMapCap) {
    m.remove(m.keys.first);
  }
}

String? _processAvatarImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(
    decoded,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.cubic,
  );
  return base64Encode(img.encodeJpg(resized, quality: 90));
}

// Avatar SELALU JPEG (sama seperti profile_screen & foto chat). Dulu memakai
// encoder WebP native FlutterImageCompress, tapi hasilnya membawa ICC
// profile/krominansi yang tidak konsisten antar-device → avatar tampil
// "biro-biro" saat dilihat dari HP lain lewat CDN. JPEG polos universal.
Future<String?> _processAvatarJpeg(Uint8List bytes) async {
  return _processAvatarImage(bytes);
}

class _AsyncAvatar extends StatefulWidget {
  final String uid;
  final String avatarB64;
  final String initial;
  final Color color;
  // Ring warna digambar DI DALAM sini supaya hanya muncul saat placeholder
  // inisial — foto yang sudah tampil tidak kena ring (lihat ProfileAvatar).
  final Color? borderColor;
  final double borderWidth;
  const _AsyncAvatar({
    super.key,
    required this.uid,
    required this.avatarB64,
    required this.initial,
    required this.color,
    this.borderColor,
    this.borderWidth = 1.5,
  });

  @override
  State<_AsyncAvatar> createState() => _AsyncAvatarState();
}

/// Decode base64 avatar di isolate — B64 besar dari network tidak boleh
/// block UI thread saat scroll list online.
Uint8List? _decodeAvatarB64Iso(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

class _AsyncAvatarState extends State<_AsyncAvatar> {
  MemoryImage? _provider;
  String? _asyncResolvingFor;

  /// UID pendek untuk log — aman untuk uid kosong/pendek.
  String get _uid8 => widget.uid.length >= 8
      ? widget.uid.substring(0, 8)
      : widget.uid.isEmpty
      ? '-'
      : widget.uid;

  @override
  void initState() {
    super.initState();
    _resolve();
    // Tanpa Timer.periodic(300ms) per kartu: decode isolate & tulis disk
    // async yang mendarat setelah frame pertama di-resolve via didUpdateWidget
    // (provider notifyListeners → parent rebuild) ATAU callback .then pada
    // compute() di bawah. Hemat 1 timer per kartu dalam list panjang.
  }

  void _resolve() {
    final src = widget.avatarB64;
    // Batasi map global sebelum tulis baru — evict FIFO kalau lewat cap.
    // CATATAN: `_avatarLastSrcByUid` SENGAJA tidak di-evict. Map itu hanya
    // menyimpan string pendek (path/base64), tapi jadi kunci "sumber sama"
    // di bawah — kalau entry-nya terbuang saat list panjang, decode ulang
    // jalan percuma dan satu kegagalan decode sempat mengosongkan foto
    // (gejala "kadang ada kadang hilang").
    _boundAvatarMap(_avatarBytesByUid);
    _boundAvatarMap(_avatarImageByUid);
    final srcType = src.isEmpty
        ? 'EMPTY'
        : src.startsWith('avatars/')
        ? 'PATH'
        : 'B64';
    // Sumber sama & provider sudah ada → nol pekerjaan (paling sering).
    if (src == _avatarLastSrcByUid[widget.uid] && _provider != null) {
      dlog(
        '[AVATAR] $_uid8 KEEP ($srcType) t=${DateTime.now().millisecondsSinceEpoch % 100000}',
      );
      return;
    }
    _avatarLastSrcByUid[widget.uid] = src;
    if (src.isEmpty) {
      // Kosong → pertahankan provider lama (jangan kedip ke inisial).
      dlog('[AVATAR] $_uid8 EMPTY keep-old=${_provider != null}');
      return;
    }
    // Sumber non-kosong dan BARU (atau provider hilang) → buang bytes +
    // provider lama milik uid ini. Maps per-uid di bawah memakai `??=` /
    // `putIfAbsent` yang tidak pernah menimpa — tanpa ini foto lama tersaji
    // selamanya: user ganti avatar tidak muncul di list online HP lain
    // sampai restart app (State kartu dipertahankan antar-reorder, jadi
    // inilah satu-satunya jalur update foto).
    final staleProvider = _avatarImageByUid.remove(widget.uid);
    _avatarBytesByUid.remove(widget.uid);
    _provider = null;
    if (staleProvider != null) {
      try {
        PaintingBinding.instance.imageCache.evict(staleProvider);
      } catch (_) {}
    }
    // PATH storage → baca bytes dari MEDIA DISK CACHE (instan, tanpa
    // network) → foto langsung tampil bahkan di mount pertama.
    if (src.startsWith('avatars/')) {
      final disk = MediaDiskCache.instance.readSync(src);
      if (disk != null && disk.isNotEmpty) {
        _avatarBytesByUid[widget.uid] ??= disk;
        _provider = _avatarImageByUid.putIfAbsent(
          widget.uid,
          () => MemoryImage(_avatarBytesByUid[widget.uid]!),
        );
        _boundAvatarMap(_avatarBytesByUid);
        _boundAvatarMap(_avatarImageByUid);
        dlog('[AVATAR] $_uid8 FROM-DISK');
      }
      // Tidak ada di disk → biarkan inisial; batch network akan mengisi.
      return;
    }
    // Instance MemoryImage stabil per-uid → pakai apa adanya.
    final stable = _avatarImageByUid[widget.uid];
    if (stable != null && _provider != stable) {
      dlog(
        '[AVATAR] $_uid8 SWAP-STABLE t=${DateTime.now().millisecondsSinceEpoch % 100000}',
      );
      _provider = stable;
      return;
    }
    // Decode sinkron (murah — server sudah q70/300px) lalu simpan
    // instance ImageProvider sekali selamanya untuk uid ini.
    if (_avatarBytesByUid[widget.uid] == null) {
      Uint8List? b;
      final cached = _avatarCache.get(src);
      if (cached != null) {
        b = cached;
      } else if (src.length > 100000 && _asyncResolvingFor != src) {
        // B64 besar dari network batch → decode di isolate agar scroll
        // tidak jank; poll initState menampilkan hasilnya saat siap.
        _asyncResolvingFor = src;
        compute(_decodeAvatarB64Iso, src).then((decoded) {
          _asyncResolvingFor = null;
          if (decoded == null || decoded.isEmpty) {
            dlog(
              '[AVATAR] $_uid8 DECODE-FAIL(async) keep-old=${_provider != null}',
            );
            return;
          }
          // Foto sudah berganti saat decode berjalan → buang hasil basi
          // (jangan timpa foto baru dengan foto lama).
          if (_avatarLastSrcByUid[widget.uid] != src) {
            dlog('[AVATAR] $_uid8 STALE-DECODE dropped');
            return;
          }
          _avatarCache.putIfAbsent(src, () => decoded);
          _avatarBytesByUid[widget.uid] ??= decoded;
          _avatarImageByUid.putIfAbsent(
            widget.uid,
            () => MemoryImage(_avatarBytesByUid[widget.uid]!),
          );
          _boundAvatarMap(_avatarBytesByUid);
          _boundAvatarMap(_avatarImageByUid);
          if (mounted)
            setState(() => _provider = _avatarImageByUid[widget.uid]);
        });
        return;
      } else if (src.length > 100000) {
        return;
      } else {
        try {
          final decoded = base64Decode(src);
          _avatarCache.putIfAbsent(src, () => decoded);
          b = decoded;
        } catch (_) {
          b = null;
        }
      }
      if (b == null) {
        // ── JANGAN buang foto yang sudah tampil ──
        // Satu emission dengan base64 rusak/kecil tidak boleh mengosongkan
        // kartu: pertahankan `_provider` lama dan tunggu emission berikutnya
        // membawa data benar. Dulu `_provider = null` di sini → foto hilang
        // (transparan) sampai batch network menyusul = "kadang ada kadang
        // hilang".
        dlog(
          '[AVATAR] $_uid8 DECODE-FAIL(sync) len=${src.length} '
          'keep-old=${_provider != null}',
        );
        return;
      }
      _avatarBytesByUid[widget.uid] = b;
    }
    _provider = _avatarImageByUid.putIfAbsent(
      widget.uid,
      () => MemoryImage(_avatarBytesByUid[widget.uid]!),
    );
    _boundAvatarMap(_avatarBytesByUid);
    _boundAvatarMap(_avatarImageByUid);
  }

  @override
  void didUpdateWidget(covariant _AsyncAvatar old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    _resolve();
    final p = _provider;
    if (p == null) {
      // Avatar ADA (PATH/B64) tapi bytes belum siap → TRANSPARAN, jangan
      // tampilkan huruf inisial dulu (user tidak mau flash "S" → foto).
      // Huruf hanya untuk yang memang tidak punya foto (string kosong).
      if (widget.avatarB64.isNotEmpty) {
        return const SizedBox.shrink();
      }
      final letter = Center(
        child: Text(
          widget.initial,
          style: TextStyle(
            color: widget.color,
            fontSize: AppGlyph.avatarInitial(40),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      // Placeholder inisial: pakai ring kalau diminta. Foto/loading:
      // tanpa ring supaya foto gelap tidak terlihat bercacat biru.
      if (widget.borderColor == null) return letter;
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.borderColor!,
            width: widget.borderWidth,
          ),
        ),
        child: letter,
      );
    }
    // gaplessPlayback: foto benar-benar baru (bytes beda) → bitmap lama
    // tetap tampil sampai bitmap baru siap, tanpa blank putih.
    return Image(
      image: p,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Center(
        child: Text(
          widget.initial,
          style: TextStyle(
            color: widget.color,
            fontSize: AppGlyph.avatarInitial(40),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class OnlineUsersScreen extends StatefulWidget {
  const OnlineUsersScreen({super.key});

  @override
  State<OnlineUsersScreen> createState() => _OnlineUsersScreenState();
}

class _OnlineUsersScreenState extends State<OnlineUsersScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  // Multi-select negara: kosong = Semua. Persist via prefs (JSON list).
  List<String> _negaraSel = const [];
  // Single-select gender: all | male | female. Persist via prefs.
  String _gender = 'all';
  String _search = '';
  bool _isSearching = false;
  int _page = 1;
  static const int _pageSize = 20;
  static const _prefKeyNegara = 'filter_negara'; // legacy single
  static const _prefKeyNegaraList = 'filter_negara_multi';
  static const _prefKeyGender = 'filter_gender';
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  StreamSubscription<List<PrivateChatInfo>>? _unreadSub;
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
        context.read<StoryProvider>().refresh(silent: true);
      } catch (_) {}
      try {
        context.read<OnlineUsersProvider>().resubscribeOnline();
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
        context.read<StoryProvider>().refresh(silent: true);
      } catch (_) {}
    });
    _requestGpsOnce();
  }

  /// Minta izin GPS saat masuk menu pengguna online (dialog native muncul
  /// sekali; kalau ditolak, user tetap bisa aktifkan lewat "bagikan lokasi").
  Future<void> _requestGpsOnce() async {
    final loc = context.read<LocationProvider>().location;
    final ok = await loc.requestPermission();
    if (!ok) return;
    await loc.updateMyLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unreadSub?.cancel();
    final auth = context.read<AuthProvider>();
    if (_hiddenOwner != auth.uid) {
      _hiddenOwner = auth.uid;
      try {
        context.read<OnlineUsersProvider>().setOwner(auth.uid);
      } catch (_) {}
    }
    if (auth.uid != null) {
      _unreadSub = context
          .read<ChatProvider>()
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
    });
  }

  Future<void> _saveFilter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKeyNegaraList, _negaraSel);
    await prefs.setString(_prefKeyGender, _gender);
  }

  bool _uploadingAvatar = false;

  Future<void> _pickAndUploadAvatar() async {
    final s = context.read<LocaleProvider>().s;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.avatarGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s.menuTakePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final XFile? picked;
    try {
      // TANPA maxWidth/imageQuality — foto asli utuh diteruskan ke cropper
      // (kompresi cukup 1x di akhir proses) — sama dengan profile_screen.
      picked = await picker.pickImage(source: source);
    } catch (e) {
      dlog('[ONLINE] pickImage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoPermission)));
      }
      return;
    }
    if (picked == null || !mounted) return;

    // Crop interaktif 1:1 — geser/zoom pilih bagian yang masuk avatar.
    // Apa yang dilihat user di lingkaran = persis yang tersimpan.
    final CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 1024,
        maxHeight: 1024,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: s.avatarCamera,
            toolbarColor: AppTheme.bgScreen,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppTheme.primary,
            lockAspectRatio: true,
            // Edge-to-edge Android 15+: ikon status bar ikut terang/gelap
            // toolbar (jangan isi warna bar — API deprecated, ditolak Play).
            statusBarLight: !AppTheme.isDark,
          ),
          IOSUiSettings(title: s.avatarCamera, aspectRatioLockEnabled: true),
        ],
      );
    } catch (e) {
      dlog('[ONLINE] crop error: $e');
      return;
    }
    if (cropped == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await cropped.readAsBytes();
      if (!mounted) {
        setState(() => _uploadingAvatar = false);
        return;
      }

      final processed = await compute(_processAvatarJpeg, bytes);
      if (processed == null || !mounted) {
        setState(() => _uploadingAvatar = false);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errPhotoProcess)));
        }
        return;
      }

      final pp = context.read<AuthProvider>();
      await pp.updateAvatar(processed);
      if (mounted) {
        // Langsung patch list online & timeline supaya foto baru terlihat
        // tanpa pindah halaman / tunggu stream 30s
        try {
          final uid = pp.profile?.uid ?? '';
          if (uid.isNotEmpty) {
            context.read<OnlineUsersProvider>().updateAvatarForUid(
              uid,
              processed,
            );
            context.read<TimelineProvider>().refreshAvatarForUid(
              uid,
              processed,
            );
          }
        } catch (_) {}
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgProfileSaved)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoUpload)));
      }
    }
  }

  void _showAvatarZoom(String b64, Color bgColor, String initial) {
    Uint8List? bytes;
    if (b64.isNotEmpty) {
      try {
        bytes = base64Decode(b64);
      } catch (_) {}
    }
    if (bytes == null && initial.isEmpty) return;
    final zoomBytes = bytes;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: zoomBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        // Cap 1080px: dialog zoom tidak butuh full-res 12MP.
                        child: Image.memory(
                          zoomBytes,
                          fit: BoxFit.contain,
                          cacheWidth: 1080,
                        ),
                      )
                    : CircleAvatar(
                        radius: 90,
                        backgroundColor: bgColor,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppGlyph.xl,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Keluarkan bitmap zoom dari ImageCache (pola PhotoViewerScreen).
      if (zoomBytes != null && zoomBytes.isNotEmpty) {
        try {
          PaintingBinding.instance.imageCache.evict(MemoryImage(zoomBytes));
        } catch (_) {}
      }
    });
  }

  /// Zoom foto profil user lain: pakai bytes cache global kalau ada (b64
  /// langsung / path dari disk), else download path → tampilkan dialog.
  Future<void> _zoomUserAvatar(UserModel user, Color color) async {
    Uint8List? bytes = _avatarBytesByUid[user.uid];
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
            await context.read<StorageProvider>().downloadBytes(src);
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
    super.dispose();
  }

  // ── Story: buka komposer (kamera + galeri satu halaman → composer) ──
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
      context.read<StoryProvider>().refresh(silent: true);
    }
  }

  /// Avatar + nama sendiri sebagai TILE PERTAMA tray (ikut scroll
  /// horizontal seperti IG — bukan nempel di luar list).
  Widget _buildOwnAvatarTile(
    String myAvatar,
    String myNickname,
    bool myRegistered,
  ) {
    // Tile avatar sendiri TETAP di tengah tray (vertikal) — Center
    // mengembalikan posisi tengah seperti semula.
    return Center(
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () {
                    final b64 = myAvatar;
                    final init = (myNickname.isEmpty ? '?' : myNickname)[0]
                        .toUpperCase();
                    _showAvatarZoom(b64, AppTheme.primary, init);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Builder(
                      builder: (_) {
                        final b64 = myAvatar;
                        final bytes = _resolveOwnAvatar(b64);
                        // Huruf inisial HANYA kalau memang tidak ada
                        // avatar (string kosong). Selama bytes belum
                        // siap → lingkaran tint polos, tanpa flash "S".
                        final showInitial = b64.isEmpty;
                        return CircleAvatar(
                          radius: 27,
                          backgroundColor: AppTheme.primary.withValues(
                            alpha: 0.15,
                          ),
                          backgroundImage: bytes != null
                              ? MemoryImage(bytes)
                              : null,
                          child: showInitial
                              ? Text(
                                  (myNickname.isEmpty ? '?' : myNickname)[0]
                                      .toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: AppGlyph.avatarInitial(54),
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 3),
                        ],
                      ),
                      child: _uploadingAvatar
                          ? Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppTheme.primary,
                              ),
                            )
                          : Icon(
                              Icons.camera_alt,
                              color: AppTheme.primary,
                              size: 11,
                            ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      myNickname,
                      style: AppText.bodyStrong.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (myRegistered) ...[
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.verified,
                        size: 13,
                        color: Color(0xFF4A90E2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tray story horizontal — kotak portrait rounded + ring gradient
  /// (belum dilihat) / putih (sudah). Slot 0 = avatar sendiri (ikut
  /// scroll); lalu tile "+" kalau belum punya story; lalu tile story.
  Widget _buildStoryTray(
    BuildContext ctx,
    String myAvatar,
    String myNickname,
    bool myRegistered,
  ) {
    final sp = ctx.watch<StoryProvider>();
    // Hanya item berisi slide (slideCount>0) yang tampil & bisa dibuka.
    final items = sp.tray.where((t) => t.slideCount > 0).toList();
    // Anon juga bisa bikin story (dipaksa public) → tile + selalu tampil.
    const showOwnTile = true;
    final showAdd = showOwnTile && !items.any((t) => t.own);
    // Tinggi = isi tile (114 + 2 + label ~12 = 128) + 4 slack — tanpa
    // ini ada 20px kosong antara tulisan Tambah dan filter di bawahnya.
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: 1 + items.length + (showAdd ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          // Slot 0 = avatar sendiri (ikut scroll seperti IG).
          if (i == 0) {
            return _buildOwnAvatarTile(myAvatar, myNickname, myRegistered);
          }
          final j = i - 1;
          // Slot berikutnya = tile "+" kalau belum punya story sendiri.
          if (showAdd && j == 0) {
            return _OwnAddTile(onTap: _openStoryComposer);
          }
          final it = items[showAdd ? j - 1 : j];
          final idx = showAdd ? j - 1 : j;
          // KEY berbasis identitas (authorId + thumbPath): State tile
          // di-reuse saat urutan berubah / tray refresh, bukan dibuang lalu
          // dibuat ulang (dulu: thumbnail "keload ulang" tiap refresh karena
          // State baru mulai dari _thumb=null). Ganti slide → thumbPath
          // berubah → key berubah → State baru ambil thumb baru (benar).
          return _StoryTrayTile(
            key: ValueKey('story_${it.authorId}_${it.thumbPath}'),
            item: it,
            // Badge "+" di tile sendiri untuk tambah slide baru —
            // buka composer (sama seperti tombol + di AppBar).
            isOwnWithAdd: showOwnTile && it.own,
            onTap: () => _openViewer(items, idx),
            onAddTap: (showOwnTile && it.own) ? _openStoryComposer : null,
          );
        },
      ),
    );
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
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final s = context.read<LocaleProvider>().s;
    final myUid = auth.uid;
    final myName = auth.profile?.nickname ?? 'Anon';
    if (myUid == null || user.uid == myUid) return;

    // Hitung chatId lokal (deterministik, tanpa network) → navigate instant.
    final ids = [myUid, user.uid]..sort();
    final chatId = '${ids[0]}_${ids[1]}';
    // Guard double-push: tap 2× cepat saat transisi push menumpuk 2 route
    // identik → 1× back tampak "tidak bereaksi" (scroll jalan). Lihat
    // docs/PERFORMANCE.md §18.
    final navKey = navKeyChat(chatId);
    if (!tryClaimNav(navKey)) return;
    // Prefetch pesan ke memori sebelum push → buka chat instant.
    context.read<ChatProvider>().prefetchPrivateChat(chatId);
    if (!context.mounted) {
      releaseNav(navKey);
      return;
    }
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        settings: RouteSettings(name: privateChatRoute(chatId)),
        pageBuilder: (_, __, ___) => PrivateChatScreen(
          chatId: chatId,
          otherName: user.nickname,
          otherUid: user.uid,
          otherGender: user.gender,
          otherCountry: user.country,
          otherCity: user.city,
          otherAge: user.age,
          otherRegistered: user.isRegistered,
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );

    // Validasi + upsert di background setelah screen sudah terbuka.
    try {
      final active = await chat.isUserActive(user.uid);
      if (!active) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
        }
        return;
      }
      await chat.startPrivateChat(
        myUid: myUid,
        otherUid: user.uid,
        myName: myName,
        otherName: user.nickname,
        myGender: auth.profile?.gender ?? '',
        otherGender: user.gender,
        myCountry: auth.profile?.country ?? '',
        otherCountry: user.country,
        myAge: auth.profile?.age ?? 0,
        otherAge: user.age,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('23503') ||
          msg.contains('foreign key') ||
          msg.contains('42501')) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    }
  }

  // Sembunyikan TANPA snackbar: swipe beruntun + bar transient = bar
  // seolah nempel/muncul terus. Feedback-nya = kotak bawah otomatis
  // terbuka menampilkan orangnya + tombol Tampilkan per kartu (tanpa
  // timeout, jauh lebih jelas daripada snackbar 3 detik).
  Future<void> _hideUser(UserModel user) async {
    if (!mounted) return;
    try {
      await context.read<OnlineUsersProvider>().hideUser(user.uid);
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
      await context.read<OnlineUsersProvider>().unhideUser(user.uid);
    } catch (_) {}
  }

  Future<void> _showUnreadBubble(
    BuildContext cardCtx,
    UserModel user,
    int unreadCount,
    Offset globalPos,
  ) async {
    final myUid = cardCtx.read<AuthProvider>().uid;
    final s = cardCtx.read<LocaleProvider>().s;
    if (myUid == null) return;
    final ids = [myUid, user.uid]..sort();
    final chatId = '${ids[0]}_${ids[1]}';
    List<MessageModel> msgs = [];
    try {
      final rows = await Supabase.instance.client
          .from('private_messages')
          .select(
            'id, sender_id, sender_name, text, type, image_data, created_at',
          )
          .eq('chat_id', chatId)
          .eq('sender_id', user.uid)
          .order('created_at', ascending: false)
          .limit(unreadCount > 8 ? 8 : unreadCount);
      msgs = rows
          .map(
            (r) => MessageModel.fromMap('${r['id']}', {
              'senderId': r['sender_id'],
              'senderName': r['sender_name'],
              'text': r['text'] ?? '',
              'type': r['type'] ?? 'text',
              'imageData': r['image_data'] ?? '',
              'createdAt': r['created_at'],
            }),
          )
          .toList();
    } catch (_) {}
    if (!cardCtx.mounted || msgs.isEmpty) return;
    HapticFeedback.mediumImpact();
    // Hitung posisi card agar bubble nempel tepat di atas/bawah card
    final box = cardCtx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final cardTopLeft = box.localToGlobal(Offset.zero);
    final cardSize = box.size;
    final cardCenterX = cardTopLeft.dx + cardSize.width / 2;
    final overlay = Overlay.of(cardCtx);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final bubbleWidth = 280.0;
        final bubbleHeight = (msgs.length * 48.0 + 40)
            .clamp(72, 280)
            .toDouble();
        double left = cardCenterX - bubbleWidth / 2;
        left = left.clamp(12, size.width - bubbleWidth - 12);
        // Nempel tepat: 0 gap + ekor 8px
        final spaceAbove = cardTopLeft.dy;
        final spaceBelow = size.height - (cardTopLeft.dy + cardSize.height);
        final isAbove =
            spaceAbove > spaceBelow && spaceAbove >= bubbleHeight + 16;
        double top;
        if (isAbove) {
          top = cardTopLeft.dy - bubbleHeight - 8;
        } else {
          top = cardTopLeft.dy + cardSize.height + 8;
        }
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => entry.remove(),
                child: Container(color: Colors.black.withValues(alpha: 0.15)),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isAbove) ...[
                      CustomPaint(
                        size: const Size(14, 8),
                        painter: _BubbleTailPainter(
                          color: AppTheme.bgInput,
                          isTop: true,
                        ),
                      ),
                    ],
                    Container(
                      width: bubbleWidth,
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgInput,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(
                          color: AppTheme.divider.withValues(alpha: 0.8),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(user.nickname, style: AppText.bodyStrong),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  s.newCount(unreadCount),
                                  style: AppText.micro.copyWith(
                                    color: AppTheme.danger,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => entry.remove(),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Divider(
                            height: 1,
                            color: AppTheme.divider.withValues(alpha: 0.5),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final m in msgs) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                    horizontal: 2,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          m.text.isNotEmpty
                                              ? m.text
                                              : (m.type == 'image'
                                                    ? s.msgPhoto
                                                    : m.type),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.bodySmall,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        formatBubbleTime(m.timestamp),
                                        style: AppText.micro.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (m != msgs.last)
                                  Divider(
                                    height: 1,
                                    color: AppTheme.divider.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isAbove) ...[
                      CustomPaint(
                        size: const Size(14, 8),
                        painter: _BubbleTailPainter(
                          color: AppTheme.bgInput,
                          isTop: false,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
    // Auto-tutup 4 dtk. `remove()` dibungkus try/catch + cek `mounted`:
    // overlay yang sudah di-unmount (pindah rute) bisa melempar saat
    // remove() → kalau tak tertangkap, jadi penghalang transparan sisa
    // (tap/back tertelan padahal scroll jalan).
    Future.delayed(const Duration(seconds: 4), () {
      try {
        if (entry.mounted) entry.remove();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Online');
    // select (bukan watch): heartbeat presence AuthProvider berubah tiap
    // beberapa detik — watch membuat SELURUH halaman (Scaffold + tray story
    // + ListView) rebuild tiap kali walau tak ada yang terlihat berubah.
    // Hanya field yang dipakai untuk render yang di-listen.
    final authUid = context.select<AuthProvider, String?>((a) => a.uid);
    final myAvatar = context.select<AuthProvider, String>(
      (a) => a.profile?.avatar ?? '',
    );
    final myNickname = context.select<AuthProvider, String>(
      (a) => a.profile?.nickname ?? '-',
    );
    final myRegistered = context.select<AuthProvider, bool>(
      (a) => a.profile?.isRegistered ?? false,
    );
    super.build(context);
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.bgScreen,
        surfaceTintColor: AppTheme.bgScreen,
        // 56 (isi judul ±38 / field cari 40) — dulu 72, ruang kosong
        // 16px antara judul dan tray story terpangkas.
        toolbarHeight: 56,
        // Tombol search di KIRI ATAS (leading). Ikon Admin Panel pindah
        // ke actions kanan (hanya tampil untuk admin sungguhan).
        leading: IconButton(
          tooltip: s.searchHint,
          icon: Icon(
            _isSearching ? Icons.close : Icons.search_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchCtrl.clear();
                _search = '';
                _page = 1;
              }
            });
          },
        ),
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(
              sizeFactor: anim,
              axis: Axis.horizontal,
              axisAlignment: -1,
              child: child,
            ),
          ),
          child: _isSearching
              ? SizedBox(
                  key: const ValueKey('search'),
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: (v) => setState(() {
                      _search = v;
                      _page = 1;
                    }),
                    style: AppText.body.copyWith(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: s.searchHint,
                      hintStyle: AppText.body.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 0,
                      ),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: 18,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _search = '';
                                  _page = 1;
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.bgCard,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                )
              : Consumer<OnlineUsersProvider>(
                  key: const ValueKey('title'),
                  builder: (_, prov, __) {
                    // Hitung sama seperti list: exclude self + blocked +
                    // hidden + dedupe by uid/nickname, supaya angka = kartu.
                    final chat = context.read<ChatProvider>();
                    final seenU = <String>{};
                    final seenN = <String>{};
                    final n = prov.users
                        .where(
                          (u) =>
                              u.uid != authUid &&
                              u.uid.isNotEmpty &&
                              !chat.isBlocked(u.uid) &&
                              !prov.isHidden(u.uid) &&
                              seenU.add(u.uid) &&
                              seenN.add(u.nickname.toLowerCase()),
                        )
                        .length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.titleOnline,
                          style: AppText.title.copyWith(
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '$n ${s.onlineActiveUsers}',
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        // Avatar + nama user + TRAY STORY (preferredSize) — tidak ikut
        // hilang saat mode search aktif.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(146),
          child: Padding(
            // Atas 2 (rapat ke field cari di toolbar) — total
            // 2 + 132 + 4 = 138 ≤ 146, tidak overflow.
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: _buildStoryTray(context, myAvatar, myNickname, myRegistered),
          ),
        ),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
        // Tombol + story (SEMUA user — anon juga bisa, dipaksa public
        // oleh server) & Orang Sekitar (registered only) — GestureDetector
        // rapat (tanpa padding). IconButton tidak dipakai: minimumSize M3
        // selalu memaksa 48px walau constraints 32 diberikan.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tombol Admin Panel dipindah ke tombol melayang kiri-bawah
                // (lihat _MainNav di app.dart) — tidak lagi di AppBar.
                Tooltip(
                  message: s.storyAddTooltip,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openStoryComposer,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(Icons.add_circle_outline),
                    ),
                  ),
                ),
                // Orang Sekitar tampil untuk SEMUA user (termasuk anon).
                // Anon yang menekan ikon ini dapat popup "lengkapi email" —
                // form yang sama dengan aksi posting di timeline (modular),
                // tapi teksnya khusus konteks Orang Sekitar.
                Tooltip(
                  message: s.nearbyTitle,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!myRegistered) {
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
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(Icons.explore_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Consumer<OnlineUsersProvider>(
            builder: (_, provider, __) {
              final chat = context.read<ChatProvider>();
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
                hiddenUsers = base
                    .where((u) => provider.isHidden(u.uid))
                    .toList();
                users = base.where((u) {
                  if (provider.isHidden(u.uid)) return false;
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

              final unreadMap = _unreadMap;

              final paged = users.take(_page * _pageSize).toList();
              final hasMore = paged.length < users.length;
              // Map uid→index sekali (dulu indexWhere linear per kunci anak
              // → O(n²) saat presence heartbeat menggeser posisi tiap emit).
              final indexByUid = <String, int>{
                for (var i = 0; i < paged.length; i++) paged[i].uid: i,
              };

              return Column(
                children: [
                  Padding(
                    // Atas 8: label floating butuh ~6px di atas field —
                    // kalau 0, label masuk area AppBar dan kepotong.
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MultiSelectDropdown(
                            label: s.labelCountry,
                            icon: Icons.public,
                            items: allCountries,
                            labels: allCountries,
                            selected: _negaraSel,
                            countText: s.selCountriesCount,
                            onChanged: (v) {
                              setState(() {
                                _negaraSel = v;
                                _page = 1;
                              });
                              _saveFilter();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SearchDropdown(
                            value: _gender,
                            label: 'Gender',
                            icon: Icons.person_outline,
                            items: const ['all', 'male', 'female'],
                            labels: [s.filterAll, s.filterMale, s.filterFemale],
                            onChanged: (v) async {
                              // Filter gender berbayar (harian) — gate server
                              // saat fitur sudah dipublish. Pilih 'all' = gratis.
                              if (v != 'all') {
                                final pp = context.read<PointsProvider>();
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
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !provider.hasLoaded
                        ? ListView.builder(
                            padding: EdgeInsets.fromLTRB(
                              10,
                              10,
                              10,
                              MediaQuery.of(context).padding.bottom + 12,
                            ),
                            itemCount: 6,
                            itemBuilder: (_, _) => const SkeletonCard(),
                          )
                        : users.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 88,
                                      height: 88,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withValues(
                                          alpha: 0.08,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Icon(
                                      Icons.group_add_rounded,
                                      size: 48,
                                      color: AppTheme.primary,
                                    ),
                                    Positioned(
                                      right: 4,
                                      bottom: 4,
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: AppTheme.online,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  _search.isNotEmpty
                                      ? s.searchNoResult
                                      : s.noOnlineUsers,
                                  textAlign: TextAlign.center,
                                  style: AppText.body.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: EdgeInsets.fromLTRB(
                              10,
                              10,
                              10,
                              MediaQuery.of(context).padding.bottom + 12,
                            ),
                            // Kartu ikut pindah posisi saat urutan berubah
                            // (sort last_seen) — State _AsyncAvatar tidak
                            // di-dispose/recreate → avatar tidak kedip.
                            findChildIndexCallback: (key) {
                              final k = key as ValueKey<String>;
                              // 'uc-<uid>' → index via Map O(1).
                              final uid = k.value.startsWith('uc-')
                                  ? k.value.substring(3)
                                  : k.value;
                              return indexByUid[uid];
                            },
                            itemCount: paged.length + (hasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= paged.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                      color: AppTheme.primary,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              final user = paged[i];
                              // Geser kiri = Sembunyikan (benam ke kotak bawah).
                              // confirmDismiss=false: kartu tidak terbang,
                              // hanya memicu hide + snackbar Undo.
                              return Dismissible(
                                key: ValueKey('uc-${user.uid}'),
                                direction: DismissDirection.endToStart,
                                secondaryBackground: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.textSecondary,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.visibility_off_outlined,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        s.btnHide,
                                        style: AppText.caption.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                background: const SizedBox.shrink(),
                                // Fire-and-forget: kartu langsung meluncur
                                // balik tanpa menunggu I/O prefs; hide +
                                // snackbar jalan di latar. Kalau di-await,
                                // kartu tertahan terbuka selama future jalan.
                                confirmDismiss: (_) {
                                  unawaited(_hideUser(user));
                                  return Future.value(false);
                                },
                                // RepaintBoundary: kartu lain tidak ikut
                                // repaint saat satu kartu berubah (badge,
                                // status dot, avatar) — list panjang jadi
                                // jauh lebih murah.
                                child: Builder(
                                  builder: (cardCtx) => RepaintBoundary(
                                    child: _UserCard(
                                      user: user,
                                      onTap: () => _startChat(context, user),
                                      onAvatarTap: (c) =>
                                          _zoomUserAvatar(user, c),
                                      onLongPressStart:
                                          unreadMap[user.uid] != null &&
                                              unreadMap[user.uid]! > 0
                                          ? (d) => _showUnreadBubble(
                                              cardCtx,
                                              user,
                                              unreadMap[user.uid]!,
                                              d.globalPosition,
                                            )
                                          : null,
                                      unreadCount: unreadMap[user.uid] ?? 0,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Kotak bawah: yang disembunyikan tetap di bawah walau
                  // online, sampai di-release (swipe kanan / tombol).
                  // Hanya tampil jika ada isi (hemat ruang).
                  if (hiddenUsers.isNotEmpty)
                    HiddenBox(
                      title: s.labelHidden(hiddenUsers.length),
                      expanded: _showHidden,
                      onToggle: () =>
                          setState(() => _showHidden = !_showHidden),
                      children: [
                        for (final user in hiddenUsers)
                          Dismissible(
                            key: ValueKey('hid-${user.uid}'),
                            direction: DismissDirection.startToEnd,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.visibility_outlined,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    s.btnUnhide,
                                    style: AppText.caption.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            secondaryBackground: const SizedBox.shrink(),
                            confirmDismiss: (_) {
                              unawaited(_unhideUser(user));
                              return Future.value(false);
                            },
                            child: Builder(
                              builder: (cardCtx) => RepaintBoundary(
                                child: _UserCard(
                                  user: user,
                                  onTap: () => _startChat(context, user),
                                  onAvatarTap: (c) =>
                                      _zoomUserAvatar(user, c),
                                  onLongPressStart:
                                      unreadMap[user.uid] != null &&
                                          unreadMap[user.uid]! > 0
                                      ? (d) => _showUnreadBubble(
                                          cardCtx,
                                          user,
                                          unreadMap[user.uid]!,
                                          d.globalPosition,
                                        )
                                      : null,
                                  unreadCount: unreadMap[user.uid] ?? 0,
                                  onUnhide: () => _unhideUser(user),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
          // Kapsul samping yang BERGANTIAN TIAP JAM: mode Timeline (klik →
          // pindah ke tab Timeline) ⇄ mode Global Room (klik → buka room
          // kategori General). Meluncur dari tepi kanan; menempel BAWAH (di
          // atas nav bar) supaya tidak menutupi list online.
          // PENTING: dibungkus Positioned.fill AGAR dapat constraints penuh
          // (widget mengembalikan Stack + Positioned sendiri). Bila dipasang
          // langsung sebagai anak Stack non-positioned, constraints longgar →
          // kapsul tidak ter-layout / tak tampil.
          Positioned.fill(
            child: _OnlinePill(
              onOpenRoom: () => _openGeneralRoom(context),
              onOpenTimeline: () => context.read<NavProvider>().goTo(2),
              ownerUid: authUid,
            ),
          ),
        ],
      ),
    );
  }

  /// Buka Global Room kategori General dari halaman Online.
  /// Selalu mengarah ke TAB GLOBAL ROOM (bukan timeline): kalau ada room
  /// general langsung dibuka; kalau belum, buka halaman Global Room dengan
  /// kategori General terpilih.
  Future<void> _openGeneralRoom(BuildContext context) async {
    final rp = context.read<RoomProvider>();
    final rooms = rp.exploreRooms.where((r) => r.category == 'general');
    if (rooms.isNotEmpty) {
      final room = rooms.first;
      unawaited(rp.markRoomRead(room.id));
      if (!context.mounted) return;
      final navKey = navKeyRoom(room.id);
      if (!tryClaimNav(navKey)) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
      ).then((_) => releaseNav(navKey));
      return;
    }
    // Belum ada room general termuat/tersedia → buka HALAMAN Global Room
    // dengan kategori General terpilih (bukan pindah tab timeline).
    rp.setExploreCategory('general');
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LobbyScreen(initialCategory: 'general'),
      ),
    );
  }
}

/// Kapsul KOMPAK di halaman Online — BERGANTIAN TIAP JAM antara dua mode:
///  - mode **Timeline** (jam genap): label "Timeline", klik → pindah tab.
///  - mode **Global Room** (jam ganjil): label "Global Room" + jumlah online,
///    klik → buka room kategori General (perilaku lama).
/// Kapsul bisa DI-DRAG vertikal (tetap nempel tepi kanan); posisi terakhir
/// disimpan per akun sehingga logout/login tetap di sana.
///
/// Perilaku animasi:
///  - Saat halaman Online dibuka → kapsul SLIDE MASUK dari kanan (dari tidak
///    ada → ada), lalu DIAM menempel di tepi (sisi rata di tepi, membulat ke
///    dalam). Tidak ada gerakan mengganggu setelahnya.
///  - Saat DIKETUK → kapsul SLIDE KELUAR ke kanan dengan halus, baru aksi
///    dipanggil (pindah tab / buka room).
///  - Satu-satunya gerakan saat diam: chevron ">" yang bergerak halus
///    (geser kanan-kiri) sebagai isyarat bisa diketuk.
/// Membaca sendiri jumlah online kategori General dari [RoomProvider].
class _OnlinePill extends StatefulWidget {
  /// Aksi saat kapsul mode Global Room diketuk. `Future` supaya kapsul bisa
  /// menunggu sampai halaman yang dibuka DITUTUP, lalu reset animasi.
  final Future<void> Function() onOpenRoom;

  /// Aksi saat kapsul mode Timeline diketuk — pindah ke tab Timeline.
  final VoidCallback onOpenTimeline;

  /// Uid pemilik posisi drag (persist per akun — logout/login tetap di
  /// posisi terakhir user itu).
  final String? ownerUid;

  const _OnlinePill({
    required this.onOpenRoom,
    required this.onOpenTimeline,
    this.ownerUid,
  });

  @override
  State<_OnlinePill> createState() => _OnlinePillState();
}

class _OnlinePillState extends State<_OnlinePill>
    with TickerProviderStateMixin {
  /// Posisi horizontal kapsul: 0 = menempel tepi, 1 = seluruhnya di luar.
  late final AnimationController _slide;

  /// Denyut chevron (isyarat "bisa diketuk") — hanya panah yang bergerak.
  late final AnimationController _chev;

  bool _leaving = false;

  /// Mode kapsul saat ini (Timeline ⇄ Global Room), berganti tiap jam.
  OnlinePillMode _mode = OnlinePillMode.timeline;

  /// Timer pergantian jam — dibangun ulang tiap kali jam berganti.
  Timer? _hourTimer;

  // Kapsul kecil: tinggi 40, teks ringkas.
  static const double _h = 40;

  /// Offset vertikal dari posisi default (60+inset): + = ke atas.
  /// Disimpan per akun; dimuat ulang saat ganti akun.
  double _dragDy = 0;
  String? _pillOwner;

  static String _pillKeyFor(String owner) => 'online_pill_dy_$owner';

  Future<void> _loadPillPos() async {
    final owner = widget.ownerUid;
    _pillOwner = owner;
    if (mounted) setState(() => _dragDy = 0);
    if (owner == null || owner.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dy = prefs.getDouble(_pillKeyFor(owner));
      if (!mounted || dy == null) return;
      if (widget.ownerUid != _pillOwner) return;
      setState(() => _dragDy = dy);
    } catch (_) {}
  }

  Future<void> _savePillPos() async {
    final owner = widget.ownerUid;
    if (owner == null || owner.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_pillKeyFor(owner), _dragDy);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _mode = onlinePillModeFor(DateTime.now());
    _scheduleHourFlip();
    _loadPillPos();
    // PENTING: mulai dari 1.0 (MENEMPEL) agar kapsul PASTI tampil, apa pun
    // kondisi TickerMode (halaman Online dibuild di dalam IndexedStack +
    // TickerMode; bila ticker ter-pause, animasi tak jalan → kapsul
    // nyangkut offscreen kalau mulai dari 0).
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: 1.0,
    );
    // Chevron geser halus bolak-balik saat kapsul diam.
    _chev = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  /// Jadwalkan pembaruan mode TEPAT saat jam berganti (bukan polling tiap
  /// detik) supaya kapsul bergantian tiap 1 jam tanpa boros.
  void _scheduleHourFlip() {
    _hourTimer?.cancel();
    _hourTimer = Timer(untilNextHour(DateTime.now()), () {
      if (!mounted) return;
      setState(() => _mode = onlinePillModeFor(DateTime.now()));
      _scheduleHourFlip();
    });
  }

  bool _tickerWasOn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode: di app, tab dibungkus `TickerMode(enabled: tab == i)`.
    // Saat tab Online TIDAK aktif, ticker di-pause → animasi tidak jalan.
    // Kita pantau perubahan TickerMode lewat notifier agar tahu saat tab
    // Online DIBUKA kembali (tanpa perlu rebuild/restart app).
    final notifier = TickerMode.getNotifier(context);
    if (!identical(_tickerNotifier, notifier)) {
      _tickerNotifier?.removeListener(_onTickerChanged);
      _tickerNotifier = notifier;
      _tickerNotifier?.addListener(_onTickerChanged);
    }
    _onTickerChanged();
  }

  @override
  void didUpdateWidget(covariant _OnlinePill old) {
    super.didUpdateWidget(old);
    // Ganti akun (dummy ⇄ admin) → muat posisi milik akun baru.
    if (old.ownerUid != widget.ownerUid) _loadPillPos();
  }

  ValueListenable<bool>? _tickerNotifier;

  void _onTickerChanged() {
    final on = _tickerNotifier?.value ?? true;
    if (!mounted) return;
    if (on && !_tickerWasOn) {
      // Tab Online baru DIBUKA (ticker ON) → animasi masuk SEKALI.
      // Langsung set 0 (di luar kanan) TANPA menunggu frame — kalau tidak,
      // ada 1 frame tampil menempel dulu → terlihat BLINK sebelum meluncur.
      // `forward()` langsung dipanggil karena ticker sudah aktif di cabang
      // ini (animasi pasti jalan, tidak nyangkut).
      _slide.value = 0;
      _slide.forward();
    }
    // Catatan: saat tab DITINGGALKAN (ticker OFF) `_slide` sengaja TIDAK
    // disentuh. Ia sudah bernilai 1 (menempel) setelah animasi masuk selesai,
    // jadi aman saat di-pause; saat tab dibuka lagi kita reset ke 0 di atas.
    _tickerWasOn = on;
  }

  @override
  void dispose() {
    _tickerNotifier?.removeListener(_onTickerChanged);
    _hourTimer?.cancel();
    _slide.dispose();
    _chev.dispose();
    super.dispose();
  }

  /// Tap: slide keluar ke kanan dengan halus, jalankan aksi sesuai MODE saat
  /// ini (Timeline → pindah tab; Global Room → buka room), lalu saat kembali
  /// reset ke posisi menempel agar BISA diklik ulang. Tanpa reset ini,
  /// `_leaving` tetap true & `_slide` tetap 0 (di luar kanan) → klik
  /// berikutnya tidak berefek.
  Future<void> _handleTap() async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _slide.reverse(); // 1 → 0 = keluar ke kanan.
    } catch (_) {}
    if (!mounted) return;
    if (_mode == OnlinePillMode.timeline) {
      widget.onOpenTimeline();
    } else {
      await widget.onOpenRoom();
    }
    if (!mounted) return;
    // Kembali → mainkan animasi masuk lagi (0 → 1) + siap diklik ulang.
    _leaving = false;
    _slide.value = 0;
    _slide.forward();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isTimeline = _mode == OnlinePillMode.timeline;
    // Mode Global Room menampilkan jumlah online kategori General (ringkas).
    final rp = context.watch<RoomProvider>();
    final online = rp.exploreRooms
        .where((r) => r.category == 'general')
        .fold<int>(0, (a, r) => a + r.onlineCount);
    final label = isTimeline ? s.titleTimeline : s.titleRooms;
    final glyph = isTimeline ? '📰' : '💬';
    final showCount = !isTimeline && online > 0;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final radius = _h / 2;
    // Lebar kapsul ± 150px → travel lebih besar supaya benar-benar di luar.
    const travel = 170.0;

    // LayoutBuilder: batas drag = tinggi body (8px margin atas-bawah).
    // Kapsul hanya geser VERTIKAL — `right` tetap menempel tepi kanan.
    return LayoutBuilder(
      builder: (_, constraints) {
        final maxBottom = (constraints.maxHeight - _h - 8.0)
            .clamp(8.0, double.infinity)
            .toDouble();
        final bottom = (60 + bottomInset + _dragDy)
            .clamp(8.0, maxBottom)
            .toDouble();
        return AnimatedBuilder(
          animation: Listenable.merge([_slide, _chev]),
          builder: (_, __) {
            // `_slide.value`: 0 = seluruhnya di LUAR kanan, 1 = MENEMPEL tepi.
            // `out`: 1 = di luar, 0 = menempel (dipakai untuk `right`).
            final out = reduceMotion
                ? 0.0
                : (1 -
                      Curves.easeOutCubic.transform(
                        _slide.value.clamp(0.0, 1.0),
                      ));
            // Opacity: 0 saat di luar, 1 saat menempel (berbanding terbalik out).
            final opacity = (1 - out).clamp(0.0, 1.0);

            // Chevron: geser 0→3px halus (hanya ini yang bergerak saat diam).
            final chevDx = reduceMotion ? 0.0 : (_chev.value * 3.0);

            return Stack(
              children: [
                Positioned(
                  // out=0 → right 0 (menempel). out=1 → right -travel (di luar).
                  right: -travel * out,
                  bottom: bottom,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleTap,
                    // Drag vertikal: geser jari 1:1 dengan kapsul; horizontal
                    // diabaikan (tetap nempel kanan). Tap tetap jalan karena
                    // cuma drag vertikal yang masuk arena gesture.
                    onVerticalDragStart: (_) =>
                        HapticFeedback.lightImpact(),
                    onVerticalDragUpdate: (d) {
                      setState(() => _dragDy += -d.delta.dy);
                    },
                    onVerticalDragEnd: (_) =>
                        unawaited(_savePillPos()),
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      height: _h,
                      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryDark,
                            AppTheme.primary,
                            AppTheme.accent,
                          ],
                        ),
                        // Kiri membulat penuh; kanan rata (menempel tepi).
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(radius),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(-2, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              glyph,
                              style: TextStyle(fontSize: AppGlyph.xs),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            label,
                            style: AppText.label.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (showCount) ...[
                            const SizedBox(width: 6),
                            Text(
                              '$online',
                              style: AppText.micro.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(width: 2),
                          // Chevron bergerak halus (satu-satunya gerak saat
                          // kapsul diam).
                          Transform.translate(
                            offset: Offset(chevDx, 0),
                            child: const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isTop;
  _BubbleTailPainter({required this.color, required this.isTop});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (isTop) {
      path.moveTo(size.width / 2 - 7, size.height);
      path.lineTo(size.width / 2 + 7, size.height);
      path.lineTo(size.width / 2, 0);
    } else {
      path.moveTo(size.width / 2 - 7, 0);
      path.lineTo(size.width / 2 + 7, 0);
      path.lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.1), 2, false);
    canvas.drawPath(path, paint);
    final border = Paint()
      ..color = AppTheme.divider.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Multi-select negara — panel TERANCUNG menempel di bawah field (bukan
/// bottom sheet): search live + checklist + footer Reset/Terapkan.
/// Kosong = Semua. Commit hanya saat Terapkan (tap luar = batal).
/// Single-select dropdown — panel TERANCUNG sama seperti multi-select
/// tapi tanpa search/footer: tap opsi → langsung terapkan + tutup.

class _MultiSelectDropdown extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<String> items;
  final List<String> labels;
  final List<String> selected;
  final String Function(int n) countText;
  final ValueChanged<List<String>> onChanged;

  const _MultiSelectDropdown({
    required this.label,
    required this.icon,
    required this.items,
    required this.labels,
    required this.selected,
    required this.countText,
    required this.onChanged,
  });

  @override
  State<_MultiSelectDropdown> createState() => _MultiSelectDropdownState();
}

class _MultiSelectDropdownState extends State<_MultiSelectDropdown>
    with WidgetsBindingObserver {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Set<String> _temp = {};
  Size _fieldSize = Size.zero;
  double _fieldLeft = 0;

  /// Tinggi keyboard MENTAH — `MediaQuery.of(context).viewInsets.bottom`
  /// selalu 0 di body Scaffold (di-mask `resizeToAvoidBottomInset`).
  double get _keyboardH => MediaQueryData.fromView(
    WidgetsBinding.instance.platformDispatcher.views.first,
  ).viewInsets.bottom;

  @override
  void initState() {
    super.initState();
    // Keyboard buka/tutup TIDAK memicu rebuild OverlayPortal
    // (_OverlayPortalState.didChangeDependencies hanya set flag, tanpa
    // setState) → panel tertinggal di posisi lama & tertutup keyboard.
    // Observer ini yang memaksa panel reposisi. (User: "pas keyboard keatas
    // dropdownnya ga ilang")
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (_portal.isShowing && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fieldText() {
    final s = context.read<LocaleProvider>().s;
    final n = widget.selected.length;
    if (n == 0) return s.filterAll;
    if (n == 1) {
      final idx = widget.items
          .indexOf(widget.selected.first)
          .clamp(0, widget.labels.length - 1);
      return widget.labels[idx];
    }
    return widget.countText(n);
  }

  void _togglePanel() {
    if (_portal.isShowing) {
      _portal.hide();
      return;
    }
    final rb = context.findRenderObject() as RenderBox;
    _fieldSize = rb.size;
    _fieldLeft = rb.localToGlobal(Offset.zero).dx;
    _temp = widget.selected.toSet();
    _searchCtrl.clear();
    _query = '';
    _portal.show();
  }

  void _apply() {
    widget.onChanged(widget.items.where(_temp.contains).toList());
    _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayCtx) {
        final mq = MediaQuery.of(overlayCtx);
        // Lebar: field + 96px ke kanan, clamp ke tepi layar (field kanan).
        final screenW = mq.size.width;

        // Panel hidup di Overlay → TIDAK ikut resize saat keyboard naik.
        // Hitung sendiri ruang terlihat + posisi field TERBARU, lalu buka ke
        // ATAS bila ruang bawah tidak layak (bug "pilihan negara ilang saat
        // keyboard naik" di tab Online).
        final visibleBottom = mq.size.height - mq.padding.bottom - _keyboardH;
        final rb = context.findRenderObject() as RenderBox?;
        double fieldTop = 0, fieldBottom = 0, fieldLeft = _fieldLeft;
        if (rb != null && rb.hasSize) {
          final origin = rb.localToGlobal(Offset.zero);
          fieldTop = origin.dy;
          fieldBottom = fieldTop + rb.size.height;
          fieldLeft = origin.dx;
        }
        final availW = screenW - fieldLeft - 8;
        final panelW = (_fieldSize.width + 96).clamp(0.0, availW).toDouble();

        const gap = 4.0;
        const maxPanel = 340.0;
        final spaceBelow = visibleBottom - fieldBottom - gap;
        // Selalu buka ke BAWAH — field negara ada di atas layar, panel
        // harus menempel di bawah field dan menyesuaikan tinggi terhadap
        // ruang tersisa (keyboard buka → panel mengecil, bukan pindah).
        final panelMaxH = spaceBelow.clamp(120.0, maxPanel);

        final filtered = [
          for (int i = 0; i < widget.items.length; i++)
            if (_query.isEmpty ||
                widget.labels[i].toLowerCase().contains(_query))
              i,
        ];
        return Stack(
          children: [
            // Penutup: tap di luar = batal (tanpa commit).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _portal.hide(),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, gap),
              showWhenUnlinked: false,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: panelW,
                  constraints: BoxConstraints(maxHeight: panelMaxH),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                        // Tinggi 40 — sama seperti form cari nama di AppBar.
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _searchCtrl,
                            autofocus: false,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 18),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 0,
                              ),
                              hintText: s.searchCountry,
                              hintStyle: AppText.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppTheme.divider),
                              ),
                            ),
                            onChanged: (q) =>
                                setState(() => _query = q.trim().toLowerCase()),
                          ),
                        ),
                      ),
                      Flexible(
                        child: filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  '-',
                                  style: AppText.bodySmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final idx = filtered[i];
                                  final checked = _temp.contains(
                                    widget.items[idx],
                                  );
                                  return CheckboxListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    value: checked,
                                    title: Text(
                                      widget.labels[idx],
                                      style: AppText.bodySmall.copyWith(
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.trailing,
                                    activeColor: AppTheme.primary,
                                    checkboxShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _temp.add(widget.items[idx]);
                                        } else {
                                          _temp.remove(widget.items[idx]);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                      Divider(height: 1, color: AppTheme.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() => _temp = {}),
                              icon: const Icon(
                                Icons.filter_alt_off_outlined,
                                size: 16,
                              ),
                              label: Text(s.filterReset),
                              // Tinggi 40 — sama dengan field cari & Terapkan.
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.textSecondary,
                                textStyle: AppText.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Tinggi dikunci 40 — sama persis dengan field cari negara.
                            SizedBox(
                              height: 40,
                              child: FilledButton.icon(
                                onPressed: _apply,
                                icon: const Icon(Icons.check, size: 16),
                                label: Text(
                                  '${s.filterApply} (${_temp.length})',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  textStyle: AppText.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: GestureDetector(
          onTap: _togglePanel,
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(
                widget.icon,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 0,
              ),
              labelText: widget.label,
              contentPadding:
                  // Sama dengan SearchDropdown (gender) → tinggi identik.
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 0,
              ),
              suffixIcon: widget.selected.isEmpty
                  ? Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: AppTheme.textSecondary,
                    )
                  : GestureDetector(
                      onTap: () => widget.onChanged(const []),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                    ),
            ),
            child: Text(
              _fieldText(),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  final void Function(Color avatarColor) onAvatarTap;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final int unreadCount;
  final VoidCallback? onUnhide;
  const _UserCard({
    required this.user,
    required this.onTap,
    required this.onAvatarTap,
    this.onLongPressStart,
    this.unreadCount = 0,
    this.onUnhide,
  });

  Color _statusColor(String status) => AppTheme.statusColor(status);

  String _idleDurationLabel(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen.toLocal());
    if (diff.inMinutes < 1) return '1m';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('d MMM').format(lastSeen.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final color = user.gender == 'male'
        ? AppTheme.male
        : user.gender == 'female'
        ? AppTheme.female
        : AppTheme.accent;
    final genderLabel = user.gender == 'male'
        ? s.genderMale
        : user.gender == 'female'
        ? s.genderFemale
        : s.genderOther;
    // Hanya 'online' yang berlabel Online — 'invisible'/lainnya = offline.
    // Dulu else-default ke Online sehingga baris invisible yang lolos
    // filter (mis. cache basi) tampil "Online" walau dot-nya abu-abu.
    final statusLabel = user.status == 'online'
        ? s.statusOnline
        : user.status == 'idle'
        ? '${s.statusIdle} · ${_idleDurationLabel(user.lastSeen)}'
        : s.statusOffline;

    return AppGestureDetector(
      // SELURUH kartu bisa di-tap → buka chat (tadi area kosong tanpa
      // handler → "kadang bisa kadang nggak" tergantung posisi jempol).
      // Zona dalam (avatar/nama/subtitle/follow/chat) tetap menang di
      // area masing-masing (detector terdalam menang arena).
      // AppGestureDetector: tahan 320ms (bukan 500ms).
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: onLongPressStart,
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        // Tanpa onTap di level kartu: 3 zona punya handler sendiri
        // (avatar→zoom, username→profil, ikon chat→chat).
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () => onAvatarTap(color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.15),
                      ),
                      clipBehavior: Clip.antiAlias,
                      // SELALU _AsyncAvatar (jangan ternary inisial↔foto):
                      // pergantian tipe widget menyebabkan State avatar
                      // di-dispose/dibuat-ulang tiap emission → kedip.
                      // Inisial dirender di dalam _AsyncAvatar.
                      // Ring warna digambar _AsyncAvatar hanya saat
                      // placeholder inisial — foto tampil tanpa ring.
                      child: _AsyncAvatar(
                        key: ValueKey(user.uid),
                        uid: user.uid,
                        avatarB64: user.avatar,
                        initial: user.initial,
                        color: color,
                        borderColor: color,
                        borderWidth: 1.5,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: _statusColor(user.status),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppTheme.danger,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: AppText.micro.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: onTap,
                            child: Text(
                              user.nickname,
                              style: AppText.bodyStrong,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (user.gender == 'male' ||
                            user.gender == 'female') ...[
                          SizedBox(width: 4),
                          Icon(
                            user.gender == 'male' ? Icons.male : Icons.female,
                            size: 15,
                            color: user.gender == 'male'
                                ? AppTheme.male
                                : AppTheme.female,
                          ),
                        ],
                        if (user.isRegistered) ...[
                          SizedBox(width: 4),
                          Tooltip(
                            message: s.labelVerified,
                            child: Icon(
                              Icons.verified,
                              size: 15,
                              color: Color(0xFF4A90E2),
                            ),
                          ),
                        ],
                      ],
                    ),
                    GestureDetector(
                      onTap: onTap,
                      child: Text(
                        '$genderLabel ${user.age} · ${user.city}, ${user.country}',
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Isi Tentang (dari RPC online, hormati about_visibility
                    // di server). Kosong = tidak tampil agar kartu ringkas.
                    if (user.about.trim().isNotEmpty)
                      GestureDetector(
                        onTap: onTap,
                        child: Text(
                          user.about.trim(),
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  Text(
                    statusLabel,
                    style: AppText.caption.copyWith(
                      color: _statusColor(user.status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (onUnhide != null)
                        Tooltip(
                          message: s.btnUnhide,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: onUnhide,
                              child: const SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Tombol TAMBAH TEMAN hanya untuk user ter-registrasi.
                      // Lingkaran belakang ikon transparan — ikon saja.
                      if (user.isRegistered)
                        Consumer<SocialProvider>(
                          builder: (_, sp, __) {
                            final isFriend = sp.isFriend(user.uid);
                            final pending = sp.isPendingFriendRequest(user.uid);
                            final done = isFriend || pending;
                            final tip = isFriend
                                ? s.btnFriends
                                : (pending
                                      ? s.btnFriendRequested
                                      : s.btnAddFriend);
                            return Tooltip(
                              message: tip,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  // Sudah teman / permintaan terkirim → tidak
                                  // bisa dikirim ulang (ikon jadi status).
                                  onTap: done
                                      ? null
                                      : () async {
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          final res = await sp
                                              .sendFriendRequest(user.uid);
                                          // 'rejected' = gagal; selain itu
                                          // (ok/pending) anggap terkirim.
                                          if (res != 'rejected') {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  s.friendRequestSent,
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Icon(
                                      isFriend
                                          ? Icons.how_to_reg_rounded
                                          : (pending
                                                ? Icons.schedule_rounded
                                                : Icons.person_add_alt_rounded),
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(width: 2),
                      Tooltip(
                        message: s.btnChatNow,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: onTap,
                            child: const SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Story tray widgets ──────────────────────────────────────────────────────

/// Kotak story satu orang: portrait rounded 67×114, thumbnail slide terbaru,
/// ring gradient (belum dilihat) / abu (sudah), username di bawah.
///
/// Rasio 67×114 dipilih agar kotak FOTO DI DALAM ring (≈62×109 setelah
/// padding 2.5 / border 2) mendekati rasio kartu preview di StoryViewer
/// (`_storyRect`: lebar layar ÷ (tinggi - padTop-60 - 68) ≈ 0.57 di HP
/// portrait umum). Dengan rasio sama, crop `BoxFit.cover` thumbnail = crop
/// preview → tampak "skala sama", bukan lebih zoom.
class _StoryTrayTile extends StatefulWidget {
  final StoryTrayItem item;
  final VoidCallback onTap;
  final bool isOwnWithAdd;
  final VoidCallback? onAddTap;

  const _StoryTrayTile({
    super.key,
    required this.item,
    required this.onTap,
    this.isOwnWithAdd = false,
    this.onAddTap,
  });

  @override
  State<_StoryTrayTile> createState() => _StoryTrayTileState();
}

class _StoryTrayTileState extends State<_StoryTrayTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    // SINKRON dulu: kalau thumbnail sudah ada di RAM/disk (sesi sebelumnya,
    // atau tile lain author sama), frame pertama LANGSUNG terisi — tidak
    // "keload ulang" seperti cold start sebelumnya. `warmThumb` mengisi RAM
    // provider dari disk (pola sama dengan AvatarB64Service) sehingga state
    // widget tidak lagi satu-satunya tempat menyimpan hasil.
    final sp = context.read<StoryProvider>();
    sp.warmThumb(widget.item.thumbPath);
    _thumb = sp.thumbCached(widget.item.thumbPath);
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final p = widget.item.thumbPath;
    if (p.isEmpty) return;
    if (context.read<StorageProvider>().isAvatarPath(p)) return;
    // Sudah punya thumbnail (sync hit / didUpdateWidget) → tidak perlu ulang.
    if (_thumb != null) return;
    // Tunggu prewarm disk dulu — kalau ternyata ADA di disk, ambil sinkron
    // tanpa network (ini yang membuat tampil persisten seperti avatar).
    try {
      await MediaDiskCache.instance.waitReady();
    } catch (_) {}
    if (!mounted) return;
    final sp = context.read<StoryProvider>();
    if (sp.warmThumb(p)) {
      final cached = sp.thumbCached(p);
      if (mounted && cached != null) {
        setState(() => _thumb = cached);
      }
      return;
    }
    try {
      final b = await sp.thumbFor(p);
      if (mounted && b != null && b.isNotEmpty) {
        setState(() => _thumb = b);
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _StoryTrayTile old) {
    super.didUpdateWidget(old);
    // Path berganti (slide baru) → ambil yang baru; kalau sama, biarkan.
    if (old.item.thumbPath != widget.item.thumbPath) {
      final sp = context.read<StoryProvider>();
      sp.warmThumb(widget.item.thumbPath);
      _thumb = sp.thumbCached(widget.item.thumbPath);
      _loadThumb();
    }
  }

  void _showMuteSheet() {
    final it = widget.item;
    final s = context.read<LocaleProvider>().s;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                it.muted
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppTheme.primary,
              ),
              title: Text(it.muted ? s.storyUnmute : s.storyMute),
              onTap: () async {
                Navigator.pop(ctx);
                final sp = context.read<StoryProvider>();
                final ok = await sp.toggleStoryMute(it.authorId, !it.muted);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? s.storyMuted : s.storyUnmuted),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    // Dibisukan → abu transparan TANPA ring (ala IG), walau belum dilihat.
    // Belum dilihat → ring gradient ungu-biru. Sudah dilihat → border
    // PUTIH 2px + shadow, sama seperti avatar di header.
    final seen = !it.hasUnseen || it.muted;
    // RepaintBoundary: tile lain tidak ikut repaint saat satu thumbnail
    // selesai dimuat (tray panjang = scroll lebih mulus).
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        // Tahan = benamkan/tampilkan lagi (kecuali tile sendiri).
        onLongPress: it.own ? null : _showMuteSheet,
        child: Opacity(
          opacity: it.muted ? 0.45 : 1,
          child: SizedBox(
          width: 67,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 67,
                    height: 114,
                    padding: seen ? EdgeInsets.zero : const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      gradient: seen
                          ? null
                          : const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF9C27B0), AppTheme.primary],
                            ),
                      border: seen
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: seen
                          ? [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _thumb != null
                          ? Image.memory(
                              _thumb!,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              // Decode kecil (kotak foto 62x109, x2 density) —
                              // rasio 124:218 = 0.569 sama dengan tile agar
                              // tidak ada crop tambahan saat raster.
                              cacheWidth: 124,
                              cacheHeight: 218,
                            )
                          // Video tanpa poster → ikon video (bukan inisial
                          // nama yang membingungkan).
                          : it.hasVideo
                          ? const Center(
                              child: Icon(
                                Icons.videocam_rounded,
                                color: Colors.white54,
                                size: 26,
                              ),
                            )
                          : Center(
                              child: Text(
                                it.authorName.isNotEmpty
                                    ? it.authorName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: AppGlyph.avatarInitial(64),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Badge video: tile berisi slide mp4.
                  if (it.hasVideo && !widget.isOwnWithAdd)
                    const Positioned(
                      left: 4,
                      bottom: 4,
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  if (widget.isOwnWithAdd)
                    Positioned(
                      // DI DALAM bounds tile (right:2, bottom:2) — dulu -3
                      // (di luar tile) sehingga tidak pernah bisa di-tap.
                      right: 2,
                      bottom: 2,
                      // Badge "+" punya handler sendiri (buka composer) —
                      // lebih dalam dari GestureDetector tile → menang arena.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onAddTap ?? widget.onTap,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 67,
                child: Text(
                  it.own
                      ? context.read<LocaleProvider>().s.storyMine
                      : it.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppText.micro.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Tile "+" milik sendiri saat belum punya story aktif.
class _OwnAddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _OwnAddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 67,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 67,
              height: 114,
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Icon(
                Icons.add,
                size: AppGlyph.md,
                color: AppTheme.primary,
              ),
            ),
            // Label "Tambah" tepat 2px di bawah card — sama seperti label
            // nama di tile story, TANPA gradient shadow.
            const SizedBox(height: 2),
            Text(
              context.read<LocaleProvider>().s.storyAddToStory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.micro.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
