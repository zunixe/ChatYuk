import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../widgets/person_avatar.dart';
import '../providers/riverpod/theme_provider.dart';
import 'user_info_screen.dart';
import '../core/perf/perf_probe.dart';
import '../core/nav_guard.dart';
import '../providers/riverpod/social_provider.dart';
import '../widgets/social_counts_line.dart';
import '../core/cache/message_cache.dart';

/// Daftar sosial (followers / following / friends / subscribers).
/// `kind` menentukan tipe; `userId` menentukan user yang diambil (diri sendiri
/// bila null). Default 'followers'.
class SocialListScreen extends ConsumerStatefulWidget {
  final String kind;
  final String? userId;
  final String? title;
  const SocialListScreen({
    super.key,
    required this.kind,
    this.userId,
    this.title,
  });

  @override
  ConsumerState<SocialListScreen> createState() => _SocialListScreenState();
}

class _SocialListScreenState extends ConsumerState<SocialListScreen> {
  SocialNotifier get _service => ProviderScope.containerOf(context, listen: false).read(socialProvider.notifier);
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  static const int _pageSize = 50;
  final ScrollController _scrollCtrl = ScrollController();
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    final uid = widget.userId ?? _service.uid;
    if (uid == null) return;
    setState(() => _loadingMore = true);
    try {
      final rows = await _service.socialList(
        widget.kind,
        uid,
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...rows];
        _hasMore = rows.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _load() async {
    final uid = widget.userId ?? _service.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final cacheKey = 'social_list:${widget.kind}:$uid';
    // PERSISTEN (SQLite): tampilkan daftar dari cache DULU → tanpa "keload
    // dulu". Refresh server menyusul di bawah.
    if (_items.isEmpty) {
      final cached = await MessageCache.instance.loadRawList(cacheKey);
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _items = cached;
          _loading = false;
        });
      }
    }
    final items = await _service.socialList(widget.kind, uid, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _items = items;
      _hasMore = items.length >= _pageSize;
      _loading = false;
    });
    // Simpan ke cache SQLite (persisten lintas cold start).
    if (items.isNotEmpty) {
      unawaited(MessageCache.instance.saveRawList(cacheKey, items));
    }
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('SocialList');
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    final title =
        widget.title ??
        switch (widget.kind) {
          'followers' => s.socialFollowers,
          'following' => s.socialFollowing,
          'friends' => s.socialFriends,
          'subscribers' => s.socialSubscribers,
          _ => '',
        };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _items.isEmpty
          ? Center(
              child: Text(
                s.socialListEmpty,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  MediaQuery.of(context).padding.bottom + 24,
                ),
                itemCount: _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _items.length) {
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
                  return _SocialTile(entry: _items[i]);
                },
              ),
            ),
    );
  }
}

class _SocialTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _SocialTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final name = '${entry['nickname'] ?? 'Anon'}';
    final uid = '${entry['uid'] ?? ''}';
    final registered = entry['is_registered'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: uid.isEmpty
              ? null
              : () {
                  final navKey = navKeyUser(uid);
                  if (!tryClaimNav(navKey)) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => UserInfoScreen(userId: uid, fallbackName: name)),
                  ).then((_) => releaseNav(navKey));
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Avatar seragam seluruh app via PersonAvatar (foto + latar
                // tint & ring warna gender). Gender dari RPC social_list.
                PersonAvatar(
                  key: ValueKey(uid),
                  uid: uid,
                  name: name,
                  gender: '${entry['gender'] ?? ''}',
                  avatarB64: '${entry['avatar'] ?? ''}',
                  size: 40,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: AppText.bodyStrong,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (registered) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              size: 14,
                              color: Color(0xFF4A90E2),
                            ),
                          ],
                        ],
                      ),
                      SocialCountsLine(uid: uid),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
