import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/riverpod/earnings_provider.dart';
import '../providers/riverpod/kyc_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/withdraw_provider.dart';
import '../utils.dart';
import 'kyc_screen.dart';
import 'withdraw_screen.dart';

/// Layar Saldo — tampilkan saldo YukCoin + rincian penghasilan + statistik.
class SaldoScreen extends ConsumerWidget {
  const SaldoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final state = ref.watch(earningsProvider);
    final wd = ref.watch(
      withdrawProvider.select(
        (w) => (
          can: w.canWithdraw,
          min: w.config.minCoins,
          earned: w.earnedBalance,
          loading: w.loading,
          rate: w.config.rate,
          requireKyc: w.config.requireKyc,
        ),
      ),
    );
    final kyc = ref.watch(kycProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.saldoTitle),
        backgroundColor: AppTheme.bgScreen,
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
          ? _ErrorView(
              s: s,
              onRetry: () => ref.read(earningsProvider.notifier).refresh(),
            )
          : RefreshIndicator(
              onRefresh: () => ref.read(earningsProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  _BalanceCard(
                    s: s,
                    withdrawable: state.withdrawable,
                    totalBalance: state.totalBalance,
                    rate: wd.rate,
                    held: state.held,
                    holdDays: state.holdDays,
                  ),
                  const SizedBox(height: 10),
                  // KYC bisa dimulai SEKARANG walau saldo belum cukup —
                  // tombol terpisah, tidak bergantung minimum withdraw.
                  if (wd.requireKyc && !kyc.isApproved && !kyc.loading)
                    _SaldoKycCard(s: s, kyc: kyc),
                  // Tombol withdraw TERKUNCI di bawah minimum — membuka
                  // layar withdraw (isi DANA/riwayat) hanya saat saldo
                  // sudah cukup, supaya user tak mengira bisa menarik.
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: wd.can
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
                  // Kapan tombol hidup — user tak menebak kenapa withdraw
                  // abu-abu (batas sama dengan request_withdraw server).
                  if (!wd.can && !wd.loading)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        s.saldoWdLocked(
                          wd.min,
                          (wd.min - wd.earned).clamp(0, wd.min),
                        ),
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _SectionTitle(s.saldoEarnings),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      s.saldoTotalHint,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
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

/// Kartu KYC di layar Saldo — pintu verifikasi yang SELALU aktif walau
/// saldo belum mencapai minimum withdraw. Menampilkan status terkini
/// (none/rejected → tombol buka form; pending → status ditinjau).
class _SaldoKycCard extends StatelessWidget {
  final S s;
  final KycState kyc;
  const _SaldoKycCard({required this.s, required this.kyc});

  @override
  Widget build(BuildContext context) {
    final pending = kyc.isPending;
    final (icon, color, text) = switch (kyc.status) {
      'pending' => (
        Icons.hourglass_top_outlined,
        Colors.orange,
        s.kycPendingBody,
      ),
      'rejected' => (
        Icons.error_outline,
        AppTheme.danger,
        kyc.rejectReason != null && kyc.rejectReason!.isNotEmpty
            ? '${s.kycRejectedTitle} — ${s.kycRejectedReason(kyc.rejectReason!)}'
            : s.kycRejectedTitle,
      ),
      _ => (
        Icons.verified_user_outlined,
        AppTheme.primary,
        s.kycBannerWithdraw,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
              ),
            ),
            if (!pending) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const KycScreen()),
                ),
                child: Text(s.kycVerifyNow),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final S s;
  final int withdrawable;
  final int totalBalance;
  final int rate;
  final int held;
  final int holdDays;

  const _BalanceCard({
    required this.s,
    required this.withdrawable,
    this.totalBalance = 0,
    this.rate = 7,
    this.held = 0,
    this.holdDays = 7,
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
              const Icon(Icons.savings_outlined, color: Colors.white, size: 20),
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
          const SizedBox(height: 2),
          // Estimasi nilai fiat dari rate server (get_withdraw_config) —
          // gambaran kasar sebelum withdraw; bukan janji payout.
          Text(
            '≈ ${formatFiatEstimate(withdrawable * rate, isId: s.isId)}',
            style: AppText.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          // Keterangan sekunder dikelompokkan satu kotak translusen supaya
          // tidak berderet longgar di bawah headline.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(Icons.info_outline, s.wdWithdrawableHint),
                if (held > 0)
                  _InfoLine(
                    Icons.lock_clock_outlined,
                    s.wdHeldInfo(held, holdDays),
                  ),
                // Total semua bucket ditampilkan terpisah supaya tidak
                // tertukar dengan angka yang benar-benar bisa ditarik.
                if (totalBalance != withdrawable)
                  _InfoLine(
                    Icons.account_balance_wallet_outlined,
                    '${s.wdTotalBalance}: $totalBalance 🪙',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris keterangan di kotak translusen kartu saldo: ikon + teks, rata.
class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: 0.92);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppText.caption.copyWith(color: color)),
          ),
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
            : Border(bottom: BorderSide(color: AppTheme.divider, width: 0.6)),
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
            : Border(bottom: BorderSide(color: AppTheme.divider, width: 0.6)),
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
