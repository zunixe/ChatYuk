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
      final liked = res['liked'] == true;
      final cur = (_p['likeCount'] as num?)?.toInt() ?? 0;
      context.read<TimelineProvider>().updatePost(_id, {
        'isLiked': liked,
        'likeCount': liked ? cur + 1 : (cur - 1).clamp(0, 1 << 31),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comment() async {
    final s = context.read<LocaleProvider>().s;
    final ctrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 12),
            Text(s.btnComment, textAlign: TextAlign.center, style: AppText.title),
            SizedBox(height: 8),
            Flexible(child: _CommentsList(postId: _id)),
            Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 8, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.bgCard, width: 1),
                      ),
                      child: TextField(
                        controller: ctrl,
                        style: TextStyle(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          hintText: s.hintComment,
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
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppTheme.primary),
                    onPressed: () async {
                      final text = ctrl.text.trim();
                      if (text.isEmpty) return;
                      Navigator.of(ctx).pop();
                      await _submitComment(text);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitComment(String text) async {
    final s = context.read<LocaleProvider>().s;
    try {
      await TimelineService().addComment(_id, text);
      final cur = (_p['commentCount'] as num?)?.toInt() ?? 0;
      if (mounted) {
        context.read<TimelineProvider>().updatePost(_id, {'commentCount': cur + 1});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgCommented)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    }
  }

  Future<void> _share() async {
    final s = context.read<LocaleProvider>().s;
    try {
      await TimelineService().sharePost(_id);
      final c = ((_p['shareCount'] as num?)?.toInt() ?? 0) + 1;
      context.read<TimelineProvider>().updatePost(_id, {'shareCount': c});
    } catch (_) {}
    final author = _p['authorName'] as String? ?? 'Anon';
    final text = (_p['text'] as String? ?? '').trim();
    await Share.share(text.isEmpty ? author : '$author: $text');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgShared)));
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.btnCancel)),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.btnBoost)),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await TimelineService().boostPost(_id);
      if (mounted) {
        context.read<TimelineProvider>().updatePost(_id, {'isBoosted': true});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgBoosted)));
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase();
        final label = msg.contains('enough') ? s.errCoinInsufficient : s.errGeneric;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
      }
    }
  }

  String _visibilityLabel(String v) {
    final s = context.read<LocaleProvider>().s;
    switch (v) {
      case 'followers': return s.visFollowers;
      case 'subscribers': return s.visSubscribers;
      default: return s.visPublic;
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
                _AuthorAvatar(post: _p, name: name, size: 38),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name, style: AppText.bodyStrong, overflow: TextOverflow.ellipsis),
                          ),
                          if (isFriend) ...[
                            SizedBox(width: 5),
                            Icon(Icons.people_alt_rounded, size: 13, color: AppTheme.primary),
                          ],
                          if (isBoosted) ...[
                            SizedBox(width: 5),
                            Icon(Icons.rocket_launch_rounded, size: 13, color: AppTheme.danger),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Text(_timeAgo(createdAt), style: AppText.micro.copyWith(color: AppTheme.textSecondary)),
                          SizedBox(width: 6),
                          _visibilityIcon(_p['visibility'] as String? ?? 'public'),
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
                  icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isLiked ? AppTheme.danger : AppTheme.textSecondary,
                  count: likeCount,
                  onTap: _like,
                ),
                _iconAction(
                  icon: Icons.mode_comment_outlined,
                  color: AppTheme.textSecondary,
                  count: commentCount,
                  onTap: _comment,
                ),
                _iconAction(
                  icon: Icons.send_outlined,
                  color: AppTheme.textSecondary,
                  count: shareCount,
                  onTap: _share,
                ),
                const Spacer(),
                if (isAuthor)
                  _iconAction(
                    icon: isBoosted ? Icons.rocket_launch_rounded : Icons.rocket_launch_outlined,
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

  /// Grid foto post — kotak-kotak (1 foto lebar penuh, >1 grid 3 kolom).
  /// Tap foto → PostPhotoViewer (popup smooth, swipe multi foto, zoom).
  Widget _photoGrid() {
    final paths = _imagePaths();
    final loaded = <(Uint8List, String)>[];
    for (var i = 0; i < _imageThumbs.length; i++) {
      final t = _imageThumbs[i];
      if (t != null && i < paths.length) loaded.add((t, paths[i]));
    }
    if (loaded.isEmpty) return const SizedBox.shrink();
    Widget photo(int i) => GestureDetector(
          onTap: () => _openViewer(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              loaded[i].$1,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        );
    if (loaded.length == 1) {
      return SizedBox(
        width: double.infinity,
        child: photo(0),
      );
    }
    // Multi foto: carousel slide kiri/kanan + indikator dot.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 260,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: loaded.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => photo(i),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < loaded.length; i++)
              AnimatedContainer(
                duration: Duration(milliseconds: 200),
                margin: EdgeInsets.symmetric(horizontal: 2),
                width: i == _page ? 14 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? AppTheme.primary : AppTheme.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _openViewer(int index) {
    final paths = _imagePaths();
    final thumbs = <Uint8List>[];
    for (var i = 0; i < _imageThumbs.length; i++) {
      final t = _imageThumbs[i];
      if (t != null && i < paths.length) thumbs.add(t);
    }
    if (thumbs.isEmpty) return;
    PostPhotoViewer.show(
      context,
      paths: paths.sublist(0, thumbs.length),
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
  }) {    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              if (showCount) ...[
                const SizedBox(width: 4),
                Text('$count', style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
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
          style: AppText.micro.copyWith(color: color, fontWeight: FontWeight.w600),
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
              const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.danger),
              const SizedBox(width: 8),
              Text(s.btnDelete, style: AppText.body.copyWith(color: AppTheme.danger)),
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
            child: Text(s.btnDelete, style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await TimelineService().deletePost(_id);
      if (!mounted) return;
      context.read<TimelineProvider>().removePost(_id);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.postDeleted)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.errDeletePost)));
      }
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

class _CommentsList extends StatelessWidget {
  final String postId;
  const _CommentsList({required this.postId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: TimelineService().comments(postId),
      builder: (_, snap) {
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const SizedBox(height: 80);
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: list.length,
          itemBuilder: (_, i) {
            final c = list[i];
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                child: Text(
                  (c['author_name'] as String? ?? 'A')[0].toUpperCase(),
                  style: AppText.label.copyWith(color: AppTheme.primary),
                ),
              ),
              title: Text(c['author_name'] as String? ?? 'Anon', style: AppText.label),
              subtitle: Text(c['text'] as String? ?? '', style: AppText.bodySmall),
            );
          },
        );
      },
    );
  }
}

/// Avatar pengirim post — pakai `authorAvatar` dari payload list_posts
/// (path storage atau base64) supaya TIDAK query profil per post.
/// Kotak rounded (sama dengan avatar di Pesan), bukan lingkaran.
/// Fallback ke ProfileAvatar (query + cache per uid) jika payload kosong.
class _AuthorAvatar extends StatelessWidget {
  final Map<String, dynamic> post;
  final String name;
  final double size;
  const _AuthorAvatar({required this.post, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final uid = post['authorId'] as String? ?? '';
    final avatar = post['authorAvatar'] as String? ?? '';
    if (avatar.isEmpty) {
      return ProfileAvatar(uid: uid, name: name, size: size, borderRadius: size / 2);
    }
    final isPath = StoragePhotoService.instance.isAvatarPath(avatar);
    return FutureBuilder<String>(
      future: isPath
          ? AvatarB64Service.instance.getByPath(avatar)
          : Future.value(avatar),
      builder: (_, snap) {
        final b64 = snap.data ?? '';
        if (b64.isEmpty) {
          return ProfileAvatar(uid: uid, name: name, size: size, borderRadius: size / 2);
        }
        return _RoundedAvatar(
          base64: b64,
          size: size,
          fallback: ProfileAvatar(uid: uid, name: name, size: size, borderRadius: size / 2),
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
  const _RoundedAvatar({required this.base64, required this.size, required this.fallback});

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
