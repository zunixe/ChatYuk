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

// ── Warna header ringkas ala Instagram (spesifik, tak ikut tema) ──
const Color _kHeaderBg = Color(0xFF0F1115);
const Color _kHeaderText = Color(0xFFF2F4F7);
const Color _kAccentBlue = Color(0xFF4FB3F6);
const Color _kMenuBg = Color(0xFF1A1E26);
const Color _kMenuBorder = Color(0xFF2A2F3A);
const Color _kMenuText = Color(0xFFD5D9E0);

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
                icon: const Icon(Icons.arrow_back, color: _kHeaderText),
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
        title: _isSearching ? _buildSearchField(s) : _buildTitleMenu(s),
        iconTheme: const IconThemeData(color: _kHeaderText),
        actions: _isSearching
            ? null
            : [
                // Padding kanan 8 — samakan dengan menu Online (jarak ikon
                // ke tepi layar konsisten antar halaman).
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: s.postAddTooltip,
                        icon: const Icon(Icons.add_box_outlined),
                        onPressed: _openComposer,
                      ),
                      IconButton(
                        tooltip: s.searchHint,
                        icon: const Icon(Icons.search_rounded),
                        onPressed: () =>
                            setState(() => _isSearching = true),
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
      body: _buildFeed(_current),
    );
  }

  /// Judul header + menu scope feed (Semua / Mengikuti / Postinganku).
  Widget _buildTitleMenu(S s) {
    final title = switch (_current) {
      1 => s.tabFollowing,
      2 => s.tabMine,
      _ => 'ChatYuk',
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
        side: const BorderSide(color: _kMenuBorder),
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
            style: AppText.title.copyWith(color: _kHeaderText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Icon(
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

  /// Field pencarian dalam header (jadi title AppBar saat mode cari).
  Widget _buildSearchField(S s) {
    // Padding kanan supaya field tidak menempel ke tepi layar
    // (titleSpacing saat searching = 0, ikon clear paling kanan).
    return Padding(
      padding: const EdgeInsets.only(right: 14),
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
        style: const TextStyle(color: _kHeaderText, fontSize: 15),
        decoration: InputDecoration(
          isDense: true,
          hintText: s.searchHint,
          hintStyle: const TextStyle(color: Colors.white54, fontSize: 15),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon:
                      const Icon(Icons.clear, size: 18, color: Colors.white70),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.10),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kMenuBorder)),
        ),
      ),
    );
  }

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

