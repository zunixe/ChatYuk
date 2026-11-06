import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../models/withdraw_request.dart';
import '../providers/riverpod/earnings_provider.dart';
import '../providers/riverpod/kyc_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/withdraw_provider.dart';
import '../widgets/withdraw/dana_form.dart';
import 'kyc_screen.dart';

/// Layar Withdraw — tarik koin `earned` ke akun DANA.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final _amountCtrl = TextEditingController();
  final _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  int get _amount => int.tryParse(_amountCtrl.text.trim()) ?? 0;

  WithdrawQuote get _quote => ref.read(withdrawProvider).config.quote(_amount);

  /// Bisa ditarik sekarang = earned dikurangi masa tahan (get_earnings_summary).
  /// Ringkasan belum termuat → fallback saldo earned (server tetap menolak).
  int _available(WithdrawState state) {
    final e = ref.read(earningsProvider);
    return e.loading ? state.earnedBalance : e.withdrawable;
  }

  Future<void> _submit() async {
    final s = ref.read(localeProvider).s;
    final state = ref.read(withdrawProvider);
    final coins = _amount;

    if (coins < state.config.minCoins) {
      _snack(s.wdBelowMin(state.config.minCoins), error: true);
      return;
    }
    if (coins > _available(state)) {
      final held = ref.read(earningsProvider).held;
      _snack(
        held > 0
            ? s.wdHeld(_available(state), state.config.holdDays)
            : s.wdInsufficient,
        error: true,
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.wdConfirmTitle,
            style: AppText.title.copyWith(color: AppTheme.textPrimary)),
        content: Text(
          s.wdConfirmBody(coins, _quote.netIdr),
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.yukcoinCancel,
                style: AppText.bodySmall
                    .copyWith(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2ECC71),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.wdConfirmYes),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final err = await ref.read(withdrawProvider.notifier).request(coins);
    if (!mounted) return;
    if (err == null) {
      _amountCtrl.clear();
      _snack(s.wdSuccess);
    } else {
      // KYC_REQUIRED → beri jalan langsung ke halaman verifikasi, bukan
      // hanya teks error yang menggantung tanpa tindakan.
      if (err == 'KYC_REQUIRED') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorText(err)),
            backgroundColor: AppTheme.danger,
            action: SnackBarAction(
              label: s.kycVerifyNow,
              onPressed: _openKyc,
            ),
          ),
        );
      } else {
        _snack(_errorText(err), error: true);
      }
    }
  }

  void _openKyc() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KycScreen()),
    );
  }

  int _detailInt(String key, int fallback) =>
      (ref.read(withdrawProvider.notifier).lastErrorDetail?[key] as num?)
          ?.toInt() ??
      fallback;

  String _errorText(String code) {
    final s = ref.read(localeProvider).s;
    final cfg = ref.read(withdrawProvider).config;
    return switch (code) {
      'BELOW_MINIMUM' => s.wdBelowMin(cfg.minCoins),
      // Kode yang BENAR-BENAR dikembalikan request_withdraw saat ini
      // (20261101100000). INSUFFICIENT_EARNED sudah tidak dipakai server.
      'INSUFFICIENT_BALANCE' => s.wdInsufficient,
      'INSUFFICIENT_EARNED' => s.wdInsufficient,
      'POINTS_DISABLED' => s.wdPointsDisabled,
      'DAILY_LIMIT' => s.wdDailyLimit(cfg.maxPerDay),
      'TOO_SOON' => s.wdTooSoon(cfg.minIntervalHours),
      'ACCOUNT_TOO_NEW' => s.wdAccountTooNew(cfg.minAccountAgeHours),
      'INVALID_NUMBER' => s.wdInvalidNumber,
      'INVALID_NAME' => s.wdInvalidName,
      'NO_ACCOUNT' => s.wdNoAccount,
      'FEMALE_ONLY' => s.wdFemaleOnly,
      'KYC_REQUIRED' => s.wdKycRequired,
      'DANA_CHANGE_COOLDOWN' => s.wdDanaCooldown(cfg.danaChangeCooldownHours),
      'HELD_BALANCE' => s.wdHeld(_detailInt('available', 0), cfg.holdDays),
      'DAILY_AMOUNT_LIMIT' =>
        s.wdDailyAmount(_detailInt('remaining', cfg.maxCoinsPerDay)),
      'UNDER_REVIEW' => s.wdUnderReview,
      'DANA_IN_USE' => s.wdDanaInUse,
      _ => s.wdErrGeneric,
    };
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? AppTheme.danger : const Color(0xFF2ECC71),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final state = ref.watch(withdrawProvider);
    final notifier = ref.read(withdrawProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.wdTitle),
        backgroundColor: AppTheme.bgScreen,
        actions: [
          IconButton(
            tooltip: s.btnRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.refresh(),
          ),
        ],
      ),
      // Kegagalan muat data JANGAN disamarkan dengan saldo 0 + riwayat
      // kosong — itu terbaca seperti "memang belum ada apa-apa".
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.history.isEmpty && state.earnedBalance == 0
              ? _ErrorView(
                  message: s.wdLoadFail,
                  onRetry: () => notifier.refresh(),
                )
              : RefreshIndicator(
              onRefresh: () => notifier.refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  // Banner KYC — withdraw digerbangi verifikasi identitas
                  // (require_kyc). Ditampilkan bila belum approved: none →
                  // CTA verifikasi, pending → status ditinjau, rejected →
                  // CTA kirim ulang. Approved → banner hilang.
                  if (state.config.requireKyc)
                    _KycBanner(s: s, onOpen: _openKyc),
                  _WithdrawableCard(
                    s: s,
                    earned: state.earnedBalance,
                    minCoins: state.config.minCoins,
                    rate: state.config.rate,
                    rupiah: _rupiah,
                  ),
                  const SizedBox(height: 14),
                  _SectionTitle(s.wdCalcTitle),
                  const SizedBox(height: 8),
                  _AmountCard(
                    s: s,
                    controller: _amountCtrl,
                    config: state.config,
                    earned: state.earnedBalance,
                    rupiah: _rupiah,
                    submitting: state.submitting,
                    onChanged: () => setState(() {}),
                    onMax: () {
                      // Maks = yang BENAR-BENAR bisa ditarik (setelah masa
                      // tahan), bukan seluruh saldo earned.
                      _amountCtrl.text = '${_available(state)}';
                      setState(() {});
                    },
                    onSubmit: _submit,
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(s.wdDanaTitle),
                  const SizedBox(height: 8),
                  DanaForm(
                    initialNumber: state.account?.danaNumber ?? '',
                    initialName: state.account?.danaName ?? '',
                    onSave: (n, name) async {
                      final err = await notifier.saveAccount(n, name);
                      return err == null ? null : _errorText(err);
                    },
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle(s.wdHistory),
                  const SizedBox(height: 8),
                  if (state.history.isEmpty)
                    _EmptyHistory(s: s)
                  else
                    ...state.history.map(
                      (r) => _HistoryTile(request: r, rupiah: _rupiah),
                    ),
                ],
              ),
            ),
    );
  }
}

class _WithdrawableCard extends StatelessWidget {
  final S s;
  final int earned;
  final int minCoins;
  final int rate;
  final NumberFormat rupiah;

  const _WithdrawableCard({
    required this.s,
    required this.earned,
    required this.minCoins,
    required this.rate,
    required this.rupiah,
  });

  @override
  Widget build(BuildContext context) {
    final ready = earned >= minCoins;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ready
              ? const [Color(0xFF2ECC71), Color(0xFF27AE60)]
              : const [Color(0xFF7F8C8D), Color(0xFF95A5A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(
                s.wdWithdrawable,
                style: AppText.caption.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$earned 🪙',
            style: AppText.display.copyWith(color: Colors.white),
          ),
          // Pakai rate dari server (get_withdraw_config), bukan angka
          // tetap 7 — admin bisa mengubahnya.
          Text(
            '≈ ${rupiah.format(earned * rate)}',
            style: AppText.bodyStrong.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.wdWithdrawableHint,
                  style: AppText.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  final S s;
  final TextEditingController controller;
  final WithdrawConfig config;
  final int earned;
  final NumberFormat rupiah;
  final bool submitting;
  final VoidCallback onChanged;
  final VoidCallback onMax;
  final VoidCallback onSubmit;

  const _AmountCard({
    required this.s,
    required this.controller,
    required this.config,
    required this.earned,
    required this.rupiah,
    required this.submitting,
    required this.onChanged,
    required this.onMax,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final coins = int.tryParse(controller.text.trim()) ?? 0;
    final quote = config.quote(coins);
    final valid = coins >= config.minCoins && coins <= earned;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  style: AppText.bodyStrong
                      .copyWith(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.wdAmountLabel,
                    hintText: s.wdAmountHint(config.minCoins),
                    prefixIcon: const Icon(Icons.monetization_on_outlined,
                        size: 18),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onMax,
                child: Text(s.wdMaxAmount),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CalcRow(s.wdCalcGross, rupiah.format(quote.grossIdr)),
          _CalcRow(
            '${s.wdCalcFee} (${config.feePct}%)',
            '- ${rupiah.format(quote.feeIdr)}',
            valueColor: AppTheme.danger,
          ),
          Divider(height: 14, color: AppTheme.divider),
          _CalcRow(
            s.wdCalcNet,
            rupiah.format(quote.netIdr),
            valueColor: const Color(0xFF2ECC71),
            strong: true,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (valid && !submitting) ? onSubmit : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2ECC71),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(s.wdSubmit, style: AppText.button),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalcRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool strong;

  const _CalcRow(this.label, this.value, {this.valueColor, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.bodySmall
                  .copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Text(
            value,
            style: (strong ? AppText.bodyStrong : AppText.bodySmall)
                .copyWith(color: valueColor ?? AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final WithdrawRequest request;
  final NumberFormat rupiah;

  const _HistoryTile({required this.request, required this.rupiah});

  @override
  Widget build(BuildContext context) {
    final color = switch (request.status) {
      WithdrawStatus.paid => const Color(0xFF2ECC71),
      WithdrawStatus.rejected => AppTheme.danger,
      WithdrawStatus.pending => Colors.orange,
    };
    final s = S(isId: AppLocale.isId);
    final statusLabel = switch (request.status) {
      WithdrawStatus.paid => s.wdStatusPaid,
      WithdrawStatus.rejected => s.wdStatusRejected,
      WithdrawStatus.pending => s.wdStatusPending,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              request.isPaid
                  ? Icons.check
                  : request.isRejected
                  ? Icons.close
                  : Icons.schedule,
              size: 17,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${request.coins} 🪙 → ${rupiah.format(request.netIdr)}',
                  style: AppText.bodyStrong
                      .copyWith(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${request.danaNumber} · ${request.danaName}',
                  style: AppText.caption
                  .copyWith(color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (request.adminNote != null &&
                    request.adminNote!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${s.wdReviewNote}: ${request.adminNote}',
                    style: AppText.caption.copyWith(color: color),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: AppText.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _date(request.createdAt),
                style: AppText.micro
                    .copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
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

class _EmptyHistory extends StatelessWidget {
  final S s;
  const _EmptyHistory({required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.history, size: 30, color: AppTheme.textSecondary),
          const SizedBox(height: 8),
          Text(
            s.wdHistoryEmpty,
            style: AppText.bodySmall
                .copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Kegagalan muat data withdraw — jangan disamarkan jadi "saldo 0".
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
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
              message,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: Text(
                S(isId: AppLocale.isId)
                    .btnRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner status KYC di atas kartu saldo — terlihat saat `require_kyc`
/// aktif dan verifikasi belum approved. Pending → status (tanpa CTA);
/// none/rejected → CTA buka halaman verifikasi.
class _KycBanner extends ConsumerWidget {
  final S s;
  final VoidCallback onOpen;
  const _KycBanner({required this.s, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kyc = ref.watch(kycProvider);
    if (kyc.isApproved) return const SizedBox.shrink();

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
      padding: const EdgeInsets.only(bottom: 12),
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
                onPressed: onOpen,
                child: Text(s.kycVerifyNow),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
