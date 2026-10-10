import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/admin_gate.dart';
import '../providers/riverpod/points_provider.dart';
import '../config/theme.dart';
import 'point_history/widgets/history_tile.dart';
import 'point_history/widgets/yukcoin_header.dart';
import 'point_history/widgets/yukcoin_how_to.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import '../utils.dart';
import '../config/app_flavor.dart';
import '../core/cache/message_cache.dart';

/// Halaman pusat YukCoin: saldo, cara dapat, cara pakai, dan riwayat.
/// Dulu hanya "History Poin" — sekarang diperluas jadi hub YukCoin.
class PointHistoryScreen extends ConsumerStatefulWidget {
  const PointHistoryScreen({super.key});

  @override
  ConsumerState<PointHistoryScreen> createState() => _PointHistoryScreenState();
}

class _PointHistoryScreenState extends ConsumerState<PointHistoryScreen> {
  PointsNotifier get _service => ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  // Paginasi + cache disk.
  static const int _pageSize = 50;
  static const String _cacheKey = 'point_history';
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

  Future<void> _load() async {
    // Cache disk dulu (instan, tahan offline).
    try {
      final cached = await MessageCache.instance.loadRawList(_cacheKey);
      if (cached.isNotEmpty && _items.isEmpty && mounted) {
        setState(() => _items = cached);
      }
    } catch (_) {}
    try {
      // Segarkan status YukCoin v2 + feature flags supaya visibilitas tombol
      // topup (yang ikut dikontrol toggle v2 / publish admin) selalu akurat.
      final points = _service;
      unawaited(points.refreshYukcoinV2());
      unawaited(points.refreshMeteredPricing());
      final rows = await points.pointHistory(limit: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _hasMore = rows.length >= _pageSize;
        _loading = false;
      });
      if (rows.isNotEmpty) {
        MessageCache.instance.saveRawList(_cacheKey, rows);
      }
    } catch (e) {
      dlog('[PointHistory] load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final rows = await _service.pointHistory(
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

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    // PERF: `watch` penuh → seluruh riwayat rebuild tiap PointsProvider
    // notify (refresh berkala). `select` snapshot nilai yang dirender;
    // aksi dipanggil via `read`.
    final pointsSnap = ref.watch(
      pointsProvider.select(
        (p) => (
          total: p.points,
          topup: p.topupPathOpen,
          v2: p.yukcoinV2Active,
          ghost: p.ghostMode,
        ),
      ),
    );
    final points = ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(s.yukcoinTitle)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: () async {
                await points.refreshWallet();
                await _load();
              },
              child: CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  // Header saldo YukCoin + tombol top-up (Play / build admin).
                  SliverToBoxAdapter(
                    child: YukcoinHeader(
                      s: s,
                      total: pointsSnap.total,
                      showTopup:
                          AppFlavor.topupEnabled ||
                          AdminGate.enabled ||
                          pointsSnap.topup,
                    ),
                  ),
                  // Cara dapat & cara pakai.
                  SliverToBoxAdapter(
                    child: YukcoinHowTo(
                      s: s,
                      v2Active: pointsSnap.v2,
                      ghostActive: pointsSnap.ghost,
                    ),
                  ),
                  // Riwayat.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Text(
                        s.pointHistoryTitle,
                        style: AppText.label.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (_items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 60),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 48,
                                color: AppTheme.textSecondary,
                              ),
                              SizedBox(height: 12),
                              Text(
                                s.pointHistoryEmpty,
                                style: AppText.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, i) =>
                          const Divider(height: 1, indent: 64),
                      itemBuilder: (_, i) => HistoryTile(entry: _items[i], s: s),
                    ),
                  if (_hasMore && _items.isNotEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 40,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
