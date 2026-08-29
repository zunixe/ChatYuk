import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/timeline_provider.dart';
import '../services/post_photo_cache.dart';
import '../services/avatar_service.dart';
import '../services/storage_photo_service.dart';
import '../services/timeline_service.dart';
import '../utils.dart';
import 'post_photo_viewer.dart';
import 'profile_avatar.dart';
import '../screens/other_profile_screen.dart';

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
                              style: TextStyle(color: AppTheme.textPrimary),
                              decoration: InputDecoration(
                                hintText: replying
                                    ? s.hintReplyTo(replyToName)
                                    : s.hintComment,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                isDense: true,
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) =>
                                  _sendComment(ctx2, ctrl, replyToId),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: AppTheme.primary),
                          onPressed: () => _sendComment(ctx2, ctrl, replyToId),
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
    try {
      await TimelineService().sharePost(_id);
      if (!mounted) return;
      final c = ((_p['shareCount'] as num?)?.toInt() ?? 0) + 1;
      context.read<TimelineProvider>().updatePost(_id, {'shareCount': c});
    } catch (_) {}
    final author = _p['authorName'] as String? ?? 'Anon';
    final text = (_p['text'] as String? ?? '').trim();
    await Share.share(text.isEmpty ? author : '$author: $text');
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
                GestureDetector(onTap: _openProfile, child: _AuthorAvatar(post: _p, name: name, size: 38)),
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
                  icon: isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isLiked ? AppTheme.danger : AppTheme.textSecondary,
                  scale: isLiked ? 1.2 : 1,
                  count: likeCount,
                  onTap: _like,
                ),
                _iconAction(
                  // Speech bubble bulat — icon comment khas Threads.
                  icon: Icons.chat_bubble_outline_rounded,
                  color: AppTheme.textSecondary,
                  count: commentCount,
                  onTap: _comment,
                ),
                _iconAction(
                  // Paper plane — icon share khas Threads.
                  icon: Icons.send_outlined,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 250),
                curve: Curves.elasticOut,
                child: Icon(icon, size: 20, color: color),
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
    final me = context.read<AuthProvider>().uid;
    if (uid == me) return;
    final avatar = _p['authorAvatar'] as String? ?? '';
    final name = _p['authorName'] as String? ?? 'Anon';
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OtherProfileScreen(uid: uid, name: name, avatar: avatar)),
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

  Future<void> _share(Map<String, dynamic> c) async {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    try {
      final res = await TimelineService().shareComment(id);
      final count = (res['share_count'] as num?)?.toInt();
      if (!mounted) return;
      if (count != null) setState(() => c['shareCount'] = count);
    } catch (_) {}
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
        final shareCount = (c['shareCount'] as num?)?.toInt() ?? 0;
        final isLiked = c['isLiked'] == true;
        final name = c['authorName'] as String? ?? 'Anon';
        final text = c['text'] as String? ?? '';
        final id = (c['id'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: EdgeInsets.only(left: isReply ? 26 : 0, bottom: 12),
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
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(text, style: AppText.bodySmall),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        _CommentAction(
                          icon: isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: isLiked
                              ? AppTheme.danger
                              : AppTheme.textSecondary,
                          count: likeCount,
                          onTap: () => _like(c),
                        ),
                        SizedBox(width: 16),
                        _CommentAction(
                          icon: Icons.chat_bubble_outline,
                          color: AppTheme.textSecondary,
                          count: null,
                          onTap: () => widget.onReply?.call(id, name),
                        ),
                        SizedBox(width: 16),
                        _CommentAction(
                          icon: Icons.send_outlined,
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
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
class _AuthorAvatar extends StatelessWidget {
  final Map<String, dynamic> post;
  final String name;
  final double size;
  const _AuthorAvatar({
    required this.post,
    required this.name,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final uid = post['authorId'] as String? ?? '';
    final avatar = post['authorAvatar'] as String? ?? '';
    if (avatar.isEmpty) {
      return ProfileAvatar(
        uid: uid,
        name: name,
        size: size,
        borderRadius: size / 2,
      );
    }
    final isPath = StoragePhotoService.instance.isAvatarPath(avatar);
    return FutureBuilder<String>(
      future: isPath
          ? AvatarB64Service.instance.getByPath(avatar)
          : Future.value(avatar),
      builder: (_, snap) {
        final b64 = snap.data ?? '';
        if (b64.isEmpty) {
          return ProfileAvatar(
            uid: uid,
            name: name,
            size: size,
            borderRadius: size / 2,
          );
        }
        return _RoundedAvatar(
          base64: b64,
          size: size,
          fallback: ProfileAvatar(
            uid: uid,
            name: name,
            size: size,
            borderRadius: size / 2,
          ),
        );
      },
    );
  }
}

/// Avatar kotak rounded dari base64 — pola sama dengan Pesan (rounded
/// square), decode async di isolate + cache sederhana.
class _RoundedAvatar extends StatefulWidget {
  final String base64;
  final double size;
  final Widget fallback;
  const _RoundedAvatar({
    required this.base64,
    required this.size,
    required this.fallback,
  });

  @override
  State<_RoundedAvatar> createState() => _RoundedAvatarState();
}

class _RoundedAvatarState extends State<_RoundedAvatar> {
  Uint8List? _bytes;
  static final _cache = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.base64];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await compute(_decodeAvatarB64, widget.base64);
    if (!mounted || bytes == null) return;
    if (_cache.length < 60) _cache[widget.base64] = bytes;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size / 2),
      child: Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

Uint8List? _decodeAvatarB64(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}
