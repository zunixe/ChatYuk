import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/timeline_provider.dart';
import '../widgets/post_card.dart';
import '../widgets/post/post_prefetch.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/skeleton_card.dart';
import 'post_composer_screen.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/empty_state_view.dart';
import '../core/perf/perf_probe.dart';
import '../config/theme.dart';
import '../config/strings.dart';

// ── Warna header ringkas ala Instagram (DINAMIS mengikuti tema) ──
Color get _kHeaderBg => AppTheme.isDark ? const Color(0xFF0F1115) : Colors.white;
Color get _kHeaderText =>
    AppTheme.isDark ? const Color(0xFFF2F4F7) : const Color(0xFF14171C);
const Color _kAccentBlue = Color(0xFF4FB3F6);
Color get _kMenuBg => AppTheme.isDark ? const Color(0xFF1A1E26) : Colors.white;
Color get _kMenuBorder =>
    AppTheme.isDark ? const Color(0xFF2A2F3A) : const Color(0xFFD5D9E0);
Color get _kMenuText =>
    AppTheme.isDark ? const Color(0xFFD5D9E0) : const Color(0xFF3A3F47);

/// Timeline feed: tab Semua / Mengikuti + infinite scroll + refresh.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen>
    with AutomaticKeepAliveClientMixin {
  // Satu ScrollController PER scope (Semua/Mengikuti/Postinganku) — posisi
  // scroll tiap scope terjaga saat user ganti scope dari menu header.
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
    for (final c in _scrolls) {
      c.addListener(_onScroll);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(refresh: true));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollDebounce?.cancel();
    for (final c in _scrolls) {
      c.removeListener(_onScroll);
      c.dispose();
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Hanya halaman scope yang SEDANG aktif yang boleh memicu load-more
    // (controller scope lain bisa ikut memanggil saat dibangun di TabBarView).
    if (!_scroll.hasClients) return;
    if (!_scroll.position.hasContentDimensions) return;
    // PREFETCH ala Instagram/chat: hangatkan thumb post di DEPAN viewport
    // begitu user bergerak — saat kartu masuk, gambarnya sudah di cache.
    // Dedupe di dalam PostPrefetch → aman dipanggil tiap event scroll murah.
    _warmAhead();
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

  /// Hangatkan thumb post di sekitar viewport saat scroll (ala Instagram).
  /// Pakai posisi scroll kasar → ambil window post di depannya. Murah &
  /// dedupe di PostPrefetch (no-op bila sudah di cache/inflight).
  void _warmAhead() {
    try {
      final tp = ref.read(timelineProvider.notifier);
      final all = tp.posts;
      if (all.isEmpty) return;
      // Perkiraan kartu ~ tile tinggi rata-rata; ambil window longgar.
      const estTile = 480.0;
      final first = (_scroll.position.pixels / estTile).floor().clamp(0, all.length - 1);
      final last = (first + PostPrefetch.maxPosts).clamp(0, all.length);
      PostPrefetch.warmPosts(all.sublist(first, last));
    } catch (_) {}
  }
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
      // Header ringkas ala Instagram: 52px, gelap muda, garis bawah tipis,
      // tanpa elevation. Pakai AppBar (bukan PreferredSize + SafeArea manual)
      // supaya status bar tidak menutup judul.
      appBar: AppBar(
        backgroundColor: _kHeaderBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        centerTitle: false,
        titleSpacing: _isSearching ? 0 : 12,
        automaticallyImplyLeading: false,
        leading: _isSearching
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: _kHeaderText),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchCtrl.clear();
                    _search = '';
                    _appliedSearch = '';
                  });
                },
              )
            : null,
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
              ? KeyedSubtree(
                  key: const ValueKey('search'),
                  child: _buildSearchField(s),
                )
              : KeyedSubtree(
                  key: const ValueKey('title'),
                  child: _buildTitleMenu(s),
                ),
        ),
        iconTheme: IconThemeData(color: _kHeaderText),
        actions: _isSearching
            ? null
            : [
                // Rapat ala halaman Online: Tooltip + GestureDetector +
                // Padding(horizontal: 3) + Icon (tanpa IconButton yang
                // memaksa 48px & bikin jarak antar-ikon jauh). Padding kanan
                // 8 → jarak ke tepi layar sama dengan Online.
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: s.searchHint,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _isSearching = true),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: s.postAddTooltip,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _openComposer,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(Icons.add_circle_outline),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
        shape: const Border(
          // Tanpa garis bawah: PostCard pertama sudah punya Divider di
          // atasnya — kalau ditambah di sini jadi garis dobel.
        ),
      ),
      // SWIPE kiri/kanan untuk pindah scope (Semua ⇄ Mengikuti ⇄
      // Postinganku). GestureDetector horizontal TIDAK mengganggu scroll
      // vertikal feed (arah berbeda) maupun swipe-to-reply/gesture kartu.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 260) return; // abaikan geseran kecil/ragu
          if (v < 0) {
            // geser ke KIRI → scope berikutnya
            if (_current < 2) _selectScope(_current + 1);
          } else {
            // geser ke KANAN → scope sebelumnya
            if (_current > 0) _selectScope(_current - 1);
          }
        },
        child: _buildFeed(_current),
      ),
    );
  }

  /// Judul header + menu scope feed (Semua / Mengikuti / Postinganku).
  Widget _buildTitleMenu(S s) {
    final title = switch (_current) {
      1 => s.tabFollowing,
      2 => s.tabMine,
      _ => 'Timeline',
    };
    return PopupMenuButton<int>(
      tooltip: '',
      onSelected: _selectScope,
      color: _kMenuBg,
      elevation: 8,
      offset: const Offset(0, 44),
      constraints: const BoxConstraints(minWidth: 230),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _kMenuBorder),
      ),
      itemBuilder: (_) => [
        _scopeMenuItem(0, s.tabAll),
        _scopeMenuItem(1, s.tabFollowing),
        _scopeMenuItem(2, s.tabMine),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: _kHeaderText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Icon(
            Icons.keyboard_arrow_down,
            color: _kHeaderText,
          ),
        ],
      ),
    );
  }

  PopupMenuItem<int> _scopeMenuItem(int index, String label) {
    final active = _current == index;
    return PopupMenuItem<int>(
      value: index,
      height: 46,
      child: Row(
        children: [
          if (active)
            const Icon(Icons.check, color: _kAccentBlue, size: 20)
          else
            const SizedBox(width: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? _kHeaderText : _kMenuText,
            ),
          ),
        ],
      ),
    );
  }

  /// Field pencarian dalam header (jadi title AppBar saat mode cari) —
  /// ukuran, border biru & bentuk SAMA dengan menu Online.
  Widget _buildSearchField(S s) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: SizedBox(
        height: 40,
        width: double.infinity,
        child: TextField(
          controller: _searchCtrl,
          autofocus: true,
          onChanged: (v) {
            _search = v;
            // Debounce 250ms — filter berat hanya jalan setelah user
            // berhenti mengetik, bukan tiap keystroke.
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) setState(() => _appliedSearch = _search);
            });
            setState(() {});
          },
          style: AppText.body.copyWith(color: _kHeaderText),
          decoration: InputDecoration(
            isDense: true,
            hintText: s.searchHint,
            hintStyle: AppText.body.copyWith(color: Colors.white54),
            prefixIcon: const Icon(
              Icons.search,
              color: Colors.white70,
              size: 20,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 0,
            ),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      size: 18,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.10),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
            border: _tlSearchBorder(_kAccentBlue),
            enabledBorder: _tlSearchBorder(Colors.white24),
            focusedBorder: _tlSearchBorder(_kAccentBlue, width: 1.5),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _tlSearchBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  /// Buka composer postingan (anon → popup lengkapi email).
  void _openComposer() {
    final auth = ProviderScope.containerOf(context, listen: false)
        .read(authProvider.notifier);
    if (!(auth.profile?.isRegistered ?? false)) {
      showAnonPromptDialog(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PostComposerScreen()),
    );
  }

  /// Ganti scope feed (0=Semua, 1=Mengikuti, 2=Postinganku) dari menu header.
  /// Menggantikan TabBar: set _current, reset scroll/search, lalu muat ulang
  /// feed dengan logika filter scope yang SUDAH ada.
  void _selectScope(int index) {
    if (index == _current) return;
    setState(() => _current = index);
    // Reset search — filter basi dari scope lama tidak boleh terbawa.
    _searchCtrl.clear();
    _searchDebounce?.cancel();
    if (_search.isNotEmpty || _appliedSearch.isNotEmpty) {
      setState(() {
        _search = '';
        _appliedSearch = '';
      });
    }
    // Tampilkan cache instan; RPC hanya bila cache basi (logika lama).
    _load(refresh: true, skipIfFresh: true);
  }

  /// Body feed untuk scope aktif (`_current`). Feed tunggal — scope diganti
  /// dari menu header (dulu TabBarView 3 halaman).
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
    // Feed tunggal: halaman yang dibangun SELALU scope aktif.
    final List<Map<String, dynamic>> posts = _computeFiltered(postsRaw);
    // PREFETCH (contek perilaku chat foto: begitu chat terbuka, thumb sudah
    // di-cache → tampil instan). Di sini: begitu daftar post tiba, hangatkan
    // thumb N post teratas di LATAR supaya kartu berikutnya langsung gambar,
    // bukan "item dulu baru gambar". Fire-and-forget, bounded, dedupe.
    if (posts.isNotEmpty) {
      PostPrefetch.warmPosts(posts);
    }
    final effectiveSearch = _appliedSearch;
    final effectiveLoading = loading;
    final ctrl = _scrolls[scopeIndex];

    return RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              // Empty state HANYA saat fetch selesai & benar-benar kosong. Saat
              // loading pertama kali tampilkan skeleton — jangan blink ke
              // "Belum ada postingan" kalau sebenarnya ada data.
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
                      : posts.isEmpty && !effectiveLoading && fetchFailed
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
            : posts.isEmpty && !effectiveLoading
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
            : posts.isEmpty && effectiveLoading
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
                      (effectiveLoading && hasMore ? 1 : 0) +
                      (!hasMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= posts.length && effectiveLoading && hasMore) {
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
                  // PREFETCH AKTIF (index-based): saat kartu ke-i DIBANGUN,
                  // hangatkan thumb beberapa post DI DEPANNYA. Berbeda dari
                  // prefetch berbasis posisi-scroll (yang kalah saat scroll
                  // cepat karena posisi melompat): ini mengekor index yang
                  // benar-benar dibangun → selalu unggul dari jari, sehingga
                  // scroll cepat pun fotonya sudah siap. Dedupe di PostPrefetch
                  // membuat ini murah (no-op bila sudah di cache).
                  PostPrefetch.warmAheadFrom(posts, i);
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

