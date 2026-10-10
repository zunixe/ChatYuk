import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_model.dart';
import '../../providers/riverpod/auth_provider.dart';
import '../../providers/riverpod/timeline_provider.dart';
import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../post_share_sheet.dart';
import '../verified_badge.dart';
import 'comment_avatar.dart';
import 'comment_widgets.dart';
import 'share_to_user.dart';

class CommentSheet extends ConsumerStatefulWidget {
  final String postId;
  final TextEditingController ctrl;
  final GlobalKey<CommentsListState> commentsKey;
  final Future<void> Function(String text, {int? parentId}) onSubmit;
  const CommentSheet({
    required this.postId,
    required this.ctrl,
    required this.commentsKey,
    required this.onSubmit,
  });

  @override
  ConsumerState<CommentSheet> createState() => CommentSheetState();
}

class CommentSheetState extends ConsumerState<CommentSheet> {
  int _replyToId = 0;
  String _replyToName = '';

  void _setReply(int id, String name) {
    if (_replyToId == id && _replyToName == name) return;
    setState(() {
      _replyToId = id;
      _replyToName = name;
    });
  }

  void _clearReply() {
    if (_replyToId == 0) return;
    setState(() {
      _replyToId = 0;
      _replyToName = '';
    });
  }

  Future<void> _send(BuildContext ctx) async {
    final text = widget.ctrl.text.trim();
    if (text.isEmpty) return;
    final parentId = _replyToId;
    // Sheet TETAP terbuka (dulu pop menutup seluruh sheet komentar).
    widget.ctrl.clear();
    _clearReply();
    FocusScope.of(ctx).unfocus();
    await widget.onSubmit(text, parentId: parentId > 0 ? parentId : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final replying = _replyToId > 0;
    // Tinggi tetap 70% layar — loading/empty/isi sama persis (anti glitch).
    final sheetH = MediaQuery.sizeOf(context).height * 0.7;
    // Sheet DIAM di 70% (tak ikut naik saat keyboard). viewInsets dibuang
    // dari subtree lewat removeViewInsets, lalu hanya BAR INPUT yang digeser
    // ke atas keyboard.
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final navPad = MediaQuery.viewPaddingOf(context).bottom;
    final kb = insets > navPad ? insets : navPad;
    return SizedBox(
      height: sheetH,
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(s.btnComment, textAlign: TextAlign.center, style: AppText.title),
            const SizedBox(height: 8),
            Expanded(
              // RepaintBoundary: ketikan/balasan tidak memicu repaint list.
              child: RepaintBoundary(
                child: CommentsList(
                  key: widget.commentsKey,
                  postId: widget.postId,
                  onReply: _setReply,
                ),
              ),
            ),
            const Divider(height: 1),
            if (replying)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        s.hintReplyTo(_replyToName),
                        style: AppText.caption.copyWith(color: AppTheme.primary),
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
                      onPressed: _clearReply,
                    ),
                  ],
                ),
              ),
            // Bar input naik di atas keyboard — list komentar & sheet DIAM.
            AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: kb),
              child: RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 16),
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
                            controller: widget.ctrl,
                            style: AppText.body,
                            decoration: InputDecoration(
                              hintText: replying
                                  ? s.hintReplyTo(_replyToName)
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
                            onSubmitted: (_) => _send(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Tombol send bulatan — gaya sama dengan composer
                      // private chat (40px, primary, ikon putih).
                      GestureDetector(
                        onTap: () => _send(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.4),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommentsList extends ConsumerStatefulWidget {
  final String postId;
  final void Function(int id, String name)? onReply;
  const CommentsList({super.key, required this.postId, this.onReply});

  @override
  ConsumerState<CommentsList> createState() => CommentsListState();
}

class CommentsListState extends ConsumerState<CommentsList> {
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
    final cached = ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).getCachedComments(
      widget.postId,
    );
    if (cached != null) {
      _items = List.from(cached);
      _loaded = true;
    }
    // RPC hanya bila cache tidak ada / basi (TTL 30 dtk) — buka-tutup-buka
    // sheet tidak menembak server berulang.
    final tp = ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier);
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
      ch.subscribe((status, err) {
        if (err != null) debugPrint('[POST] comments realtime error: $err');
      });
      _channel = ch;
    } catch (_) {}
  }

  Future<void> _load() async {
    final list = await ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).comments(widget.postId);
    if (!mounted) return;
    ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).cacheComments(widget.postId, list);
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
    final res = await ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).toggleCommentLike(id);
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
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final author = c['authorName'] as String? ?? 'Anon';
    final text = (c['text'] as String? ?? '').trim();
    // Komentar = teks komentar + link ChatYuk (bilingual via strings).
    // Sheet yang sama seperti share post: preview penulis + search user +
    // aplikasi. Counter + snackbar hanya bila benar-benar terkirim.
    final content = s.commentShareMsg(author, text);
    final snippet = text.length > 120 ? '${text.substring(0, 120)}…' : text;
    await showPostShareSheet(
      context: context,
      authorUid: '${c['authorId'] ?? ''}',
      authorName: author,
      authorGender: '${c['authorGender'] ?? ''}',
      snippet: snippet,
      shareText: content,
      shareSubject: author,
      // Komentar teks saja — tidak ada file foto.
      buildFiles: () async => const [],
      onShareToUser: (user) => _shareCommentToUser(user, content),
      onExternalShared: () => _bumpCommentShareCount(c, id),
    );
  }

  /// Bagikan komentar ke user ChatYuk lain via chat pribadi.
  Future<bool> _shareCommentToUser(UserModel user, String content) async {
    final ok = await sendShareToUser(context, user, content);
    if (!ok || !mounted) return ok;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.shareSentTo(user.nickname))));
    return true;
  }

  /// Counter share komentar — hanya bila benar-benar terkirim.
  Future<void> _bumpCommentShareCount(Map<String, dynamic> c, int id) async {
    final tp = ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier);
    try {
      final res = await tp.shareComment(id);
      final count = (res['share_count'] as num?)?.toInt();
      if (!mounted) return;
      if (count != null) {
        setState(() => c['shareCount'] = count);
      }
    } catch (_) {}
  }

  /// Hapus komentar sendiri (konfirmasi dulu). Id ≤ 0 = optimistic yang
  /// belum terkonfirmasi server — abaikan (segera terganti data server).
  Future<void> _delete(Map<String, dynamic> c) async {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
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
      await ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).deleteComment(widget.postId, id);
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
    final myUid = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).uid ?? '';
    if (!_loaded && items.isEmpty) return const CommentSkeleton();
    if (items.isEmpty) {
      // Isi penuh area (sheet tinggi TETAP) → empty state center, tidak
      // menyisakan celah / tidak mengubah tinggi sheet.
      return Center(
        child: Text(
          ref.watch(localeProvider).s.commentEmpty,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      );
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
              // Avatar penulis komentar — foto (lazy-load pola sama seperti
              // avatar post) + ring warna gender untuk yang tanpa foto,
              // seperti daftar "Pengguna Online" (male=biru/female=pink).
              CommentAvatar(
                uid: authorId,
                name: name,
                gender: '${c['authorGender'] ?? ''}',
                avatar: '${c['authorAvatar'] ?? ''}',
                size: 38,
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
                        VerifiedBadgeForUid(uid: authorId, size: 13),
                        if (createdAt != null) ...[
                          SizedBox(width: 6),
                          Text(
                            '· ${timeAgoShort(createdAt)}',
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
                        CommentAction(
                          icon: isLiked
                              ? PhosphorIconsFill.heart
                              : PhosphorIconsRegular.heart,
                          color: isLiked
                              ? AppTheme.danger
                              : AppTheme.textSecondary,
                          count: likeCount,
                          onTap: () => _like(c),
                        ),
                        CommentAction(
                          icon: PhosphorIconsRegular.chatCircle,
                          color: AppTheme.textSecondary,
                          count: null,
                          onTap: () => widget.onReply?.call(id, name),
                        ),
                        CommentAction(
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
