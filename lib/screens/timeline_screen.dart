import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/timeline_provider.dart';
import '../widgets/post_card.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/skeleton_card.dart';
import 'post_composer_screen.dart';
import '../providers/theme_provider.dart';

/// Timeline feed: tab Semua / Mengikuti + infinite scroll + refresh.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  final ScrollController _scroll = ScrollController();
  int _current = 0;
  // Posisi scroll per tab — dipulihkan saat balik ke tab tsb.
  final Map<int, double> _scrollOffsets = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(refresh: true));
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    if (_tab.index != _current) {
      // Simpan posisi scroll scope lama supaya balik ke tab ini tetap
      // di posisi yang sama (klik terasa instan, tidak lompat ke atas).
      if (_scroll.hasClients) _scrollOffsets[_current] = _scroll.offset;
      _current = _tab.index;
      _load(refresh: true);
      // Pulihkan posisi scroll scope baru setelah frame ter-render.
      final target = _scrollOffsets[_current];
      if (target != null && target > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          final max = _scroll.position.maxScrollExtent;
          _scroll.jumpTo(target.clamp(0.0, max));
        });
      }
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      final tp = context.read<TimelineProvider>();
      if (!tp.loading && tp.hasMore) _load(refresh: false);
    }
  }

  String get _scope =>
      _current == 0 ? 'all' : (_current == 1 ? 'following' : 'mine');

  Future<void> _load({bool refresh = false}) async {
    final auth = context.read<AuthProvider>();
    if (auth.uid == null) return;
    await context.read<TimelineProvider>().load(_scope, refresh: refresh);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    super.build(context);
    final s = context.watch<LocaleProvider>().s;
    // Rebuild granular: hanya rebuild saat daftar post / hasMore benar-benar
    // berubah (bukan tiap notifyListeners — mis. pricing, loading).
    final postsRaw = context.select<TimelineProvider, List<Map<String, dynamic>>>(
      (t) => t.posts,
    );
    final hasMore = context.select<TimelineProvider, bool>((t) => t.hasMore);
    final loading = context.select<TimelineProvider, bool>((t) => t.loading);
    final scope = _scope;
    final posts = _search.isEmpty
        ? postsRaw
        : postsRaw.where((p) {
            final q = _search.toLowerCase();
            final text = (p['text'] as String? ?? '').toLowerCase();
            final name = (p['authorName'] as String? ?? '').toLowerCase();
            return text.contains(q) || name.contains(q);
          }).toList();

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
                    onChanged: (v) => setState(() => _search = v),
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
      body: RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              // Empty state HANYA saat fetch selesai & benar-benar kosong. Saat
              // loading pertama kali (atau tab switch) tampilkan spinner — jangan
              // blink ke "Belum ada postingan" kalau sebenarnya ada data.
              child: posts.isEmpty && !loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 400,
                    child: _EmptyState(
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
                        final auth = context.read<AuthProvider>();
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
            ? // Skeleton saat load pertama — konsisten dengan tab lain.
              const SkeletonList(
                count: 5,
                padding: EdgeInsets.only(top: 4, bottom: 88),
              )
            : ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 4, bottom: 88),
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
                  return PostCard(
                    key: ValueKey('${posts[i]['id']}'),
                    post: posts[i],
                  );
                },
              ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyState({
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lingkaran + ikon — komposisi sama dengan halaman Online.
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(
                  Icons.dynamic_feed_rounded,
                  size: 48,
                  color: AppTheme.primary,
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(title, style: AppText.bodyStrong, textAlign: TextAlign.center),
            SizedBox(height: 6),
            Text(
              hint,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            if (actionLabel != null)
              FilledButton(onPressed: onAction, child: Text(actionLabel!))
            else
              // Petunjuk tombol +
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.emptyTimelineCta,
                      style: AppText.caption.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
