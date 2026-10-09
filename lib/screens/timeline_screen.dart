import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/timeline_provider.dart';
import '../widgets/post_card.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/skeleton_card.dart';
import 'post_composer_screen.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/empty_state_view.dart';
import '../core/perf/perf_probe.dart';
import '../config/theme.dart';

/// Timeline feed: tab Semua / Mengikuti + infinite scroll + refresh.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  // Satu ScrollController PER scope (Semua/Mengikuti/Postinganku) — dibutuhkan
  // karena body kini TabBarView: tiap halaman punya scroll terpisah sehingga
  // swipe antar-tab tidak mengganggu posisi scroll scope lain.
  final List<ScrollController> _scrolls =
      List.generate(3, (_) => ScrollController());
  ScrollController get _scroll => _scrolls[_current];
  int _current = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  // Hasil debounce _search — filter list pakai ini, bukan _search mentah.
  String _appliedSearch = '';
  Timer? _searchDebounce;
  Timer? _scrollDebounce;
  bool _isSearching = false;

  // Hasil filter di-cache: recompute HANYA saat posts / appliedSearch
  // berubah — bukan tiap build (dulu `.where()` jalan tiap frame).
  List<Map<String, dynamic>> _filteredCache = const [];
  List<Map<String, dynamic>>? _lastPostsRaw;
  String _lastSearch = '\u0000';

  List<Map<String, dynamic>> _computeFiltered(
    List<Map<String, dynamic>> postsRaw,
  ) {
    if (identical(postsRaw, _lastPostsRaw) && _appliedSearch == _lastSearch) {
      return _filteredCache;
    }
    _lastPostsRaw = postsRaw;
    _lastSearch = _appliedSearch;
    if (_appliedSearch.isEmpty) {
      _filteredCache = postsRaw;
    } else {
      final q = _appliedSearch.toLowerCase();
      _filteredCache = postsRaw.where((p) {
        final text = (p['text'] as String? ?? '').toLowerCase();
        final name = (p['authorName'] as String? ?? '').toLowerCase();
        return text.contains(q) || name.contains(q);
      }).toList();
    }
    return _filteredCache;
  }

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
    for (final c in _scrolls) {
      c.addListener(_onScroll);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(refresh: true));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollDebounce?.cancel();
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    for (final c in _scrolls) {
      c.removeListener(_onScroll);
      c.dispose();
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    if (_tab.index != _current) {
      // Tiap scope punya ScrollController sendiri → posisi scroll sudah
      // otomatis terjaga, tak perlu simpan/pulihkan manual.
      setState(() => _current = _tab.index);
      // Reset search saat ganti tab — filter basi dari tab lama tidak
      // boleh membawa hasil ke scope baru.
      _searchCtrl.clear();
      _searchDebounce?.cancel();
      if (_search.isNotEmpty || _appliedSearch.isNotEmpty) {
        setState(() {
          _search = '';
          _appliedSearch = '';
        });
      }
      // Ganti tab: tampilkan cache instan; RPC hanya bila cache basi.
      _load(refresh: true, skipIfFresh: true);
    }
  }

  void _onScroll() {
    // Hanya halaman scope yang SEDANG aktif yang boleh memicu load-more
    // (controller scope lain bisa ikut memanggil saat dibangun di TabBarView).
    if (!_scroll.hasClients) return;
    if (!_scroll.position.hasContentDimensions) return;
    if (_scroll.position.pixels <
        _scroll.position.maxScrollExtent - 200) {
      return;
    }
    // Debounce 300ms: scroll listener menyala tiap piksel — jangan memicu
    // _load berulang (dan _fetchScope dedupe) saat user menahan di ujung feed.
    if (_scrollDebounce?.isActive ?? false) return;
    _scrollDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final tp = ref.read(timelineProvider.notifier);
      if (!tp.loading && tp.hasMore) _load(refresh: false);
    });
  }

  String get _scope =>
      _current == 0 ? 'all' : (_current == 1 ? 'following' : 'mine');

  Future<void> _load({bool refresh = false, bool skipIfFresh = false}) async {
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    if (auth.uid == null) return;
    // Gerbang Timeline absolut: anon (belum registrasi) TIDAK bisa lihat feed.
    // Jangan tembak RPC `list_posts` (pasti raise ANON_DISABLED → layar error
    // retry palsu). UI menampilkan state "daftar dulu" (lihat build()).
    if (auth.anonTimelineBlocked) return;
    await ref
        .read(timelineProvider.notifier)
        .load(_scope, refresh: refresh, skipIfFresh: skipIfFresh);
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Timeline');
    ref.watch(themeProvider);
    super.build(context);
    final s = ref.watch(localeProvider).s;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        leading: IconButton(
          tooltip: s.searchHint,
          icon: Icon(_isSearching ? Icons.close : Icons.search_rounded),
          color: Colors.white,
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchCtrl.clear();
                _search = '';
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
                    onChanged: (v) {
                      _search = v;
                      // Debounce 250ms — filter berat hanya jalan setelah
                      // user berhenti mengetik, bukan tiap keystroke.
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 250),
                        () {
                          if (mounted) {
                            setState(() => _appliedSearch = _search);
                          }
                        },
                      );
                      setState(() {});
                    },
                    style: AppText.body.copyWith(color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: s.searchHint,
                      hintStyle: AppText.body.copyWith(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: Colors.white70),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.15),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white, width: 1)),
                    ),
                  ),
                )
              : Column(
                  key: const ValueKey('title'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ChatYuk', style: AppText.title.copyWith(color: Colors.white)),
                    Text(s.titleTimeline, style: AppText.bodySmall.copyWith(color: Colors.white70)),
                  ],
                ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        // Tombol + kanan-atas (seperti Online): ke halaman Post.
        // Anon: popup lengkapi email (pola sama dengan CTA empty-state).
        actions: [
          IconButton(
            tooltip: s.postAddTooltip,
            icon: const Icon(Icons.add_circle_outline),
            color: Colors.white,
            onPressed: () {
              final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
              if (!(auth.profile?.isRegistered ?? false)) {
                showAnonPromptDialog(context);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PostComposerScreen(),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: s.tabAll),
            Tab(text: s.tabFollowing),
            Tab(text: s.tabMine),
          ],
        ),
      ),
      // Swipe antar-tab (Semua/Mengikuti/Postinganku) seperti halaman Grup.
      // Tiap halaman punya ScrollController sendiri (lihat _scrolls).
      body: TabBarView(
        controller: _tab,
        children: [
          _buildFeed(0),
          _buildFeed(1),
          _buildFeed(2),
        ],
      ),
    );
  }

  /// Body feed untuk satu scope (index tab). Dipakai ketiga halaman TabBarView.
  Widget _buildFeed(int scopeIndex) {
    final s = ref.watch(localeProvider).s;
    final postsRaw = ref.watch(timelineProvider.select((t) => t.posts));
    final hasMore = ref.watch(timelineProvider.select((t) => t.hasMore));
    final loading = ref.watch(timelineProvider.select((t) => t.loading));
    final fetchFailed =
        ref.watch(timelineProvider.select((t) => t.fetchFailed));
    final anonBlocked =
        ref.watch(authProvider.select((a) => a.anonTimelineBlocked));
    final scope =
        scopeIndex == 0 ? 'all' : (scopeIndex == 1 ? 'following' : 'mine');
    // Hanya scope AKTIF yang menampilkan data provider (data provider = scope
    // aktif). Scope lain tampil skeleton/kosong sampai jadi aktif — mencegah
    // menampilkan feed scope lain di halaman yang salah.
    final isActive = scopeIndex == _current;
    final posts = isActive ? _computeFiltered(postsRaw) : const [];
    final effectiveSearch = isActive ? _appliedSearch : '';
    final ctrl = _scrolls[scopeIndex];

    return RefreshIndicator(
              onRefresh: () async {
                if (scopeIndex != _current) {
                  // Swipe ke scope lain dulu baru refresh scope itu.
                  _tab.animateTo(scopeIndex);
                }
                await _load(refresh: true);
              },
              // Empty state HANYA saat fetch selesai & benar-benar kosong. Saat
              // loading pertama kali (atau tab switch) tampilkan spinner — jangan
              // blink ke "Belum ada postingan" kalau sebenarnya ada data.
              child: anonBlocked
                      // Gerbang Timeline absolut: anon tidak bisa lihat feed.
                      // Tampilkan ajakan daftar (bukan error retry dari RPC
                      // yang memang selalu ditolak server).
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 400,
                              child: EmptyStateView(
                                icon: Icons.dynamic_feed_rounded,
                                title: s.promptCompleteEmailTimelineTitle,
                                hint: s.promptCompleteEmailTimelineMsg,
                                actionLabel: s.btnGoProfile,
                                onAction: () => showAnonPromptDialog(
                                  context,
                                  title: s.promptCompleteEmailTimelineTitle,
                                  message: s.promptCompleteEmailTimelineMsg,
                                  icon: Icons.dynamic_feed_rounded,
                                ),
                              ),
                            ),
                          ],
                        )
                      : posts.isEmpty && !loading && fetchFailed
            // Fetch gagal (network/RPC) — BUKAN feed kosong. Tampilkan
            // pesan error + tombol coba lagi, jangan empty state palsu.
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 400,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 40,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          s.msgServerError,
                          style: AppText.bodyStrong.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _load(refresh: true),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(s.btnRetry),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : posts.isEmpty && !loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 400,
                    // Search aktif + hasil filter kosong → bukan feed
                    // kosong; jangan tampilkan CTA "Ketuk +" palsu.
                    child: effectiveSearch.isNotEmpty
                        ? Center(
                            child: Text(
                              s.searchNoResult,
                              style: AppText.bodyStrong.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          )
                        : EmptyStateView(
                            icon: Icons.dynamic_feed_rounded,
                            title: scope == 'all'
                                ? s.emptyTimeline
                                : scope == 'following'
                                ? s.emptyFollowing
                                : s.emptyMine,
                            hint: scope == 'all'
                                ? s.emptyTimelineHint
                                : scope == 'following'
                                ? s.emptyFollowingHint
                                : s.emptyMineHint,
                            // Semua tab: "Ketuk +" bisa diklik — seragam, anon popup, registered ke composer
                            actionLabel: s.emptyTimelineCta,
                            onAction: () {
                              final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
                              if (!(auth.profile?.isRegistered ?? false)) {
                                showAnonPromptDialog(context);
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PostComposerScreen(),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              )
            : posts.isEmpty && loading
            // Skeleton bentuk post — terasa instan & konsisten
            // dengan layar online (user lebih suka skeleton daripada
            // spinner/muter-muter).
            ? const PostSkeletonList(count: 3)
            : ListView.builder(
                controller: ctrl,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 4, bottom: 88),
                // PERF: cache kecil (dulu default 250px). Kartu di luar
                // viewport lebih sedikit yang ter-build → tidak lagi mengunduh
                // + decode foto post yang belum terlihat saat Timeline dibuka.
                // Kombinasi dgn _loadImages post-frame di PostCard.
                scrollCacheExtent: ScrollCacheExtent.pixels(100),
                itemCount: posts.length +
                      (loading && hasMore ? 1 : 0) +
                      (!hasMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= posts.length && loading && hasMore) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (i >= posts.length) {
                    return Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          s.noMorePosts,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }
                  // RepaintBoundary: kartu post lain tidak ikut repaint
                  // saat satu kartu berubah (like/komentar/avatar).
                  return RepaintBoundary(
                    child: PostCard(
                      key: ValueKey('${posts[i]['id']}'),
                      post: posts[i],
                    ),
                  );
                 },
               ),
      );
  }

  @override
  bool get wantKeepAlive => true;
}

