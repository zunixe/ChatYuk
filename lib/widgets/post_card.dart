import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/social_provider.dart';
import '../providers/timeline_provider.dart';
import '../core/cache/post_photo_cache.dart';
import '../services/avatar_service.dart';
import '../core/cache/media_disk_cache.dart';
import '../services/storage_photo_service.dart';
import '../utils.dart';
import 'post_photo_viewer.dart';
import 'profile_avatar.dart';
import '../screens/user_info_screen.dart';

/// Kartu postingan timeline: header + foto + caption + like/comment/share.
class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  Map<String, dynamic> get _p => widget.post;
  bool _busy = false;
  bool _followBusy = false;
  // Tinggi foto feed MENGIKUTI RASIO ASLI (ala Threads) — lebar tetap,
  // tinggi = lebar/rasio, di-clamp supaya ekstrem tidak mendominasi feed.
  static const double _kPhotoMinFactor = 0.35; // landscape ekstrem paling pendek
  static const double _kPhotoMaxFactor = 1.25; // portrait dicap (1.25× lebar)
  // Lebar foto single = 83% area konten — seukuran Threads.
  static const double _kSingleWidthFactor = 0.83;
  // Rasio seragam untuk CAROUSEL multi-foto (ala Threads 4:5).
  static const double _kCarouselAspect = 4 / 5; // w/h → tinggi = lebar * 5/4
  // Lebar carousel = isi penuh area konten (maxW). Area konten = layar −
  // padKiri(48) − padKanan(16) ≈ 83% layar — sama seperti Threads.
  static const double _kCarouselWidthFactor = 1.0;
  // Jarak tepi kiri konten (teks, foto, tombol like/komentar/share).
  // Avatar 38 + spacer 10 = 48 → konten sejajar tepi kanan avatar,
  // dan nama user sejajar sama jarak dari kiri.
  static const double _kContentPadH = 48;
  // Radius sudut foto agar terlihat rounded.
  static const double _kPhotoRadius = 14;
  final List<Uint8List?> _imageThumbs = [];
  // Rasio asli (w/h) per foto — sumber: payload `imageDims`/`imageW`/`imageH`
  // (akurat, tanpa shift) atau fallback decode bytes thumbnail.
  final List<double?> _imageAspect = [];
  final Set<String> _failedPaths = {};
  final PageController _pageCtrl = PageController();
  // GlobalKey untuk akses _CommentsListState saat kirim komentar (optimistic).
  final GlobalKey<_CommentsListState> _commentsKey =
      GlobalKey<_CommentsListState>();

  String get _id => '${_p['id']}';

  @override
  void initState() {
    super.initState();
    final paths = _imagePaths();
    _imageThumbs.addAll(List.filled(paths.length, null));
    _initAspects(paths);
    if (paths.isNotEmpty) _loadImages(paths);
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Path foto berubah (mis. realtime update / placeholder → path asli) →
    // muat ulang thumb. Dulu hanya di initState, jadi kartu tidak pernah
    // memperbarui gambar saat data post-nya diganti.
    final oldPaths = _pathsOf(oldWidget.post);
    final newPaths = _imagePaths();
    if (oldPaths.length != newPaths.length ||
        !List.generate(newPaths.length, (i) => oldPaths[i] == newPaths[i])
            .every((e) => e)) {
      _imageThumbs
        ..clear()
        ..addAll(List.filled(newPaths.length, null));
      _imageAspect.clear();
      _initAspects(newPaths);
      _failedPaths.clear();
      if (newPaths.isNotEmpty) _loadImages(newPaths);
    }
  }

  /// Isi rasio asli dari payload (`imageDims` array / `imageW`+`imageH`)
  /// tanpa perlu decode — ini yang bikin layout BENAR sejak frame pertama
  /// (nol layout shift). Post lama tanpa dimensi → null → fallback decode.
  void _initAspects(List<String> paths) {
    _imageAspect.addAll(List.filled(paths.length, null));
    final dims = _p['imageDims'];
    var filled = 0;
    if (dims is List) {
      for (var i = 0; i < paths.length; i++) {
        if (i >= dims.length) break;
        final d = dims[i];
        if (d is Map) {
          final w = (d['w'] as num?)?.toDouble() ?? 0;
          final h = (d['h'] as num?)?.toDouble() ?? 0;
          if (w > 0 && h > 0) {
            _imageAspect[i] = w / h;
            filled++;
          }
        }
      }
    }
    // Fallback: imageW/imageH (foto pertama) — post lama / payload parsial.
    if (filled == 0 && paths.isNotEmpty) {
      final w = (_p['imageW'] as num?)?.toDouble() ?? 0;
      final h = (_p['imageH'] as num?)?.toDouble() ?? 0;
      if (w > 0 && h > 0) _imageAspect[0] = w / h;
    }
  }

  /// Rasio (w/h) untuk foto ke-[i]; null = belum diketahui.
  double? _aspectOf(int i) =>
      i >= 0 && i < _imageAspect.length ? _imageAspect[i] : null;

  /// Kotak foto tunggal yang ngikutin proporsi asli (tidak dipaksa full-width):
  /// - pas di rentang clamp → selebar area, tinggi pas rasio (tanpa crop).
  /// - portrait ekstrem → tinggi dicap, lebar menyempit (rata kiri, tanpa crop).
  /// - landscape ekstrem → selebar area, tinggi min (crop atas-bawah).
  static ({double width, double height}) _photoBoxFor(
    double aspect,
    double maxW,
  ) {
    // Lebar single dibatasi 70% area (kompak, rata kiri).
    final w = maxW * _kSingleWidthFactor;
    final naturalH = w / aspect;
    final minH = maxW * _kPhotoMinFactor;
    final maxH = maxW * _kPhotoMaxFactor;
    if (naturalH > maxH) return (width: maxH * aspect, height: maxH);
    if (naturalH < minH) return (width: w, height: minH);
    return (width: w, height: naturalH);
  }

  /// Ukuran placeholder sebelum thumb tiba — pakai rasio payload kalau ada,
  /// else rasio carousel (4:5) sebagai default aman.
  ({double width, double height}) _placeholderBox(
    double maxW, {
    required bool multi,
  }) {
    if (multi) {
      final w = maxW * _kCarouselWidthFactor;
      return (width: w, height: w / _kCarouselAspect);
    }
    final a = _aspectOf(0);
    if (a != null && a > 0) return _photoBoxFor(a, maxW);
    final h = maxW / _kCarouselAspect;
    return (width: maxW, height: h);
  }

  /// Semua path foto gagal dimuat → tidak ada foto yang bisa tampil
  /// (bukan placeholder selamanya).
  bool _photosAllFailed() {
    final paths = _imagePaths();
    return paths.isNotEmpty && paths.every(_failedPaths.contains);
  }

  List<String> _pathsOf(Map<String, dynamic> post) {
    final arr = post['images'];
    if (arr is List && arr.isNotEmpty) {
      return arr.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    }
    final single = post['imagePath'] as String? ?? '';
    return single.isNotEmpty ? [single] : [];
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  List<String> _imagePaths() {
    final arr = _p['images'];
    if (arr is List && arr.isNotEmpty) {
      return arr.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    }
    final single = _p['imagePath'] as String? ?? '';
    return single.isNotEmpty ? [single] : [];
  }

  Future<void> _loadImages(List<String> paths) async {
    final cache = PostPhotoCache.instance;
    // Download paralel (max 4) + dedupe via loadMany — jauh lebih cepat
    // daripada loop thumb() sekuensial untuk post multi-foto.
    final thumbs = await cache.loadMany(paths);
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < paths.length; i++) {
        if (i >= _imageThumbs.length) break;
        final t = thumbs[paths[i]];
        if (t != null) {
          _imageThumbs[i] = t;
        } else {
          _failedPaths.add(paths[i]);
        }
      }
    });
    // Fallback rasio: post lama tanpa dimensi payload → decode rasio dari
    // bytes thumbnail (thumb = copyResize(width:1024) → rasio asli terjaga).
    await _fillAspectsFromThumbs(paths);
  }

  /// Isi rasio yang MASIH null dengan decode bytes thumbnail (off-main-thread).
  Future<void> _fillAspectsFromThumbs(List<String> paths) async {
    final missing = <int>[];
    for (var i = 0; i < paths.length; i++) {
      if (i < _imageAspect.length &&
          _imageAspect[i] == null &&
          i < _imageThumbs.length &&
          _imageThumbs[i] != null) {
        missing.add(i);
      }
    }
    if (missing.isEmpty) return;
    final computed = <int, double>{};
    for (final i in missing) {
      final bytes = _imageThumbs[i];
      if (bytes == null) continue;
      final a = await compute(_aspectRatioOfBytes, bytes);
      if (a != null && a > 0) computed[i] = a;
    }
    if (!mounted || computed.isEmpty) return;
    setState(() {
      for (final e in computed.entries) {
        if (e.key < _imageAspect.length && _imageAspect[e.key] == null) {
          _imageAspect[e.key] = e.value;
        }
      }
    });
  }

  Future<void> _like() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = context.read<LocaleProvider>().s;
    try {
      final res = await context.read<TimelineProvider>().toggleLike(_id);
      if (!mounted) return;
      final liked = res['liked'] == true;
      // Sumber kebenaran = server. RPC mengembalikan likeCount absolut
      // (migration 20260922000000). Hindari hitung `cur ± 1` yang bisa
      // dobel saat realtime UPDATE balapan menimpa nilai lokal.
      final serverCount = (res['likeCount'] as num?)?.toInt();
      final cur = (_p['likeCount'] as num?)?.toInt() ?? 0;
      final nextCount = serverCount ?? (liked ? cur + 1 : (cur - 1).clamp(0, 1 << 31));
      context.read<TimelineProvider>().updatePost(_id, {
        'isLiked': liked,
        'likeCount': nextCount,
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comment() async {
    final s = context.read<LocaleProvider>().s;
    final ctrl = TextEditingController();
    var replyToId = 0;
    var replyToName = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Kunci 70% layar: komentar sedikit = compact, komentar banyak =
      // list scroll di dalam 70% layar (tidak full-screen sampai atas).
      // Flexible di dalam Column(min) selalu mengisi tinggi MAKSIMAL route —
      // tanpa batas ini sheet ikut setinggi layar penuh.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            // Sheet dikunci 70% layar via constraints route (di atas);
            // input tetap di atas menu Android (nav/gesture bar) & keyboard.
            // viewInsets = keyboard; viewPadding = nav bar (tidak terpotong
            // saat keyboard terbuka) — kombinasi ini paling aman di MIUI.
            final bottom =
                MediaQuery.viewInsetsOf(ctx2).bottom +
                MediaQuery.viewPaddingOf(ctx2).bottom;
            final replying = replyToId > 0;
            return Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 12),
                  Text(
                    s.btnComment,
                    textAlign: TextAlign.center,
                    style: AppText.title,
                  ),
                  SizedBox(height: 8),
                  Flexible(
                    child: _CommentsList(
                      key: _commentsKey,
                      postId: _id,
                      onReply: (id, name) => setSheet(() {
                        replyToId = id;
                        replyToName = name;
                      }),
                    ),
                  ),
                  Divider(height: 1),
                  if (replying)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 6, 8, 0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              s.hintReplyTo(replyToName),
                              style: AppText.caption.copyWith(
                                color: AppTheme.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: AppTheme.textSecondary,
                            ),
                            onPressed: () => setSheet(() {
                              replyToId = 0;
                              replyToName = '';
                            }),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 8, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppTheme.bgCard,
                                width: 1,
                              ),
                            ),
                            child: TextField(
                              controller: ctrl,
                              style: AppText.body,
                              decoration: InputDecoration(
                                hintText: replying
                                    ? s.hintReplyTo(replyToName)
                                    : s.hintComment,
                                hintStyle: AppText.body.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              minLines: 1,
                              maxLines: 4,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendComment(
                                ctx2,
                                ctrl,
                                replyToId,
                                () => setSheet(() {
                                  replyToId = 0;
                                  replyToName = '';
                                }),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Tombol send bulatan — gaya sama dengan composer
                        // private chat (40px, primary, ikon putih).
                        GestureDetector(
                          onTap: () => _sendComment(
                            ctx2,
                            ctrl,
                            replyToId,
                            () => setSheet(() {
                              replyToId = 0;
                              replyToName = '';
                            }),
                          ),
                          child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.send_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendComment(
    BuildContext ctx,
    TextEditingController ctrl,
    int parentId,
    void Function() resetReply,
  ) async {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    // Sheet TETAP terbuka (dulu pop menutup seluruh sheet komentar).
    ctrl.clear();
    resetReply();
    FocusScope.of(ctx).unfocus();
    await _submitComment(text, parentId: parentId);
  }

  Future<void> _submitComment(String text, {int? parentId}) async {
    final s = context.read<LocaleProvider>().s;
    final tp = context.read<TimelineProvider>();
    final auth = context.read<AuthProvider>();
    // Id unik per kiriman — dua komentar cepat tidak tabrakan saat
    // replace/rollback (dulu konstanta -1 untuk semua).
    final optimisticId = -DateTime.now().microsecondsSinceEpoch;

    // Optimistic insert — tampil instant tanpa tunggu server.
    final optimistic = {
      'id': optimisticId,
      'postId': _id,
      'parentId': parentId ?? 0,
      'text': text,
      'authorId': auth.uid ?? '',
      'authorName': auth.profile?.nickname ?? s.labelYou,
      'authorGender': auth.profile?.gender ?? '',
      'likeCount': 0,
      'shareCount': 0,
      'isLiked': false,
      'createdAt': DateTime.now().toIso8601String(),
    };
    tp.addCommentToCache(_id, optimistic);
    // Sheet yang sedang terbuka memakai list lokal (snapshot) — tampilkan
    // juga di sana + gulir ke bawah (dulu hanya cache provider yang update).
    _commentsKey.currentState?.addItem(optimistic);
    _commentsKey.currentState?.scrollToBottom();

    try {
      final Map<String, dynamic> result;
      if (parentId != null && parentId > 0) {
        result = await tp.replyComment(_id, parentId, text);
      } else {
        result = await tp.addComment(_id, text);
      }
      // Server (add/reply_post_comment) hanya mengembalikan {ok, id} —
      // TANPA authorName/teks. Merge ke optimistic supaya nama user
      // langsung menetap (dulu replace mentah → jadi 'Anon' + teks
      // hilang + tombol hapus sembunyi sampai refetch berikutnya).
      final confirmed = <String, dynamic>{
        ...optimistic,
        ...result,
        'id': (result['id'] as num?)?.toInt() ?? optimisticId,
      };
      tp.replaceCommentInCache(_id, optimisticId, confirmed);
      _commentsKey.currentState?.replaceItem(optimisticId, confirmed);
      final cur = (_p['commentCount'] as num?)?.toInt() ?? 0;
      if (mounted) {
        tp.updatePost(_id, {'commentCount': cur + 1});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgCommented)));
      }
    } catch (_) {
      // Rollback optimistic insert jika gagal.
      tp.removeCommentFromCache(_id, optimisticId);
      _commentsKey.currentState?.removeItem(optimisticId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    }
  }

  Future<void> _share() async {
    final s = context.read<LocaleProvider>().s;
    final author = _p['authorName'] as String? ?? 'Anon';
    final text = (_p['text'] as String? ?? '').trim();
    // Link post → Play Store (identitas post via id) + teks author.
    final link =
        'https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';
    final content = text.isEmpty
        ? '$author\n\n$link'
        : '$author: $text\n\n$link';
    // Counter HANYA bertambah saat user benar-benar menyelesaikan share
    // (status success) — tap icon lalu batal tidak dihitung.
    final result = await Share.share(
      content,
      subject: author,
    );
    if (result.status != ShareResultStatus.success) return;
    try {
      await context.read<TimelineProvider>().sharePost(_id);
      if (!mounted) return;
      final c = ((_p['shareCount'] as num?)?.toInt() ?? 0) + 1;
      context.read<TimelineProvider>().updatePost(_id, {'shareCount': c});
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgShared)));
    }
  }

  Future<void> _boost() async {
    final s = context.read<LocaleProvider>().s;
    final tp = context.read<TimelineProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.btnBoost),
        content: Text(
          '${s.boostConfirm}\n\n${s.boostPaidLabel}: ${tp.boostPaid}\n${s.boostBonusLabel}: ${tp.boostBonus}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.btnCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.btnBoost),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<TimelineProvider>().boostPost(_id);
      if (mounted) {
        context.read<TimelineProvider>().updatePost(_id, {'isBoosted': true});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgBoosted)));
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase();
        final label = msg.contains('enough')
            ? s.errCoinInsufficient
            : s.errGeneric;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(label)));
      }
    }
  }

  String _visibilityLabel(String v) {
    final s = context.read<LocaleProvider>().s;
    switch (v) {
      case 'followers':
        return s.visFollowers;
      case 'subscribers':
        return s.visSubscribers;
      default:
        return s.visPublic;
    }
  }

  /// Toggle follow/unfollow author (ala Facebook: Follow ↔ Following).
  /// Guard anon (minta daftar dulu), cegah double-tap, dan patch
  /// `isFollowing` di post agar konsisten saat scroll.
  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    final authorId = _p['authorId'] as String? ?? '';
    if (authorId.isEmpty) return;
    final auth = context.read<AuthProvider>();
    if (auth.isAnonymous || !(auth.profile?.isRegistered ?? false)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<LocaleProvider>().s.msgRegisterToFollow),
        ),
      );
      return;
    }
    final sp = context.read<SocialProvider>();
    final currently =
        sp.isFollowing(authorId) || _p['isFollowing'] == true;
    setState(() => _followBusy = true);
    final ok =
        currently ? await sp.unfollow(authorId) : await sp.follow(authorId);
    if (!mounted) return;
    setState(() => _followBusy = false);
    // Hanya patch kalau RPC sukses — state tetap sinkron dengan server.
    if (ok) {
      context.read<TimelineProvider>().updatePost(_id, {
        'isFollowing': !currently,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final uid = context.select<AuthProvider, String?>((a) => a.uid);
    final authorId = _p['authorId'] as String? ?? '';
    final isAuthor = authorId.isNotEmpty && authorId == uid;
    final name = _p['authorName'] as String? ?? 'Anon';
    // Status follow: set global (realtime) ATAU bawaan server saat load.
    final following =
        context.select<SocialProvider, bool>((sp) => sp.isFollowing(authorId)) ||
        _p['isFollowing'] == true;
    final createdAt = parseDate(_p['createdAt']);
    final isLiked = _p['isLiked'] == true;
    final likeCount = (_p['likeCount'] as num?)?.toInt() ?? 0;
    final commentCount = (_p['commentCount'] as num?)?.toInt() ?? 0;
    final shareCount = (_p['shareCount'] as num?)?.toInt() ?? 0;
    final isBoosted = _p['isBoosted'] == true;
    final isFriend = _p['isFriend'] == true;

    // Konten (nama, teks, foto, tombol aksi) diberi padding kiri/kanan
    // supaya sejajar dengan tepi kanan avatar di header. Pemisah antar
    // post pakai Divider tipis full-width.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, thickness: 0.5),
        Padding(
          // Profil dempet ke kiri (tanpa padding kiri).
          padding: EdgeInsets.fromLTRB(0, 12, 8, 8),
          child: Row(
              children: [
                // Tap avatar = zoom foto (internal); tap nama = profil.
                _AuthorAvatar(post: _p, name: name, size: 38, onAvatarTap: _zoomAuthorPhoto),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: _openProfile,
                              child: Text(
                                name,
                                style: AppText.bodyStrong,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // Follow ↔ Following ala Facebook: di depan nama,
                          // tebal (tidak tipis), biru saat Follow.
                          if (!isAuthor) ...[
                            Text(
                              ' · ',
                              style: AppText.label.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            GestureDetector(
                              onTap: _followBusy ? null : _toggleFollow,
                              child: Text(
                                following
                                    ? s.socialFollowing
                                    : s.btnFollow,
                                style: AppText.label.copyWith(
                                  color: following
                                      ? AppTheme.textSecondary
                                      : AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          if (isFriend) ...[
                            SizedBox(width: 5),
                            Icon(
                              Icons.people_alt_rounded,
                              size: 13,
                              color: AppTheme.primary,
                            ),
                          ],
                          if (isBoosted) ...[
                            SizedBox(width: 5),
                            Icon(
                              Icons.rocket_launch_rounded,
                              size: 13,
                              color: AppTheme.danger,
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            _timeAgo(createdAt),
                            style: AppText.micro.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          SizedBox(width: 6),
                          _visibilityIcon(
                            _p['visibility'] as String? ?? 'public',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isAuthor) _authorMenu(s),
              ],
            ),
          ),
          if ((_p['text'] as String? ?? '').isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(_kContentPadH, 10, 16, 2),
              child: Text(_p['text'] as String, style: AppText.body),
            ),
          // Area foto dicadangkan sejak path diketahui (bukan saat thumb
          // tiba) — dulu blok 0→penuh tiba-tiba tiap thumb masuk → kartu
          // melompat saat scroll. Placeholder setinggi layout final.
          if (_imagePaths().isNotEmpty && !_photosAllFailed())
            Padding(
              // Kanan 16 — sejajar dengan teks di atasnya.
              padding: EdgeInsets.fromLTRB(_kContentPadH, 10, 16, 2),
              child: _photoGrid(),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(_kContentPadH, 4, 8, 8),
            child: Row(
              children: [
                _iconAction(
                  // Phosphor: outline saat mati, fill merah saat suka.
                  icon: isLiked
                      ? PhosphorIconsFill.heart
                      : PhosphorIconsRegular.heart,
                  color: isLiked ? AppTheme.danger : AppTheme.textSecondary,
                  scale: isLiked ? 1.2 : 1,
                  count: likeCount,
                  onTap: _like,
                ),
                _iconAction(
                  // Phosphor chat-circle — sekeluarga dengan heart.
                  icon: PhosphorIconsRegular.chatCircle,
                  color: AppTheme.textSecondary,
                  count: commentCount,
                  onTap: _comment,
                ),
                _iconAction(
                  // Phosphor paper-plane-tilt (gaya Threads).
                  icon: PhosphorIconsRegular.paperPlaneTilt,
                  color: AppTheme.textSecondary,
                  count: shareCount,
                  onTap: _share,
                ),
                const Spacer(),
                if (isAuthor)
                  _iconAction(
                    icon: isBoosted
                        ? Icons.rocket_launch_rounded
                        : Icons.rocket_launch_outlined,
                    color: isBoosted ? AppTheme.danger : AppTheme.primary,
                    count: 0,
                    showCount: false,
                    tooltip: s.btnBoost,
                    onTap: _boost,
                  ),
              ],
            ),
          ),
        ],
    );
  }

  /// Foto post — 1 foto lebar penuh; multi foto = strip thumbnail di atas +
  /// carousel slide kiri/kanan dengan badge counter di pojok foto.
  /// Tap foto → PostPhotoViewer (popup smooth, swipe multi foto, zoom).
  Widget _photoGrid() {
    final paths = _imagePaths();
    final loaded = <(Uint8List, String)>[];
    for (var i = 0; i < _imageThumbs.length; i++) {
      final t = _imageThumbs[i];
      if (t != null && i < paths.length) loaded.add((t, paths[i]));
    }
    final isMulti = paths.length > 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (loaded.isEmpty) {
          // Thumb belum tiba: placeholder seukuran layout final (rasio payload
          // kalau ada, else 4:5) supaya kartu tidak melompat saat foto masuk.
          final box = _placeholderBox(maxW, multi: isMulti);
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              key: const ValueKey('photo_placeholder'),
              width: box.width,
              height: box.height,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(_kPhotoRadius),
              ),
            ),
          );
        }
        // Foto tunggal — kotak pas proporsi asli (rata kiri); cover hanya
        // motong bila landscape ekstrem (kotak min-height).
        Widget singlePhoto() => GestureDetector(
          onTap: () => _openViewer(0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kPhotoRadius),
            child: Image.memory(
              loaded[0].$1,
              fit: BoxFit.cover,
              // Feed lebar ~layar; cap ~1080 cukup tajam, hemat RAM utk
              // scroll banyak post.
              cacheWidth: 1080,
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        );
        // Foto carousel — Positioned.fill + badge counter "2/3" sebagai
        // penanda bahwa foto bisa di-slide. Hanya dipakai di PageView.
        Widget carouselPhoto(int i) => GestureDetector(
          onTap: () => _openViewer(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kPhotoRadius),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.memory(
                    loaded[i].$1,
                    fit: BoxFit.cover,
                    cacheWidth: 1080,
                    gaplessPlayback: true,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${i + 1}/${loaded.length}',
                      style: AppText.micro.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        if (loaded.length == 1) {
          // Kotak ngikutin proporsi asli (rata kiri, kanan tidak dipaksa) —
          // rasio dari payload, atau fallback thumb yang baru diketahui.
          // Rasio belum diketahui → tetap pakai LEBAR 50% + rasio 1:1
          // (JANGAN maxW penuh — itu bikin foto tampak full-width).
          final a = _aspectOf(0);
          final box = a != null && a > 0
              ? _photoBoxFor(a, maxW)
              : (width: maxW * _kSingleWidthFactor,
                 height: maxW * _kSingleWidthFactor);
          return AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                key: const ValueKey('photo_single'),
                width: box.width,
                height: box.height,
                child: singlePhoto(),
              ),
            ),
          );
        }
        // Multi foto: carousel geser kiri/kanan (ala Threads) — rasio seragam
        // 4:5, lebar ~83% layar, anchor kiri. Tanpa strip thumbnail.
        final carouselW = maxW * _kCarouselWidthFactor;
        final carouselH = carouselW / _kCarouselAspect;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: carouselW,
            height: carouselH,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: loaded.length,
              itemBuilder: (_, i) => carouselPhoto(i),
            ),
          ),
        );
      },
    );
  }

  void _openViewer(int index) {
    final paths = _imagePaths();
    // Pasangkan thumb yang SUKSES dengan path-nya masing-masing (bukan
    // sublist N pertama) — kalau ada foto gagal load, full-res di viewer
    // bisa tertukar (bug: paths.sublist(0, thumbs.length)).
    final loadedPaths = <String>[];
    final thumbs = <Uint8List>[];
    final aspects = <double?>[];
    for (var i = 0; i < _imageThumbs.length; i++) {
      final t = _imageThumbs[i];
      if (t != null && i < paths.length) {
        loadedPaths.add(paths[i]);
        thumbs.add(t);
        aspects.add(_aspectOf(i));
      }
    }
    if (thumbs.isEmpty) return;
    PostPhotoViewer.show(
      context,
      paths: loadedPaths,
      thumbs: thumbs,
      aspects: aspects,
      initialIndex: index,
    );
  }

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required int count,
    required VoidCallback onTap,
    bool showCount = true,
    String? tooltip,
    double scale = 1,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 250),
                curve: Curves.elasticOut,
                child: Icon(icon, size: 18, color: color),
              ),
              if (showCount) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: AppText.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _visibilityIcon(String v) {
    final (icon, color) = switch (v) {
      'followers' => (Icons.people_outline_rounded, AppTheme.primary),
      'subscribers' => (Icons.star_outline_rounded, Colors.amber.shade700),
      _ => (Icons.public, AppTheme.textSecondary),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          _visibilityLabel(v),
          style: AppText.micro.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Menu ⋮ untuk post milik sendiri: hapus.
  Widget _authorMenu(S s) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 18, color: AppTheme.textSecondary),
      padding: EdgeInsets.zero,
      color: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) {
        if (v == 'delete') _deletePost(s);
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppTheme.danger,
              ),
              const SizedBox(width: 8),
              Text(
                s.btnDelete,
                style: AppText.body.copyWith(color: AppTheme.danger),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deletePost(S s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.btnDelete),
        content: Text(s.confirmDeletePost),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.btnDelete,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<TimelineProvider>().deletePost(_id);
      if (!mounted) return;
      context.read<TimelineProvider>().removePost(_id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.postDeleted)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errDeletePost)));
      }
    }
  }

  void _openProfile() {
    final uid = _p['authorId'] as String? ?? '';
    if (uid.isEmpty) return;
    final name = _p['authorName'] as String? ?? 'Anon';
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserInfoScreen(userId: uid, fallbackName: name)),
    );
  }

  /// Zoom foto avatar author (InteractiveViewer ala menu online) — tap
  /// avatar di header post, tanpa pindah ke halaman profil.
  void _zoomAuthorPhoto(Uint8List? bytes) {
    final name = _p['authorName'] as String? ?? 'Anon';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
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
                        // Cap 1080px: dialog zoom tidak butuh full-res.
                        child: Image.memory(
                          zoomBytes,
                          fit: BoxFit.contain,
                          cacheWidth: 1080,
                        ),
                      )
                    : CircleAvatar(
                        radius: 90,
                        backgroundColor: AppTheme.primary,
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

  String _timeAgo(DateTime t) => _timeAgoShort(t);
}

class _CommentsList extends StatefulWidget {
  final String postId;
  final void Function(int id, String name)? onReply;
  const _CommentsList({super.key, required this.postId, this.onReply});

  @override
  State<_CommentsList> createState() => _CommentsListState();
}

class _CommentsListState extends State<_CommentsList> {
  List<Map<String, dynamic>>? _items;
  bool _busy = false;
  // true setelah fetch pertama selesai (atau cache ada) — sebelum itu
  // tampilkan skeleton, bukan kotak kosong.
  bool _loaded = false;
  RealtimeChannel? _channel;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Baca cache dulu — tampil instant tanpa network.
    final cached = context.read<TimelineProvider>().getCachedComments(
      widget.postId,
    );
    if (cached != null) {
      _items = List.from(cached);
      _loaded = true;
    }
    // RPC hanya bila cache tidak ada / basi (TTL 30 dtk) — buka-tutup-buka
    // sheet tidak menembak server berulang.
    final tp = context.read<TimelineProvider>();
    if (!tp.isCommentsFresh(widget.postId)) _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        ch.unsubscribe();
        Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Realtime komentar HANYA untuk post ini (filter post_id) — komentar baru
  /// dari orang lain muncul live; unsubscribe saat sheet ditutup.
  void _subscribeRealtime() {
    try {
      final sb = Supabase.instance.client;
      final ch = sb.channel('post-comments-${widget.postId}');
      final filter = PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'post_id',
        value: widget.postId,
      );
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'post_comments',
        filter: filter,
        callback: (_) {
          if (mounted) _load();
        },
      );
      ch.subscribe();
      _channel = ch;
    } catch (_) {}
  }

  Future<void> _load() async {
    final list = await context.read<TimelineProvider>().comments(widget.postId);
    if (!mounted) return;
    context.read<TimelineProvider>().cacheComments(widget.postId, list);
    // Jangan timpa optimistic user yang belum terkonfirmasi server: bila
    // item lokal punya id negatif (optimistic), pertahankan — kecuali server
    // sudah mengembalikannya (cocok author+teks) supaya tidak dobel.
    final local = _items;
    if (local != null && local.any((c) => ((c['id'] as num?)?.toInt() ?? 0) < 0)) {
      final pendings = local
          .where((c) => ((c['id'] as num?)?.toInt() ?? 0) < 0)
          .toList();
      final kept = pendings.where((p) {
        return !list.any(
          (s) =>
              '${s['authorId'] ?? ''}' == '${p['authorId'] ?? ''}' &&
              '${s['text'] ?? ''}' == '${p['text'] ?? ''}',
        );
      }).toList();
      final merged = <Map<String, dynamic>>[...list, ...kept];
      setState(() {
        _items = merged;
        _loaded = true;
      });
      return;
    }
    setState(() {
      _items = list;
      _loaded = true;
    });
  }

  /// Tambah komentar optimistic ke list lokal (dipanggil via GlobalKey).
  void addItem(Map<String, dynamic> comment) {
    setState(() => _items = [...?_items, comment]);
  }

  /// Ganti komentar optimistic dengan data server (dipanggil via GlobalKey).
  void replaceItem(dynamic oldId, Map<String, dynamic> newComment) {
    if (_items == null) return;
    setState(() {
      _items = [
        for (final c in _items!)
          if (c['id'] == oldId) newComment else c,
      ];
    });
  }

  /// Gulir ke komentar terbawah (dipanggil setelah kirim sendiri).
  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (max <= 0) return;
      _scrollCtrl.animateTo(
        max,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// Hapus komentar dari list lokal — rollback jika gagal (dipanggil via GlobalKey).
  void removeItem(dynamic id) {
    if (_items == null) return;
    setState(() => _items = _items!.where((c) => c['id'] != id).toList());
  }

  Future<void> _like(Map<String, dynamic> c) async {
    if (_busy) return;
    _busy = true;
    final id = (c['id'] as num?)?.toInt() ?? 0;
    try {
    final res = await context.read<TimelineProvider>().toggleCommentLike(id);
    if (!mounted) return;
    final liked = res['liked'] == true;
    // Sumber kebenaran = server (likeCount absolut), bukan hitung lokal.
    final serverCount = (res['likeCount'] as num?)?.toInt();
    final count = serverCount ??
        (((c['likeCount'] as num?)?.toInt() ?? 0) + (liked ? 1 : -1));
    setState(() {
      c['isLiked'] = liked;
      c['likeCount'] = count < 0 ? 0 : count;
    });
    } catch (_) {}
    _busy = false;
  }

  Future<void> _share(Map<String, dynamic> c) async {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    final s = context.read<LocaleProvider>().s;
    final author = c['authorName'] as String? ?? 'Anon';
    final text = (c['text'] as String? ?? '').trim();
    // Sama seperti share post: sheet sistem dulu, counter + snackbar
    // hanya bila user benar-benar menyelesaikan share.
    final link =
        'https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';
    final content = text.isEmpty ? '$author\n\n$link' : '$author: $text\n\n$link';
    final result = await Share.share(content, subject: author);
    if (result.status != ShareResultStatus.success) return;
    try {
      final res = await context.read<TimelineProvider>().shareComment(id);
      final count = (res['share_count'] as num?)?.toInt();
      if (!mounted) return;
      if (count != null) {
        setState(() => c['shareCount'] = count);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgShared)));
      }
    } catch (_) {}
  }

  /// Hapus komentar sendiri (konfirmasi dulu). Id ≤ 0 = optimistic yang
  /// belum terkonfirmasi server — abaikan (segera terganti data server).
  Future<void> _delete(Map<String, dynamic> c) async {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    final s = context.read<LocaleProvider>().s;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(s.commentDeleteTitle),
        content: Text(s.commentDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<TimelineProvider>().deleteComment(widget.postId, id);
      if (!mounted) return;
      setState(
        () => _items = _items!
            .where((e) => (e['id'] as num?)?.toInt() != id)
            .toList(),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.commentDeleted)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    final myUid = context.read<AuthProvider>().uid ?? '';
    if (!_loaded && items.isEmpty) return const _CommentSkeleton();
    if (items.isEmpty) {
      return const SizedBox(height: 80);
    }
    // Flexible di parent sudah memberi tinggi BOUNDED → tidak perlu
    // shrinkWrap (dulu shrinkWrap:true membangun SEMUA baris sekaligus,
    // boros untuk post dengan banyak komentar). ListView biasa hanya
    // membangun baris yang terlihat.
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        final isReply = ((c['parentId'] as num?)?.toInt() ?? 0) > 0;
        final createdAt = DateTime.tryParse(c['createdAt'] as String? ?? '');
        final likeCount = (c['likeCount'] as num?)?.toInt() ?? 0;
        final shareCount = (c['shareCount'] as num?)?.toInt() ?? 0;
        final isLiked = c['isLiked'] == true;
        final name = c['authorName'] as String? ?? 'Anon';
        final text = c['text'] as String? ?? '';
        final id = (c['id'] as num?)?.toInt() ?? 0;
        final authorId = '${c['authorId'] ?? ''}';
        final isMine = authorId.isNotEmpty && authorId == myUid;
        return Padding(
          padding: EdgeInsets.only(left: isReply ? 26 : 0, bottom: 12),
          // Bar luar rata bawah → like sejajar baris terakhir teks.
          // Bar dalam rata atas → avatar tetap di atas.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                child: Text(
                  (name.isEmpty ? 'A' : name[0]).toUpperCase(),
                  style: AppText.label.copyWith(color: AppTheme.primary),
                ),
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
                            name,
                            style: AppText.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (createdAt != null) ...[
                          SizedBox(width: 6),
                          Text(
                            '· ${_timeAgoShort(createdAt)}',
                            style: AppText.micro.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                        // Hapus hanya untuk komentar sendiri (server RLS
                        // author-only sebagai penegak terakhir).
                        if (isMine) ...[
                          SizedBox(width: 2),
                          InkWell(
                            onTap: () => _delete(c),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.delete_outline,
                                size: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(text, style: AppText.bodySmall),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        _CommentAction(
                          icon: isLiked
                              ? PhosphorIconsFill.heart
                              : PhosphorIconsRegular.heart,
                          color: isLiked
                              ? AppTheme.danger
                              : AppTheme.textSecondary,
                          count: likeCount,
                          onTap: () => _like(c),
                        ),
                        _CommentAction(
                          icon: PhosphorIconsRegular.chatCircle,
                          color: AppTheme.textSecondary,
                          count: null,
                          onTap: () => widget.onReply?.call(id, name),
                        ),
                        _CommentAction(
                          icon: PhosphorIconsRegular.paperPlaneTilt,
                          color: AppTheme.textSecondary,
                          count: shareCount,
                          onTap: () => _share(c),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Skeleton baris komentar saat fetch pertama (gantikan kotak kosong 80px
/// supaya sheet terasa instan).
class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
          width: w,
          height: 10,
          decoration: BoxDecoration(
            color: AppTheme.bgInput,
            borderRadius: BorderRadius.circular(5),
          ),
        );
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.bgInput,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(90),
                      const SizedBox(height: 6),
                      bar(double.infinity),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CommentAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int? count;
  final VoidCallback onTap;
  const _CommentAction({
    required this.icon,
    required this.color,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        // Ritme proporsional dengan bar aksi utama (ikon 18/pad 8 →
        // ikon 14/pad 6): jarak antar-ikon datang dari padding item.
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            if (count != null && count! > 0) ...[
              SizedBox(width: 4),
              Text(
                '$count',
                style: AppText.micro.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _timeAgoShort(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// Avatar pengirim post — pakai `authorAvatar` dari payload list_posts
/// (path storage atau base64) supaya TIDAK query profil per post.
/// Kotak rounded (sama dengan avatar di Pesan), bukan lingkaran.
/// Fallback ke ProfileAvatar (query + cache per uid) jika payload kosong.
class _AuthorAvatar extends StatefulWidget {
  final Map<String, dynamic> post;
  final String name;
  final double size;
  /// Tap avatar → zoom foto (dipisah dari tap nama → profil), pola sama
  /// dengan menu online. Menerima bytes hasil resolve (null = inisial).
  final void Function(Uint8List? bytes)? onAvatarTap;
  const _AuthorAvatar({
    required this.post,
    required this.name,
    required this.size,
    this.onAvatarTap,
  });

  @override
  State<_AuthorAvatar> createState() => _AuthorAvatarState();
}

class _AuthorAvatarState extends State<_AuthorAvatar> {
  // Resolve SATU tahap langsung ke bytes per identitas avatar (fetch +
  // decode) — tanpa FutureBuilder dua tahap (fallback → future → decode
  // → foto) yang terlihat kedip. Rebuild/scroll tidak memicu kerja ulang.
  static final _bytesCache = <String, Uint8List>{};
  Uint8List? _bytes;
  String? _resolvedFor;

  @override
  void initState() {
    super.initState();
    // Jalur SINKRON dulu: cache statis → disk → decode B64 inline.
    // Berhasil = frame pertama langsung foto (tanpa fallback inisial).
    // Gagal (perlu network) = jalur async seperti dulu.
    if (!_resolveSync()) _resolveAsync();
  }

  @override
  void didUpdateWidget(_AuthorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post['authorAvatar'] != widget.post['authorAvatar']) {
      _bytes = null;
      _resolvedFor = null;
      if (!_resolveSync()) _resolveAsync();
    }
  }

  /// Resolve sinkron sebelum frame pertama. Return true kalau bytes
  /// langsung tersedia (tidak perlu setState — build() jalan sesudahnya).
  bool _resolveSync() {
    final avatar = widget.post['authorAvatar'] as String? ?? '';
    if (avatar.isEmpty) return false;
    _resolvedFor = avatar;
    try {
      final cached = _bytesCache[avatar];
      if (cached != null) {
        _bytes = cached;
        return true;
      }
      if (StoragePhotoService.instance.isAvatarPath(avatar)) {
        final disk = MediaDiskCache.instance.readSync(avatar);
        if (disk != null && disk.isNotEmpty) {
          if (_bytesCache.length < 60) _bytesCache[avatar] = disk;
          _bytes = disk;
          return true;
        }
        return false;
      }
      // B64 inline kecil → decode sinkron langsung (tanpa compute).
      if (avatar.length < 200000) {
        final b = base64Decode(avatar);
        if (b.isNotEmpty) {
          if (_bytesCache.length < 60) _bytesCache[avatar] = b;
          _bytes = b;
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _resolveAsync() async {
    final avatar = widget.post['authorAvatar'] as String? ?? '';
    if (avatar.isEmpty) return;
    if (_resolvedFor == avatar && _bytes != null) return;
    _resolvedFor = avatar;
    final cached = _bytesCache[avatar];
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    final isPath = StoragePhotoService.instance.isAvatarPath(avatar);
    final b64 =
        isPath ? await AvatarB64Service.instance.getByPath(avatar) : avatar;
    if (b64.isEmpty || !mounted) return;
    if (_resolvedFor != avatar) return;
    final bytes = await compute(_decodeAvatarB64, b64);
    if (bytes == null || !mounted || _resolvedFor != avatar) return;
    if (_bytesCache.length < 60) _bytesCache[avatar] = bytes;
    setState(() => _bytes = bytes);
  }

  Widget _fallback(String uid) => ProfileAvatar(
        uid: uid,
        name: widget.name,
        size: widget.size,
        borderRadius: widget.size / 2,
      );

  @override
  Widget build(BuildContext context) {
    final uid = widget.post['authorId'] as String? ?? '';
    final avatar = widget.post['authorAvatar'] as String? ?? '';
    final tap = widget.onAvatarTap == null
        ? null
        : () => widget.onAvatarTap!(_bytes);
    if (avatar.isEmpty) {
      return tap == null
          ? _fallback(uid)
          : GestureDetector(onTap: tap, child: _fallback(uid));
    }
    final bytes = _bytes;
    // Belum siap → fallback (ProfileAvatar ikut lazy-load dari lokal,
    // jadi satu pop-in halus, bukan kedip berulang).
    if (bytes == null || _resolvedFor != avatar) {
      return tap == null
          ? _fallback(uid)
          : GestureDetector(onTap: tap, child: _fallback(uid));
    }
    final img = ClipRRect(
      borderRadius: BorderRadius.circular(widget.size / 2),
      child: Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        cacheWidth: (widget.size * 2).round(),
        gaplessPlayback: true,
      ),
    );
    return tap == null ? img : GestureDetector(onTap: tap, child: img);
  }
}

Uint8List? _decodeAvatarB64(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

/// Rasio asli (w/h) dari bytes gambar — top-level untuk compute().
/// Dipakai fallback post lama yang belum menyimpan dimensi.
Future<double?> _aspectRatioOfBytes(Uint8List bytes) async {
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    if (w <= 0 || h <= 0) return null;
    return w / h;
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}
