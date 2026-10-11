import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/social_provider.dart';
import '../providers/riverpod/timeline_provider.dart';
import '../core/cache/post_photo_cache.dart';
import '../core/media/native_image.dart';
import '../core/perf/perf_probe.dart';
import '../core/nav_guard.dart';
import '../utils.dart';
import 'post/comment_widgets.dart';
import 'post/author_avatar.dart';
import 'post/comments_list.dart';
import 'post/share_to_user.dart';
import 'post/author_photo_zoom.dart';
import 'post/post_photo_grid.dart';
import 'post_photo_viewer.dart';
import 'post_share_sheet.dart';
import '../screens/user_info_screen.dart';
import 'package:share_plus/share_plus.dart';

/// Kirim teks share ke chat pribadi user lain. Return true bila terkirim.
/// Dipakai bersama oleh share post & share komentar (counter + snackbar
/// diurus masing-masing pemanggil supaya tidak dobel).

/// Kartu postingan timeline: header + foto + caption + like/comment/share.
class PostCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> post;

  /// Dipanggil setelah post berhasil dihapus. Di feed kartu hilang sendiri
  /// via `removePost`; di layar detail (PostDetailScreen) callback ini dipakai
  /// untuk pop kembali ke feed.
  final VoidCallback? onDeleted;

  const PostCard({super.key, required this.post, this.onDeleted});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  Map<String, dynamic> get _p => widget.post;
  bool _busy = false;
  bool _followBusy = false;
  // Controller komentar dibuat SEKALI per kartu (dulu dibuat di dalam
  // `_comment()` tiap buka sheet → tidak pernah di-dispose = leak + kerja
  // alokasi tiap kali sheet dibuka = buka terasa lambat).
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }
  // Jarak tepi kiri konten (teks, foto, tombol like/komentar/share).
  // Avatar 38 + spacer 10 = 48 → konten sejajar tepi kanan avatar,
  // dan nama user sejajar sama jarak dari kiri.
  static const double _kContentPadH = 48;
  final List<Uint8List?> _imageThumbs = [];
  // Rasio asli (w/h) per foto — sumber: payload `imageDims`/`imageW`/`imageH`
  // (akurat, tanpa shift) atau fallback decode bytes thumbnail.
  final List<double?> _imageAspect = [];
  final Set<String> _failedPaths = {};
  // GlobalKey untuk akses CommentsListState saat kirim komentar (optimistic).
  final GlobalKey<CommentsListState> _commentsKey =
      GlobalKey<CommentsListState>();

  String get _id => '${_p['id']}';

  @override
  void initState() {
    super.initState();
    final paths = _imagePaths();
    _imageThumbs.addAll(List.filled(paths.length, null));
    _initAspects(paths);
    // ANTI-KEDIP: thumb yang SUDAH ada di RAM/disk dibaca SINKRON dulu (frame
    // pertama Timeline langsung foto). Tanpa ini placeholder tampil dulu →
    // thumb menyusul post-frame = kedip saat cold start (pola sama foto chat).
    var syncHit = false;
    for (var i = 0; i < paths.length; i++) {
      final t = PostPhotoCache.instance.thumbSync(paths[i]);
      if (t != null && t.isNotEmpty) {
        _imageThumbs[i] = t;
        syncHit = true;
      }
    }
    // PERF: foto yang BELUM ada di cache TIDAK dimuat di initState (frame
    // pertama hanya layout). Dimuat post-frame — plus `cacheExtent` kecil di
    // Timeline, kartu di luar viewport tak mengunduh+decode foto.
    if (paths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Sudah lengkap dari cache sinkron → tak perlu fetch lagi.
        if (syncHit && _imageThumbs.every((t) => t != null)) return;
        _loadImages(_imagePaths());
      });
    }
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
    var changed = false;
    for (var i = 0; i < paths.length; i++) {
      if (i >= _imageThumbs.length) break;
      final t = thumbs[paths[i]];
      if (t != null) {
        if (_imageThumbs[i] == null) {
          _imageThumbs[i] = t;
          changed = true;
        }
      } else {
        if (_failedPaths.add(paths[i])) changed = true;
      }
    }
    // Fallback rasio: post lama tanpa dimensi payload → decode rasio dari
    // bytes thumbnail (thumb = copyResize(width:1024) → rasio asli terjaga).
    // SATU setState untuk thumb + rasio (dulu 2 rebuild per kartu), dan
    // lewati rebuild sama sekali bila tidak ada yang berubah (mis. notify
    // provider yang me-reload kartu saat scroll).
    if (await _fillAspectsFromThumbs(paths)) changed = true;
    if (!mounted) return;
    if (!changed) return;
    setState(() {});
  }

  /// Isi rasio yang MASIH null dengan SATU compute isolate untuk semua foto
  /// (dulu satu isolate per foto → spawn berulang saat scroll cepat).
  /// Return true bila ada rasio yang terisi. Tanpa setState sendiri —
  /// pemanggil me-rebuild sekali setelahnya.
  Future<bool> _fillAspectsFromThumbs(List<String> paths) async {
    final idx = <int>[];
    final jobs = <Uint8List>[];
    for (var i = 0; i < paths.length; i++) {
      if (i < _imageAspect.length &&
          _imageAspect[i] == null &&
          i < _imageThumbs.length &&
          _imageThumbs[i] != null) {
        idx.add(i);
        jobs.add(_imageThumbs[i]!);
      }
    }
    if (jobs.isEmpty) return false;
    final computed = await NativeImage.aspectRatios(jobs);
    var filled = false;
    for (var k = 0; k < idx.length && k < computed.length; k++) {
      final a = computed[k];
      final i = idx[k];
      if (a != null && a > 0 && i < _imageAspect.length && _imageAspect[i] == null) {
        _imageAspect[i] = a;
        filled = true;
      }
    }
    return filled;
  }

  Future<void> _like() async {
    if (_busy) return;
    // OPTIMISTIK: UI langsung berubah (hati + counter) TANPA menunggu
    // network — hapus delay saat tap. RPC jalan di belakang; hasil server
    // merekonsiliasi angka absolut, error → kembalikan ke nilai awal.
    final tp = ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier);
    final curLiked = _p['isLiked'] == true;
    final curCount = (_p['likeCount'] as num?)?.toInt() ?? 0;
    final optLiked = !curLiked;
    final optCount = optLiked
        ? curCount + 1
        : (curCount - 1).clamp(0, 1 << 31);
    tp.updatePost(_id, {'isLiked': optLiked, 'likeCount': optCount});
    setState(() => _busy = true);
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    try {
      final res = await tp.toggleLike(_id);
      if (!mounted) return;
      final liked = res['liked'] == true;
      // Sumber kebenaran = server (RPC mengembalikan likeCount absolut).
      final serverCount = (res['likeCount'] as num?)?.toInt();
      tp.updatePost(_id, {
        'isLiked': liked,
        'likeCount': serverCount ?? optCount,
      });
    } catch (_) {
      // Gagal → balikkan ke state semula (anti "hati nempel").
      tp.updatePost(_id, {'isLiked': curLiked, 'likeCount': curCount});
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
    // Controller dibuat SEKALI di State (di-dispose di dispose()) — dulu
    // alokasi baru tiap buka sheet → buka terasa lambat + leak.
    _commentCtrl.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Sheet dikelola oleh StatefulWidget sendiri (CommentSheet) sehingga
      // perubahan state internal (mode balas / fokus) TIDAK merelayout
      // seluruh sheet lewat StatefulBuilder di root. Mengetik kini hanya
      // memicu repaint TextField (dibungkus RepaintBoundary), bukan rebuild
      // list komentar.
      builder: (_) => CommentSheet(
        postId: _id,
        ctrl: _commentCtrl,
        commentsKey: _commentsKey,
        onSubmit: _submitComment,
      ),
    );
  }

  Future<void> _submitComment(String text, {int? parentId}) async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final tp = ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier);
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
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
      'authorAvatar': auth.profile?.avatar ?? '',
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

  /// Tulis foto post ke file temp untuk shareXFiles. Ambil dari thumb
  /// yang sudah tampil dulu (instan), fallback download via cache.
  Future<List<XFile>> _shareFilesFor(List<String> paths, String postId) async {
    final safeId = postId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    try {
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      final cache = PostPhotoCache.instance;
      for (var i = 0; i < paths.length; i++) {
        try {
          Uint8List? bytes;
          if (i < _imageThumbs.length) bytes = _imageThumbs[i];
          bytes ??= await cache.thumb(paths[i]);
          if (bytes == null || bytes.isEmpty) continue;
          final f = File('${dir.path}/chatyuk_post_${safeId}_$i.jpg');
          await f.writeAsBytes(bytes, flush: true);
          files.add(XFile(f.path, mimeType: 'image/jpeg'));
        } catch (_) {}
      }
      return files;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _share() async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final author = _p['authorName'] as String? ?? 'Anon';
    final authorUid = _p['authorId'] as String? ?? '';
    final authorGender = _p['authorGender'] as String? ?? '';
    final text = (_p['text'] as String? ?? '').trim();
    // Teks = konten post + link ChatYuk (bilingual via strings).
    final content = s.postShareMsg(author, text);
    final snippet = text.length > 120 ? '${text.substring(0, 120)}…' : text;
    await showPostShareSheet(
      context: context,
      authorUid: authorUid,
      authorName: author,
      authorGender: authorGender,
      snippet: snippet,
      shareText: content,
      shareSubject: author,
      // Foto ikut dibagikan bila ada — pola sama seperti story (tulis thumb
      // ke file temp lalu shareXFiles). Tanpa ini penerima cuma dapat teks
      // + link Play Store.
      buildFiles: () => _shareFilesFor(_imagePaths(), _id),
      onShareToUser: (user) => _shareToUser(user, content),
      onExternalShared: () => _bumpShareCount(),
    );
  }

  /// Bagikan post ke user ChatYuk lain via chat pribadi. Return true bila
  /// terkirim (sheet menutup diri + snackbar "Dibagikan ke X").
  Future<bool> _shareToUser(UserModel user, String content) async {
    final ok = await sendShareToUser(context, user, content);
    if (!ok) return false;
    await _bumpShareCount();
    if (!mounted) return true;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.shareSentTo(user.nickname))));
    return true;
  }

  /// Counter HANYA bertambah saat user benar-benar menyelesaikan share
  /// (status success / terkirim ke user) — tap lalu batal tidak dihitung.
  Future<void> _bumpShareCount() async {
    final tp = ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier);
    try {
      await tp.sharePost(_id);
      if (!mounted) return;
      final c = ((_p['shareCount'] as num?)?.toInt() ?? 0) + 1;
      tp.updatePost(_id, {'shareCount': c});
    } catch (_) {}
  }

  Future<void> _boost() async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final tp = ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier);
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
      await ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).boostPost(_id);
      if (mounted) {
        ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).updatePost(_id, {'isBoosted': true});
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
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
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
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    if (auth.isAnonymous || !(auth.profile?.isRegistered ?? false)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ProviderScope.containerOf(context, listen: false).read(localeProvider).s.msgRegisterToFollow),
        ),
      );
      return;
    }
    final sp = ProviderScope.containerOf(context, listen: false).read(socialProvider.notifier);
    final currently =
        sp.isFollowing(authorId) || _p['isFollowing'] == true;
    setState(() => _followBusy = true);
    final ok =
        currently ? await sp.unfollow(authorId) : await sp.follow(authorId);
    if (!mounted) return;
    setState(() => _followBusy = false);
    // Hanya patch kalau RPC sukses — state tetap sinkron dengan server.
    if (ok) {
      ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).updatePost(_id, {
        'isFollowing': !currently,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('PostCard');
    final s = ref.watch(localeProvider).s;
    final uid = ref.watch(authProvider.select((a) => a.uid));
    final authorId = _p['authorId'] as String? ?? '';
    final isAuthor = authorId.isNotEmpty && authorId == uid;
    final name = _p['authorName'] as String? ?? 'Anon';
    // Status follow: set global (realtime) ATAU bawaan server saat load.
    final following =
        ref.watch(socialProvider.select((sp) => sp.isFollowing(authorId))) ||
        _p['isFollowing'] == true;
    final createdAt = parseDate(_p['createdAt']);
    final isLiked = _p['isLiked'] == true;
    final likeCount = (_p['likeCount'] as num?)?.toInt() ?? 0;
    final commentCount = (_p['commentCount'] as num?)?.toInt() ?? 0;
    final shareCount = (_p['shareCount'] as num?)?.toInt() ?? 0;
    final isBoosted = _p['isBoosted'] == true;
    // Status teman: set global (realtime) ATAU bawaan server saat load.
    // Realtime stream `posts` tidak membawa is_friend (computed di RPC), jadi
    // sumber utama = SocialNotifier.isFriend(authorId).
    final isFriend =
        ref.watch(socialProvider.select((sp) => sp.isFriend(authorId))) ||
        _p['isFriend'] == true;

    // Konten (nama, teks, foto, tombol aksi) diberi padding kiri/kanan
    // supaya sejajar dengan tepi kanan avatar di header. Pemisah antar
    // post pakai Divider tipis full-width.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, thickness: 0.5),
        Padding(
          // Profil dempet ke kiri (tanpa padding kiri).
          padding: EdgeInsets.fromLTRB(0, 12, 8, 2),
          child: Row(
              children: [
                // Tap avatar = zoom foto (internal); tap nama = profil.
                PostAuthorAvatar(post: _p, name: name, size: 38, onAvatarTap: _zoomAuthorPhoto),
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
                              child: Tooltip(
                                message:
                                    '${following ? s.btnUnfollow : s.btnFollow} · ${s.sheetFollowDesc}',
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
                          const SizedBox(width: 3),
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
              padding: EdgeInsets.fromLTRB(_kContentPadH, 2, 16, 2),
              child: Text(_p['text'] as String, style: AppText.body),
            ),
          // Area foto dicadangkan sejak path diketahui (bukan saat thumb
          // tiba) — dulu blok 0→penuh tiba-tiba tiap thumb masuk → kartu
          // melompat saat scroll. Placeholder setinggi layout final.
          if (_imagePaths().isNotEmpty && !_photosAllFailed())
            Padding(
              // Kanan 16 — sejajar dengan teks di atasnya.
              padding: EdgeInsets.fromLTRB(_kContentPadH, 2, 16, 2),
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
  Widget _photoGrid() => PostPhotoGrid(
    thumbs: _imageThumbs,
    aspects: _imageAspect,
    onOpenViewer: _openViewer,
  );


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
    // PENTING: `index` = indeks di `_imageThumbs` (semua foto), tapi
    // `loadedPaths`/`thumbs` sudah DIFILTER (foto gagal-load dibuang) →
    // panjangnya bisa lebih kecil. Kalau `index` diteruskan apa adanya,
    // `PageController(initialPage:)` bisa di luar rentang → RangeError saat
    // viewer membangun halaman (crash "aplikasi mati saat buka timeline").
    // Petakan: index foto pertama yang berhasil ≥ index asli, kalau tidak
    // jatuh ke elemen terakhir.
    var mapped = -1;
    for (var i = 0; i < loadedPaths.length; i++) {
      if (loadedPaths[i] == paths[index.clamp(0, paths.length - 1)]) {
        mapped = i;
        break;
      }
    }
    if (mapped < 0) {
      mapped = (index < loadedPaths.length) ? index : loadedPaths.length - 1;
    }
    PostPhotoViewer.show(
      context,
      paths: loadedPaths,
      thumbs: thumbs,
      aspects: aspects,
      initialIndex: mapped.clamp(0, loadedPaths.length - 1),
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
        const SizedBox(width: 2),
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
      await ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).deletePost(_id);
      if (!mounted) return;
      ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).removePost(_id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.postDeleted)));
      widget.onDeleted?.call();
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
    final navKey = navKeyUser(uid);
    if (!tryClaimNav(navKey)) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserInfoScreen(userId: uid, fallbackName: name)),
    ).then((_) => releaseNav(navKey));
  }

  /// Zoom foto avatar author (InteractiveViewer ala menu online) — tap
  /// avatar di header post, tanpa pindah ke halaman profil.
  void _zoomAuthorPhoto(Uint8List? bytes) {
    final name = _p['authorName'] as String? ?? 'Anon';
    showAuthorPhotoZoomDialog(context, bytes, name: name);
  }


  String _timeAgo(DateTime t) => timeAgoShort(t);
}

/// Sheet komentar — state TERISOLASI dari list komentar.
///
/// Dulu seluruh sheet dibangun dalam `StatefulBuilder` di root: setiap
/// perubahan (mode balas, munculnya keyboard) memicu rebuild yang menyentuh
/// `CommentsList` (ListView + avatar) → mengetik terasa ngelag. Kini:
///  - mode balas dikelola di sini (setState lokal),
///  - `CommentsList` TIDAK ikut rebuild saat mengetik/balas (dibungkus
///    RepaintBoundary + hanya bergantung pada onReply),
///  - `TextField` dibungkus RepaintBoundary sehingga ketikan hanya
///    merepaint dirinya sendiri,
///  - tinggi sheet tetap 70% & bar input naik sendiri di atas keyboard.

/// Skeleton baris komentar saat fetch pertama (gantikan kotak kosong 80px
/// supaya sheet terasa instan).

/// Avatar pengirim post — pakai `authorAvatar` dari payload list_posts
/// (path storage atau base64) supaya TIDAK query profil per post.
/// Kotak rounded (sama dengan avatar di Pesan), bukan lingkaran.
/// Fallback ke ProfileAvatar (query + cache per uid) jika payload kosong.

/// Avatar penulis KOMENTAR — pola lazy-load SAMA dengan `_AuthorAvatar`
/// (foto dari payload `authorAvatar` dulu: cache statis → disk → decode,
/// baru async), dan fallback memakai `GenderAvatar` supaya yang tanpa foto
/// tampil lingkar warna gender (male=biru/female=pink) seperti daftar
/// "Pengguna Online".

// Rasio asli (w/h) banyak gambar diproses di NATIVE via
// `NativeImage.aspectRatios` (header-only, tanpa decode penuh; fallback ke
// `dartAspectRatios` Dart di lib/core/media/chat_photo_helper.dart).


