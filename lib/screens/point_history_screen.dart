import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_flavor.dart';
import '../core/admin_gate.dart';
import '../providers/points_provider.dart';
import '../config/theme.dart';
import 'point_history/widgets/history_tile.dart';
import 'point_history/widgets/yukcoin_header.dart';
import 'point_history/widgets/yukcoin_how_to.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../utils.dart';

/// Halaman pusat YukCoin: saldo, cara dapat, cara pakai, dan riwayat.
/// Dulu hanya "History Poin" — sekarang diperluas jadi hub YukCoin.
class PointHistoryScreen extends StatefulWidget {
  const PointHistoryScreen({super.key});

  @override
  State<PointHistoryScreen> createState() => _PointHistoryScreenState();
}

class _PointHistoryScreenState extends State<PointHistoryScreen> {
  PointsProvider get _service => context.read<PointsProvider>();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Segarkan status YukCoin v2 + feature flags supaya visibilitas tombol
      // topup (yang ikut dikontrol toggle v2 / publish admin) selalu akurat.
      final points = _service;
      unawaited(points.refreshYukcoinV2());
      unawaited(points.refreshMeteredPricing());
      final rows = await points.pointHistory(limit: 200);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      dlog('[PointHistory] load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final points = context.watch<PointsProvider>();
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
                slivers: [
                  // Header saldo YukCoin + tombol top-up (Play / build admin).
                  SliverToBoxAdapter(
                    child: YukcoinHeader(
                      s: s,
                      total: points.points,
                      showTopup: AppFlavor.topupEnabled ||
                          AdminGate.enabled ||
                          points.topupPathOpen,
                    ),
                  ),
                  // Cara dapat & cara pakai.
                  SliverToBoxAdapter(
                    child: YukcoinHowTo(
                      s: s,
                      v2Active: points.yukcoinV2Active,
                      ghostActive: points.ghostMode,
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
