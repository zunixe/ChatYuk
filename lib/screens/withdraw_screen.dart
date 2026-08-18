import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../services/kyc_service.dart';
import '../services/points_service.dart';
import 'kyc_screen.dart';
import 'withdrawal_history_screen.dart';
import '../providers/theme_provider.dart';

/// Screen pencairan koin (earned) → rupiah. Syarat: KYC approved.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});
  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _amountCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  String _payMethod = 'qris';
  bool _kycApproved = false;
  bool _loadingKyc = true;
  bool _submitting = false;
  int _rate = 7;
  int _minCoins = 1000;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final kyc = await KycService.instance.myStatus();
    final summary = await PointsService(Supabase.instance.client).withdrawalSummary();
    if (!mounted) return;
    setState(() {
      _kycApproved = kyc['status'] == 'approved';
      _loadingKyc = false;
      _rate = (summary['rate'] as num?)?.toInt() ?? 7;
      _minCoins = (summary['min_coins'] as num?)?.toInt() ?? 1000;
    });
  }

  Future<void> _submit() async {
    final s = context.read<LocaleProvider>().s;
    final points = context.read<PointsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final coin = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    final account = _accountCtrl.text.trim();
    final holder = _holderCtrl.text.trim();

    if (coin < _minCoins) {
      messenger.showSnackBar(SnackBar(content: Text(s.withdrawBelowMin(_minCoins))));
      return;
    }
    if (coin > points.earnedBalance) {
      messenger.showSnackBar(SnackBar(content: Text(s.withdrawInsufficient)));
      return;
    }
    if (account.length < 5 || holder.length < 3) {
      messenger.showSnackBar(SnackBar(content: Text(s.withdrawInvalidPayout)));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.withdrawConfirmTitle),
        content: Text(s.withdrawConfirmBody(coin, coin * _rate),
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnConfirm, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _submitting = true);
    try {
      await PointsService(Supabase.instance.client).requestWithdrawal(
        coinAmount: coin,
        payMethod: _payMethod,
        payAccount: account,
        payHolder: holder,
      );
      await points.refreshWallet();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.withdrawRequested)));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WithdrawalHistoryScreen()),
      );
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('KYC required') ? s.withdrawKycRequired
        : msg.contains('Below minimum') ? s.withdrawBelowMin(_minCoins)
        : msg.contains('Not enough') ? s.withdrawInsufficient
        : msg.contains('disabled') ? s.errCoinDisabled
        : s.withdrawFailed;
      messenger.showSnackBar(SnackBar(content: Text(show)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _accountCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final points = context.watch<PointsProvider>();
    final coin = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    final preview = coin > 0 ? coin * _rate : 0;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.withdrawTitle), backgroundColor: AppTheme.bgScreen),
      body: _loadingKyc
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
              children: [
                if (!_kycApproved) ...[
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      Icon(Icons.verified_user_outlined, color: Colors.teal, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.withdrawKycRequired,
                              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary)),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => const KycScreen()));
                              await _load();
                            },
                            child: Text(s.menuKyc,
                                style: AppText.bodySmall.copyWith(color: Colors.teal, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  SizedBox(height: 16),
                ],
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(s.withdrawBalance, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                      Text('${points.earnedBalance} 🪙',
                          style: AppText.bodyStrong.copyWith(color: Color(0xFFB8860B), fontWeight: FontWeight.w800)),
                    ]),
                    SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(s.withdrawRate, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                      Text('1 🪙 = Rp${_rate}',
                          style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                    Divider(height: 20),
                    Text(s.withdrawOnlyEarned,
                        style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
                  ]),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  enabled: _kycApproved,
                  onChanged: (_) => setState(() {}),
                  style: AppText.button.copyWith(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.withdrawAmount,
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                    suffixText: '🪙',
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Color(0xFF2E7D32).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(Icons.payments_outlined, color: Color(0xFF2E7D32), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        preview > 0 ? s.withdrawPreview(preview) : s.withdrawPreviewHint(_minCoins),
                        style: AppText.bodySmall.copyWith(color: Color(0xFF2E7D32), fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),
                SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _payMethod,
                  dropdownColor: AppTheme.bgCard,
                  style: AppText.body,
                  decoration: InputDecoration(
                    labelText: s.withdrawMethod,
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                  ),
                  items: ['qris', 'bank', 'ewallet'].map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(switch (m) {
                      'qris' => s.withdrawMethodQris,
                      'bank' => s.withdrawMethodBank,
                      _ => s.withdrawMethodEwallet,
                    }),
                  )).toList(),
                  onChanged: _kycApproved ? (v) => setState(() => _payMethod = v ?? 'qris') : null,
                ),
                SizedBox(height: 14),
                TextField(
                  controller: _accountCtrl,
                  enabled: _kycApproved,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: _payMethod == 'qris' ? s.withdrawQrisId : s.withdrawAccountNo,
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                SizedBox(height: 14),
                TextField(
                  controller: _holderCtrl,
                  enabled: _kycApproved,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.withdrawHolder,
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF2E7D32),
                    padding: EdgeInsets.symmetric(vertical: 14),
                    disabledBackgroundColor: AppTheme.bgInput,
                  ),
                  onPressed: (!_kycApproved || _submitting) ? null : _submit,
                  icon: _submitting
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.currency_exchange),
                  label: Text(_submitting ? s.loading : s.withdrawSubmit,
                      style: AppText.bodyStrong.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WithdrawalHistoryScreen())),
                  icon: Icon(Icons.history, size: 16, color: AppTheme.textSecondary),
                  label: Text(s.withdrawHistory, style: TextStyle(color: AppTheme.textSecondary)),
                ),
              ],
            ),
    );
  }
}
