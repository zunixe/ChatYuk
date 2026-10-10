import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../providers/riverpod/avatar_provider.dart';
import '../core/media/native_image.dart';
import '../widgets/user_avatar.dart'
    show cachedUserAvatarBytes, rememberAvatarBytes;
import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../core/cache/message_cache.dart';

// Top-level untuk compute() — decode avatar base64 di background isolate
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  PointsNotifier get _service => ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
  late final TabController _tab = TabController(length: 2, vsync: this);
  String _scope = 'weekly';
  bool _loading = true;
  List<dynamic> _entries = [];
  Map<String, dynamic>? _me;
  // Paginasi + cache disk.
  static const int _pageSize = 50;
  final ScrollController _scrollCtrl = ScrollController();
  bool _hasMore = true;
  bool _loadingMore = false;

  String get _cacheKey => 'leaderboard_$_scope';

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _tab.addListener(() {
      if (_tab.indexIsChanging) return;
      final scope = _tab.index == 0 ? 'weekly' : 'alltime';
      if (scope != _scope) {
        _scope = scope;
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Cache disk dulu (instan, tahan offline) sebelum server.
    try {
      final cached = await MessageCache.instance.loadRawList(_cacheKey);
      if (cached.isNotEmpty && _entries.isEmpty && mounted) {
        setState(() => _entries = cached);
      }
    } catch (_) {}
    try {
      final res = await _service.leaderboard(_scope, limit: _pageSize, offset: 0);
      if (!mounted) return;
      final entries = (res['entries'] as List?) ?? [];
      _hasMore = entries.length >= _pageSize;
      setState(() {
        _entries = entries;
        _me = res['me'] is Map ? Map<String, dynamic>.from(res['me']) : null;
        _loading = false;
      });
      if (entries.isNotEmpty) {
        MessageCache.instance.saveRawList(
          _cacheKey,
          entries.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
      }
      unawaited(
        ProviderScope.containerOf(context, listen: false).read(avatarProvider).prefetch(
          entries
              .map((e) => '${(e)['uid'] ?? ''}')
              .where((u) => u.isNotEmpty)
              .toList(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_entries.isEmpty) {
          _entries = [];
          _me = null;
        }
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final res = await _service.leaderboard(
        _scope,
        limit: _pageSize,
        offset: _entries.length,
      );
      if (!mounted) return;
      final more = (res['entries'] as List?) ?? [];
      setState(() {
        _entries = [..._entries, ...more];
        _hasMore = more.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.lbTitle),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: s.lbWeekly),
            Tab(text: s.lbAllTime),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                SizedBox(width: 6),
                Text(
                  _scope == 'weekly' ? s.lbWeeklyHint : s.lbAllTimeHint,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _entries.isEmpty
                ? Center(
                    child: Text(
                      s.lbEmpty,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: _entries.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, otherIndex) =>
                          const Divider(height: 1, indent: 64),
                      itemBuilder: (_, i) {
                        if (i >= _entries.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        return _RankTile(
                          entry: Map<String, dynamic>.from(_entries[i] as Map),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _me == null
          ? null
          : _MyRankBar(
              rank: (_me!['rank'] as num?)?.toInt(),
              score: (_me!['score'] as num?)?.toInt() ?? 0,
            ),
    );
  }
}

class _RankTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _RankTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final rank = (entry['rank'] as num?)?.toInt() ?? 0;
    final nickname = entry['nickname']?.toString() ?? '—';
    final avatar = entry['avatar']?.toString() ?? '';
    final score = (entry['score'] as num?)?.toInt() ?? 0;
    final registered = entry['is_registered'] == true;
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 28, child: _RankBadge(rank: rank)),
          const SizedBox(width: 4),
          _Avatar(
            base64: avatar,
            nickname: nickname,
            uid: '${entry['uid'] ?? ''}',
          ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (registered) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, size: 14, color: AppTheme.primary),
          ],
        ],
      ),
      trailing: Text(
        '$score',
        style: AppText.bodyStrong.copyWith(
          color: AppTheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    if (rank == 1)
      return const Text(
        '🥇',
        style: TextStyle(fontSize: AppGlyph.sm),
        textAlign: TextAlign.center,
      );
    if (rank == 2)
      return const Text(
        '🥈',
        style: TextStyle(fontSize: AppGlyph.sm),
        textAlign: TextAlign.center,
      );
    if (rank == 3)
      return const Text(
        '🥉',
        style: TextStyle(fontSize: AppGlyph.sm),
        textAlign: TextAlign.center,
      );
    return Text(
      '$rank',
      textAlign: TextAlign.center,
      style: AppText.bodySmall.copyWith(
        color: AppTheme.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _Avatar extends StatefulWidget {
  final String base64;
  final String nickname;
  final String uid;
  const _Avatar({required this.base64, required this.nickname, this.uid = ''});

  // Bytes memakai cache BERSAMA UserAvatar (per-uid) — bukan map statis
  // sendiri (retensi ganda). Lihat user_avatar.dart.
  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  Uint8List? _bytes;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_Avatar old) {
    super.didUpdateWidget(old);
    if (old.base64 != widget.base64) {
      _bytes = null;
      _started = false;
      _decode();
    }
  }

  Future<void> _decode() async {
    final b64 = widget.base64;
    if (b64.isEmpty || _started) return;
    _started = true;
    final cached = cachedUserAvatarBytes(widget.uid);
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    final b = await NativeImage.decodeAvatar(b64, maxPx: 256);
    if (b == null) return;
    rememberAvatarBytes(widget.uid, b);
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.nickname.isNotEmpty ? widget.nickname[0].toUpperCase() : '?';
    if (widget.base64.isEmpty || _bytes == null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: AppTheme.avatarBg,
        child: Text(
          initial,
          style: const TextStyle(
            color: AppTheme.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 18,
      // Avatar mungil (radius 18) — cap decode (x2 density x2) agar
      // tidak raster gambar penuh.
      backgroundImage: ResizeImage(MemoryImage(_bytes!), width: 72),
    );
  }
}

class _MyRankBar extends ConsumerWidget {
  final int? rank;
  final int score;
  const _MyRankBar({required this.rank, required this.score});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle_outlined, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rank == null ? s.lbUnranked : '${s.lbYourRank}: #$rank',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$score',
            style: AppText.titleEmphasis.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
