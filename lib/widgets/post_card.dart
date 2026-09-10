import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/timeline_provider.dart';
import '../services/post_photo_cache.dart';
import '../services/avatar_service.dart';
import '../services/media_disk_cache.dart';
import '../services/storage_photo_service.dart';
import '../services/timeline_service.dart';
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
  final List<Uint8List?> _imageThumbs = [];
  final Set<String> _failedPaths = {};
  final PageController _pageCtrl = PageController();
  int _page = 0;
  // GlobalKey untuk akses _CommentsListState saat kirim komentar (optimistic).
  final GlobalKey<_CommentsListState> _commentsKey =
      GlobalKey<_CommentsListState>();

  String get _id => '${_p['id']}';

  @override
  void initState() {
    super.initState();
    final paths = _imagePaths();
    _imageThumbs.addAll(List.filled(paths.length, null));
    if (paths.isNotEmpty) _loadImages(paths);
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
  }

  Future<void> _like() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = context.read<LocaleProvider>().s;
    try {
      final res = await TimelineService().toggleLike(_id);
      if (!mounted) return;
      final liked = res['liked'] == true;
      final cur = (_p['likeCount'] as num?)?.toInt() ?? 0;
      context.read<TimelineProvider>().updatePost(_id, {
        'isLiked': liked,
        'likeCount': liked ? cur + 1 : (cur - 1).clamp(0, 1 << 31),
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
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setSheet) {
            // Compact (bukan full page): sheet menempel bawah seperti dulu,
            // tapi input tetap di atas menu Android (nav/gesture bar) & keyboard.
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
                              onSubmitted: (_) =>
                                  _sendComment(ctx2, ctrl, replyToId),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Tombol send bulatan — gaya sama dengan composer
                        // private chat (40px, primary, ikon putih).
                        GestureDetector(
                          onTap: () => _sendComment(ctx2, ctrl, replyToId),
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
  ) async {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    Navigator.of(ctx).pop();
    await _submitComment(text, parentId: parentId);
  }

  Future<void> _submitComment(String text, {int? parentId}) async {
    final s = context.read<LocaleProvider>().s;
    final tp = context.read<TimelineProvider>();
    final auth = context.read<AuthProvider>();
    const optimisticId = -1;

    // Optimistic insert — tampil instant tanpa tunggu server.
    final optimistic = {
      'id': optimisticId,
      'postId': _id,
      'parentId': parentId ?? 0,
      'text': text,
      'authorId': auth.uid ?? '',
      'authorName': auth.profile?.nickname ?? 'Kamu',
      'authorGender': auth.profile?.gender ?? '',
      'likeCount': 0,
      'shareCount': 0,
      'isLiked': false,
      'createdAt': DateTime.now().toIso8601String(),
    };
    tp.addCommentToCache(_id, optimistic);

    try {
      final Map<String, dynamic> result;
      if (parentId != null && parentId > 0) {
        result = await TimelineService().replyComment(_id, parentId, text);
      } else {
        result = await TimelineService().addComment(_id, text);
      }
      // Ganti optimistic dengan data server.
      tp.replaceCommentInCache(_id, optimisticId, result);
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
      await TimelineService().sharePost(_id);
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
      await TimelineService().boostPost(_id);
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final uid = context.select<AuthProvider, String?>((a) => a.uid);
    final isAuthor = _p['authorId'] == uid;
    final name = _p['authorName'] as String? ?? 'Anon';
    final createdAt = parseDate(_p['createdAt']);
    final isLiked = _p['isLiked'] == true;
    final likeCount = (_p['likeCount'] as num?)?.toInt() ?? 0;
    final commentCount = (_p['commentCount'] as num?)?.toInt() ?? 0;
    final shareCount = (_p['shareCount'] as num?)?.toInt() ?? 0;
    final isBoosted = _p['isBoosted'] == true;
    final isFriend = _p['isFriend'] == true;

    return Container(
      margin: EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
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
              padding: EdgeInsets.fromLTRB(14, 10, 14, 2),
              child: Text(_p['text'] as String, style: AppText.body),
            ),
          if (_imageThumbs.any((t) => t != null))
            Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: _photoGrid(),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(6, 4, 6, 8),
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
      ),
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
    if (loaded.isEmpty) return const SizedBox.shrink();
    // Foto tunggal — tanpa Stack supaya tinggi natural (bukan unbounded).
    Widget singlePhoto() => GestureDetector(
      onTap: () => _openViewer(0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(
          loaded[0].$1,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
    // Foto carousel — Positioned.fill + badge counter "2/3" sebagai penanda
    // bahwa foto bisa di-slide. Hanya dipakai di PageView (tinggi bounded).
    Widget carouselPhoto(int i) => GestureDetector(
      onTap: () => _openViewer(i),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.memory(
                loaded[i].$1,
                fit: BoxFit.cover,
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
      return SizedBox(width: double.infinity, child: singlePhoto());
    }
    // Multi foto: thumbnail strip di atas (klik → ganti foto besar) +
    // carousel slide kiri/kanan.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: loaded.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _pageCtrl.animateToPage(
                i,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: i == _page ? 52 : 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: i == _page ? AppTheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    loaded[i].$1,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: loaded.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => carouselPhoto(i),
          ),
        ),
      ],
    );
  }

  void _openViewer(int index) {
    final paths = _imagePaths();
    // Pasangkan thumb yang SUKSES dengan path-nya masing-masing (bukan
    // sublist N pertama) — kalau ada foto gagal load, full-res di viewer
    // bisa tertukar (bug: paths.sublist(0, thumbs.length)).
    final loadedPaths = <String>[];
    final thumbs = <Uint8List>[];
    for (var i = 0; i < _imageThumbs.length; i++) {
      final t = _imageThumbs[i];
      if (t != null && i < paths.length) {
        loadedPaths.add(paths[i]);
        thumbs.add(t);
      }
    }
    if (thumbs.isEmpty) return;
    PostPhotoViewer.show(
      context,
      paths: loadedPaths,
      thumbs: thumbs,
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
      await TimelineService().deletePost(_id);
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
    );
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

  @override
  void initState() {
    super.initState();
    // Baca cache dulu — tampil instant tanpa network.
    final cached = context.read<TimelineProvider>().getCachedComments(
      widget.postId,
    );
    if (cached != null) _items = List.from(cached);
    _load();
  }

  Future<void> _load() async {
    final list = await TimelineService().comments(widget.postId);
    if (!mounted) return;
    context.read<TimelineProvider>().cacheComments(widget.postId, list);
    setState(() => _items = list);
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
      final res = await TimelineService().toggleCommentLike(id);
      if (!mounted) return;
      final liked = res['liked'] == true;
      final count = ((c['likeCount'] as num?)?.toInt() ?? 0) + (liked ? 1 : -1);
      setState(() {
        c['isLiked'] = liked;
        c['likeCount'] = count < 0 ? 0 : count;
      });
    } catch (_) {}
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    if (items.isEmpty) {
      return const SizedBox(height: 80);
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        final isReply = ((c['parentId'] as num?)?.toInt() ?? 0) > 0;
        final createdAt = DateTime.tryParse(c['createdAt'] as String? ?? '');
        final likeCount = (c['likeCount'] as num?)?.toInt() ?? 0;
        final isLiked = c['isLiked'] == true;
        final name = c['authorName'] as String? ?? 'Anon';
        final text = c['text'] as String? ?? '';
        return Padding(
          padding: EdgeInsets.only(left: isReply ? 26 : 0, bottom: 12),
          // Bar luar rata bawah → like sejajar baris terakhir teks.
          // Bar dalam rata atas → avatar tetap di atas.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppTheme.primary.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        (name.isEmpty ? 'A' : name[0]).toUpperCase(),
                        style: AppText.label.copyWith(
                          color: AppTheme.primary,
                        ),
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
                            ],
                          ),
                          SizedBox(height: 2),
                          Text(text, style: AppText.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Like doang, mentok kanan card.
              _CommentAction(
                icon: isLiked
                    ? PhosphorIconsFill.heart
                    : PhosphorIconsRegular.heart,
                color: isLiked ? AppTheme.danger : AppTheme.textSecondary,
                count: likeCount,
                onTap: () => _like(c),
              ),
            ],
          ),
        );
      },
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
