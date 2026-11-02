import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_flavor.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../core/admin_gate.dart';
import '../core/nav_gate.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/my_level_provider.dart';
import '../providers/riverpod/points_provider.dart';
import 'profile/widgets/profile_widgets.dart' show formatPoints;
import 'my_level/widgets/my_level_widgets.dart';

/// Layar My Level (MALE only) — level dari kumulatif topup YukCoin.
/// Rujukan: halaman "My Level" app referensi (kartu Lv + progress,
/// tab Privileges per level, tabel Aturan Level).
class MyLevelScreen extends ConsumerStatefulWidget {
  const MyLevelScreen({super.key});

  @override
  ConsumerState<MyLevelScreen> createState() => _MyLevelScreenState();
}

class _MyLevelScreenState extends ConsumerState<MyLevelScreen> {
  int _tabLevel = -1;

  void _openTopup(S s) {
    final show = NavGate.topupSheet;
    final open = AppFlavor.topupEnabled ||
        AdminGate.enabled ||
        ref.read(pointsProvider).topupPathOpen;
    if (open && show != null) {
      show(context, s);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.yukcoinTopupSoon)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final st = ref.watch(myLevelProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.myLevelTitle),
        backgroundColor: AppTheme.bgScreen,
      ),
      body: st.loading && st.ladder.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : st.error != null && st.ladder.isEmpty
          ? _ErrorView(s: s, onRetry: () => ref.read(myLevelProvider.notifier).refresh())
          : RefreshIndicator(
              onRefresh: () => ref.read(myLevelProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  MyLevelHeroCard(st: st, s: s),
                  const SizedBox(height: 16),
                  MyLevelPrivileges(
                    ladder: st.ladder,
                    selected: _tabLevel < 0 ? st.level : _tabLevel,
                    onSelect: (lv) => setState(() => _tabLevel = lv),
                    s: s,
                  ),
                  const SizedBox(height: 16),
                  MyLevelRuleTable(ladder: st.ladder, current: st.level, s: s),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openTopup(s),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: Text(s.myLevelCtaTopup, style: AppText.button),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Kartu hero: Lv besar + progress ke level berikutnya.
class MyLevelHeroCard extends StatelessWidget {
  final MyLevelState st;
  final S s;
  const MyLevelHeroCard({super.key, required this.st, required this.s});

  @override
  Widget build(BuildContext context) {
    final next = st.nextLevel;
    final nextAt = st.nextAt;
    final progress = (nextAt == null || nextAt <= 0)
        ? 1.0
        : (st.cumulative / nextAt).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.headerGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.levelShort(st.level),
                  style: AppText.display.copyWith(color: Colors.white),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${s.levelShort(st.level)} (${formatPoints(st.cumulative)} 🪙)',
                style: AppText.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              Expanded(
                child: Text(
                  next == null ? '' : s.levelShort(next),
                  textAlign: TextAlign.right,
                  style: AppText.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          Text(
            next == null || nextAt == null
                ? s.myLevelMaxLevel
                : s.myLevelTopupMore(
                    formatPoints((nextAt - st.cumulative).clamp(0, nextAt)),
                    next,
                  ),
            style: AppText.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          // Reward yang baru saja dicetak (naik level saat topup terakhir).
          for (final r in st.justRewarded) ...[
            const SizedBox(height: 6),
            Text(
              s.myLevelReward((r['coins'] as num?)?.toInt() ?? 0),
              style: AppText.bodyStrong.copyWith(color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final S s;
  final VoidCallback onRetry;
  const _ErrorView({required this.s, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.orange, size: 36),
            const SizedBox(height: 10),
            Text(
              s.myLevelLoadFail,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(s.btnRetry)),
          ],
        ),
      ),
    );
  }
}
