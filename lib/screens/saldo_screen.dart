import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/riverpod/earnings_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/withdraw_provider.dart';
import 'withdraw_screen.dart';

/// Layar Saldo — tampilkan saldo YukCoin + rincian penghasilan + statistik.
class SaldoScreen extends ConsumerWidget {
  const SaldoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final state = ref.watch(earningsProvider);
    final canWithdraw =
        ref.watch(withdrawProvider.select((w) => w.canWithdraw));

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.saldoTitle),
        backgroundColor: AppTheme.bgScreen,
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
          ? _ErrorView(s: s, onRetry: () => ref.read(earningsProvider.notifier).refresh())
          : RefreshIndicator(
              onRefresh: () => ref.read(earningsProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  _BalanceCard(
                    s: s,
                    withdrawable: state.withdrawable,
                    totalBalance: state.totalBalance,
                  ),
                  const SizedBox(height: 10),
                  // Tombol withdraw — saldo withdrawable sudah jadi angka
                  // utama di kartu atas. Non-aktif sampai saldo earned
                  // mencapai withdraw_min_coins (gerbang sama dengan
                  // request_withdraw di server).
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canWithdraw
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const WithdrawScreen(),
                                ),
                              )
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2ECC71),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.arrow_outward, size: 18),
                      label: Text(s.wdTitle, style: AppText.button),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionTitle(s.saldoEarnings),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      s.saldoTotalHint,
                      style: AppText.caption
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: s.saldoTotal,
                          value: _coins(state.totalEarnings),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          label: s.saldoWeekly,
                          value: _coins(state.weeklyEarnings),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          label: s.saldoToday,
                          value: _coins(state.todayEarnings),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(s.saldoBreakdown),
                  const SizedBox(height: 8),
                  _Card(
                    child: Column(
                      children: [
                        // "Bonus" sengaja TIDAK ditampilkan: female tidak
                        // punya bonus, dan bonus male bukan "penghasilan".
                        _Row(s.saldoPrivateCall, state.privateCall),
                        _Row(s.saldoMatchCall, state.matchCall),
                        _Row(s.saldoMessage, state.message),
                        _Row(s.saldoGift, state.gift),
                        _Row(s.saldoMission, state.mission),
                        _Row(s.saldoOther, state.other, last: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(s.saldoStats),
                  const SizedBox(height: 8),
                  _Card(
                    child: Column(
                      children: [
                        _InfoRow(
                          s.saldoVideoCallCount,
                          '${state.videoCallCount} ${s.saldoUnitTimes}',
                        ),
                        _InfoRow(
                          s.saldoVideoCallDuration,
                          '${(state.videoCallSeconds / 60).round()} ${s.saldoUnitMin}',
                        ),
                        _InfoRow(
                          s.saldoAvgMatch,
                          '${(state.avgMatchSeconds / 60).round()} ${s.saldoUnitMin}',
                        ),
                        _InfoRow(
                          s.saldoAnswerRate,
                          '${state.privateAnswerRate}${s.saldoUnitPct}',
                          last: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _coins(int n) => '$n 🪙';
}

class _BalanceCard extends StatelessWidget {
  final S s;
  final int withdrawable;
  final int totalBalance;

  const _BalanceCard({
    required this.s,
    required this.withdrawable,
    this.totalBalance = 0,
  });

  /// 2026-11-01: yang bisa ditarik HANYA bucket `earned` (request_withdraw
  /// menolak bonus). Koin `bonus` — termasuk reward misi male — menaikkan
  /// saldo total tapi tidak bisa dicairkan, jadi headline pakai angka
  /// withdrawable dari server, bukan total.
  int get _headline => withdrawable;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                s.wdWithdrawable,
                style: AppText.caption.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_headline 🪙',
            style: AppText.display.copyWith(color: Colors.white),
          ),
          Text(
            s.wdWithdrawableHint,
            style: AppText.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          // Total semua bucket ditampilkan terpisah supaya tidak tertukar
          // dengan angka yang benar-benar bisa ditarik.
          if (totalBalance != withdrawable) ...[
            const SizedBox(height: 6),
            Text(
              '${s.wdTotalBalance}: $totalBalance 🪙',
              style: AppText.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: AppText.label.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: child,
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.bodyStrong.copyWith(color: Colors.amber),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final int coins;
  final bool last;
  const _Row(this.label, this.coins, {this.last = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(color: AppTheme.divider, width: 0.6),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
            ),
          ),
          Text(
            '$coins 🪙',
            style: AppText.bodyStrong.copyWith(
              color: coins > 0 ? Colors.amber : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;
  const _InfoRow(this.label, this.value, {this.last = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(color: AppTheme.divider, width: 0.6),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Text(
            value,
            style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
          ),
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
              s.saldoLoadFail,
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
