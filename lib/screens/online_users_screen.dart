import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/online_users_provider.dart';
import '../widgets/skeleton_card.dart';
import '../services/media_disk_cache.dart';
import '../providers/social_provider.dart';
import '../providers/timeline_provider.dart';
import '../services/chat_service.dart';
import '../services/location_service.dart';
import '../utils/bounded_cache.dart';
import '../models/message_model.dart';
import 'private_chat_screen.dart';
import 'nearby_screen.dart';
import '../providers/call_provider.dart';
import '../providers/theme_provider.dart';
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

String? _processAvatarImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: 300, height: 300);
  final jpg = img.encodeJpg(resized, quality: 70);
  return base64Encode(jpg);
}

class _AsyncAvatar extends StatefulWidget {
  final String uid;
  final String avatarB64;
  final String initial;
  final Color color;
  const _AsyncAvatar({
    super.key,
    required this.uid,
    required this.avatarB64,
    required this.initial,
    required this.color,
  });

  @override
  State<_AsyncAvatar> createState() => _AsyncAvatarState();
}

class _AsyncAvatarState extends State<_AsyncAvatar> {
  MemoryImage? _provider;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    final src = widget.avatarB64;
    final srcType = src.isEmpty ? 'EMPTY' : src.startsWith('avatars/') ? 'PATH' : 'B64';
    // Sumber sama & provider sudah ada → nol pekerjaan (paling sering).
    if (src == _avatarLastSrcByUid[widget.uid] && _provider != null) {
      debugPrint('[AVATAR] ${widget.uid.substring(0,8)} KEEP ($srcType) t=${DateTime.now().millisecondsSinceEpoch % 100000}');
      return;
    }
    _avatarLastSrcByUid[widget.uid] = src;
    if (src.isEmpty) {
      // Kosong → pertahankan provider lama (jangan kedip ke inisial).
      return;
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
        debugPrint('[AVATAR] ${widget.uid.substring(0,8)} FROM-DISK');
      }
      // Tidak ada di disk → biarkan inisial; batch network akan mengisi.
      return;
    }
    // Instance MemoryImage stabil per-uid → pakai apa adanya.
    final stable = _avatarImageByUid[widget.uid];
    if (stable != null && _provider != stable) {
      debugPrint('[AVATAR] ${widget.uid.substring(0,8)} SWAP-STABLE t=${DateTime.now().millisecondsSinceEpoch % 100000}');
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
        _provider = null;
        return;
      }
      _avatarBytesByUid[widget.uid] = b;
    }
    _provider = _avatarImageByUid.putIfAbsent(
      widget.uid,
      () => MemoryImage(_avatarBytesByUid[widget.uid]!),
    );
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
      return Center(
        child: Text(widget.initial,
            style: TextStyle(color: widget.color, fontSize: AppGlyph.avatarInitial(40), fontWeight: FontWeight.w700)),
      );
    }
    // gaplessPlayback: foto benar-benar baru (bytes beda) → bitmap lama
    // tetap tampil sampai bitmap baru siap, tanpa blank putih.
    return Image(
      image: p,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Center(
        child: Text(widget.initial,
            style: TextStyle(color: widget.color, fontSize: AppGlyph.avatarInitial(40), fontWeight: FontWeight.w700)),
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
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  String _negara = 'all';
  String _gender = 'all';
  String _search = '';
  bool _isSearching = false;
  int _page = 1;
  static const int _pageSize = 20;
  static const _prefKeyNegara = 'filter_negara';
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  StreamSubscription<List<PrivateChatInfo>>? _unreadSub;
  Map<String, int> _unreadMap = {};

  late final AnimationController _sharePulse;
  late final Animation<double> _shareScale;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadFilter();
    _sharePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _shareScale = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _sharePulse, curve: Curves.easeInOut));
    _requestGpsOnce();
  }

  /// Minta izin GPS saat masuk menu pengguna online (dialog native muncul
  /// sekali; kalau ditolak, user tetap bisa aktifkan lewat "bagikan lokasi").
  Future<void> _requestGpsOnce() async {
    final loc = LocationService();
    final ok = await loc.requestPermission();
    if (!ok) return;
    await loc.updateMyLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unreadSub?.cancel();
    final auth = context.read<AuthProvider>();
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
          });
    }
  }

  Future<void> _loadFilter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _negara = prefs.getString(_prefKeyNegara) ?? 'all';
      _gender = 'all';
    });
  }

  Future<void> _saveFilter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyNegara, _negara);
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

    setState(() => _uploadingAvatar = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80,
      );
      if (picked == null || !mounted) {
        setState(() => _uploadingAvatar = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) {
        setState(() => _uploadingAvatar = false);
        return;
      }

      final processed = await compute(_processAvatarImage, bytes);
      if (processed == null || !mounted) {
        setState(() => _uploadingAvatar = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.errPhotoProcess)),
          );
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
            context.read<OnlineUsersProvider>().updateAvatarForUid(uid, processed);
            context.read<TimelineProvider>().refreshAvatarForUid(uid, processed);
          }
        } catch (_) {}
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.msgProfileSaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.errPhotoUpload}$e')),
        );
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
                child: bytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(bytes, fit: BoxFit.contain),
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
    );
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _sharePulse.dispose();
    _unreadSub?.cancel();
    super.dispose();
  }

  Future<void> _shareApp() async {
    final auth = context.read<AuthProvider>();
    final s = context.read<LocaleProvider>().s;
    final uid = auth.uid;
    if (uid == null) return;
    final link = SupabaseConfig.shareLink;
    await Share.share(s.shareInviteMsg(link));
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
    if (!context.mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
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
        ).showSnackBar(SnackBar(content: Text('${s.errGeneric}$e')));
      }
    }
  }

  Future<void> _showUnreadBubble(BuildContext cardCtx, UserModel user, int unreadCount, Offset globalPos) async {
    final myUid = cardCtx.read<AuthProvider>().uid;
    if (myUid == null) return;
    final ids = [myUid, user.uid]..sort();
    final chatId = '${ids[0]}_${ids[1]}';
    List<MessageModel> msgs = [];
    try {
      final rows = await Supabase.instance.client
          .from('private_messages')
          .select('id, sender_id, sender_name, text, type, image_data, created_at')
          .eq('chat_id', chatId)
          .eq('sender_id', user.uid)
          .order('created_at', ascending: false)
          .limit(unreadCount > 8 ? 8 : unreadCount);
      msgs = rows.map((r) => MessageModel.fromMap('${r['id']}', {
            'senderId': r['sender_id'],
            'senderName': r['sender_name'],
            'text': r['text'] ?? '',
            'type': r['type'] ?? 'text',
            'imageData': r['image_data'] ?? '',
            'createdAt': r['created_at'],
          })).toList();
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
        final bubbleHeight = (msgs.length * 48.0 + 40).clamp(72, 280).toDouble();
        double left = cardCenterX - bubbleWidth / 2;
        left = left.clamp(12, size.width - bubbleWidth - 12);
        // Nempel tepat: 0 gap + ekor 8px
        final spaceAbove = cardTopLeft.dy;
        final spaceBelow = size.height - (cardTopLeft.dy + cardSize.height);
        final isAbove = spaceAbove > spaceBelow && spaceAbove >= bubbleHeight + 16;
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
                      CustomPaint(size: const Size(14, 8), painter: _BubbleTailPainter(color: AppTheme.bgInput, isTop: true)),
                    ],
                    Container(
                      width: bubbleWidth,
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgInput,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
                        border: Border.all(color: AppTheme.divider.withValues(alpha: 0.8)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(user.nickname, style: AppText.bodyStrong),
                            const SizedBox(width: 6),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppTheme.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Text('$unreadCount baru', style: AppText.micro.copyWith(color: AppTheme.danger, fontWeight: FontWeight.w800))),
                            const Spacer(),
                            GestureDetector(onTap: () => entry.remove(), child: Icon(Icons.close, size: 16, color: AppTheme.textSecondary)),
                          ]),
                          Divider(height: 1, color: AppTheme.divider.withValues(alpha: 0.5)),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final m in msgs) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Expanded(child: Text(m.text.isNotEmpty ? m.text : (m.type == 'image' ? '[Foto]' : m.type), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodySmall)),
                                    const SizedBox(width: 8),
                                    Text(DateFormat('HH:mm').format(m.timestamp.toLocal()), style: AppText.micro.copyWith(color: AppTheme.textSecondary)),
                                  ]),
                                ),
                                if (m != msgs.last) Divider(height: 1, color: AppTheme.divider.withValues(alpha: 0.3)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isAbove) ...[
                      CustomPaint(size: const Size(14, 8), painter: _BubbleTailPainter(color: AppTheme.bgInput, isTop: false)),
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
    Future.delayed(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    super.build(context);
    final auth = context.watch<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.bgScreen,
        surfaceTintColor: AppTheme.bgScreen,
        toolbarHeight: 130,
        // Admin Panel di KIRI ATAS — hanya untuk zunixe (bukan sesi dummy).
        // Build user: panelBuilder null → tidak pernah tampil.
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
                      hintStyle: AppText.body.copyWith(color: AppTheme.textSecondary),
                      prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 36, minHeight: 0),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                )
              : Consumer<OnlineUsersProvider>(
                  key: const ValueKey('title'),
                  builder: (_, prov, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.titleOnline,
                        style: AppText.title.copyWith(color: AppTheme.textPrimary),
                      ),
                      Text(
                        '${prov.users.length} ${s.onlineActiveUsers}',
                        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      // Avatar + nama user sendiri di header
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  final b64 = auth.profile?.avatar ?? '';
                                  final init = (auth.profile?.nickname ?? '?')[0].toUpperCase();
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
                                  child: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                                    backgroundImage: (auth.profile?.avatar ?? '').isNotEmpty
                                        ? MemoryImage(base64Decode(auth.profile!.avatar))
                                        : null,
                                    child: (auth.profile?.avatar ?? '').isEmpty
                                        ? Text(
                                            (auth.profile?.nickname ?? '?')[0].toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: AppGlyph.avatarInitial(44),
                                              fontWeight: FontWeight.w800,
                                            ),
                                          )
                                        : null,
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
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 3,
                                        ),
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
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              auth.profile?.nickname ?? '-',
                              style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (auth.profile?.isRegistered == true) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              size: 16,
                              color: Color(0xFF4A90E2),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
        ),
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
        actions: [
          // "Orang Sekitar" (nearby) hanya untuk akun terdaftar — kombinasi
          // lokasi + anon paling sering memicu flag kebijakan Play.
          if (!auth.isAnonymous)
            IconButton(
              tooltip: s.nearbyTitle,
              icon: const Icon(Icons.explore_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NearbyScreen()),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Consumer<OnlineUsersProvider>(
            builder: (_, provider, __) {
              final chat = context.read<ChatProvider>();
              final allUsers = provider.users
                  .where((u) => u.uid != auth.uid && !chat.isBlocked(u.uid))
                  .toList();

              final users = allUsers.where((u) {
                if (_negara != 'all' && u.country != _negara) return false;
                if (_gender != 'all' && u.gender != _gender) return false;
                if (_search.isNotEmpty &&
                    !u.nickname.toLowerCase().contains(_search.toLowerCase())) {
                  return false;
                }
                return true;
              }).toList();

              final unreadMap = _unreadMap;

              final paged = users.take(_page * _pageSize).toList();
              final hasMore = paged.length < users.length;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _FilterDropdown(
                            value: _negara,
                            label: s.labelCountry,
                            icon: Icons.public,
                            items: ['all', ...allCountries],
                            labels: [s.filterAll, ...allCountries],
                            onChanged: (v) {
                              setState(() {
                                _negara = v;
                                _page = 1;
                              });
                              _saveFilter();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FilterDropdown(
                            value: _gender,
                            label: 'Gender',
                            icon: Icons.person_outline,
                            items: const ['all', 'male', 'female'],
                            labels: [s.filterAll, s.filterMale, s.filterFemale],
                            onChanged: (v) {
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
                              8,
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
                              8,
                              10,
                              MediaQuery.of(context).padding.bottom + 12,
                            ),
                            // Kartu ikut pindah posisi saat urutan berubah
                            // (sort last_seen) — State _AsyncAvatar tidak
                            // di-dispose/recreate → avatar tidak kedip.
                            findChildIndexCallback: (key) {
                              final k = key as ValueKey<String>;
                              final idx = paged.indexWhere(
                                (u) => 'uc-${u.uid}' == k.value,
                              );
                              return idx < 0 ? null : idx;
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
                              return Builder(
                                key: ValueKey('uc-${paged[i].uid}'),
                                builder: (cardCtx) => _UserCard(
                                  user: paged[i],
                                  onTap: () => _startChat(context, paged[i]),
                                  onLongPressStart: unreadMap[paged[i].uid] != null && unreadMap[paged[i].uid]! > 0
                                      ? (d) => _showUnreadBubble(cardCtx, paged[i], unreadMap[paged[i].uid]!, d.globalPosition)
                                      : null,
                                  unreadCount: unreadMap[paged[i].uid] ?? 0,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: ScaleTransition(
              scale: _shareScale,
              child: Tooltip(
                message: s.shareTooltip,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: _shareApp,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppTheme.headerGradient,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.ios_share,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            s.shareTooltip,
                            style: AppText.bodyStrong.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isTop;
  _BubbleTailPainter({required this.color, required this.isTop});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
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
    final border = Paint()..color = AppTheme.divider.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawPath(path, border);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final List<String> items;
  final List<String> labels;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary),
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          menuMaxHeight: 400,
          items: [
            for (int i = 0; i < items.length; i++)
              DropdownMenuItem(
                value: items[i],
                child: Text(
                  labels[i],
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppText.bodySmall,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final int unreadCount;
  const _UserCard({
    required this.user,
    required this.onTap,
    this.onLongPressStart,
    this.unreadCount = 0,
  });

  Color _statusColor(String status) {
    if (status == 'idle') return AppTheme.idle;
    if (status == 'offline') return AppTheme.offline;
    return AppTheme.online;
  }

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
    final statusLabel = user.status == 'idle'
        ? '${s.statusIdle} · ${_idleDurationLabel(user.lastSeen)}'
        : user.status == 'offline'
        ? s.statusOffline
        : s.statusOnline;

    return GestureDetector(
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.15),
                        border: Border.all(color: color, width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      // SELALU _AsyncAvatar (jangan ternary inisial↔foto):
                      // pergantian tipe widget menyebabkan State avatar
                      // di-dispose/dibuat-ulang tiap emission → kedip.
                      // Inisial dirender di dalam _AsyncAvatar.
                      child: _AsyncAvatar(
                          key: ValueKey(user.uid),
                          uid: user.uid,
                          avatarB64: user.avatar,
                          initial: user.initial,
                          color: color,
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
                            child: Text(
                              user.nickname,
                              style: AppText.bodyStrong,
                              overflow: TextOverflow.ellipsis,
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
                      Text(
                        '$genderLabel ${user.age} · ${user.city}, ${user.country}',
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                        // Tombol ikuti hanya untuk user yang ter-registrasi email.
                        if (user.isRegistered)
                          Consumer<SocialProvider>(
                            builder: (_, sp, __) {
                              final following = sp.isFollowing(user.uid);
                              return GestureDetector(
                                onTap: () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final ok = following
                                      ? await sp.unfollow(user.uid)
                                      : await sp.follow(user.uid);
                                  if (ok) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          following
                                              ? s.btnUnfollow
                                              : s.btnFollow,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: following
                                        ? AppTheme.primary.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppTheme.textSecondary.withValues(
                                            alpha: 0.10,
                                          ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    following
                                        ? Icons.person_remove
                                        : Icons.person_add,
                                    size: 17,
                                    color: following
                                        ? AppTheme.primary
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              );
                            },
                          ),
                        const SizedBox(width: 6),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline,
                            color: AppTheme.primary,
                            size: 17,
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
      ),
    ));
  }
}
