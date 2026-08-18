import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/auth_provider.dart';
import '../services/topup_service.dart';
import '../providers/theme_provider.dart';

class TopUpScreen extends StatefulWidget {
  const TopUpScreen({super.key});

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  final TopupService _service = TopupService();
  bool _loading = true;
  bool _buying = false;
  String? _buyingId;
  List<Map<String, dynamic>> _packages = [];
  String? _pendingOrderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pkgs = await _service.packages();
      if (!mounted) return;
      setState(() {
        _packages = pkgs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _buy(Map<String, dynamic> pkg) async {
    if (_buying) return;
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    if (!auth.canUsePaid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
      return;
    }
    setState(() { _buying = true; _buyingId = pkg['id'] as String?; });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final order = await _service.createOrder(pkg['id'] as String);
      _pendingOrderId = order['order_id'] as String?;
      final redirect = order['redirect_url'] as String?;
      if (redirect == null) throw Exception('No redirect URL');
      final uri = Uri.parse(redirect);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('Cannot open payment page');
      if (mounted) _showPendingSheet();
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(SnackBar(content: Text('${s.errGeneric}$msg')));
    } finally {
      if (mounted) setState(() { _buying = false; _buyingId = null; });
    }
  }

  // Setelah user diarahkan ke halaman pembayaran iPaymu, tampilkan sheet cek status.
  void _showPendingSheet() {
    final s = context.read<LocaleProvider>().s;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_bottom, size: 40, color: AppTheme.primary),
            SizedBox(height: 12),
            Text(s.topupWaitingTitle,
              style: AppText.titleEmphasis),
            SizedBox(height: 6),
            Text(s.topupWaitingBody, textAlign: TextAlign.center,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: () => _checkStatus(ctx),
                child: Text(s.topupCheckStatus, style: TextStyle(color: Colors.white)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.btnClose, style: TextStyle(color: AppTheme.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkStatus(BuildContext sheetCtx) async {
    final s = context.read<LocaleProvider>().s;
    final id = _pendingOrderId;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final status = await _service.orderStatus(id);
    if (!mounted) return;
    if (status == 'paid') {
      // Refresh wallet supaya saldo topup langsung tampil
      await context.read<PointsProvider>().refreshWallet();
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      messenger.showSnackBar(SnackBar(content: Text(s.topupSuccess)));
    } else if (status == 'pending' || status == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.topupStillPending)));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(s.topupFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final pts = context.watch<PointsProvider>();
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.topupTitle)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: EdgeInsets.all(16),
              children: [
                // Saldo saat ini
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppTheme.headerGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet, color: Colors.white, size: 32),
                      SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.walletTotal, style: AppText.bodySmall.copyWith(color: Colors.white70)),
                          Text('${pts.points} 🪙',
                            style: AppText.display.copyWith(color: Colors.white)),
                          SizedBox(height: 2),
                          Text('${s.paidBalanceLabel}: ${pts.paidBalance} 🪙',
                            style: AppText.caption.copyWith(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                Text(s.topupPickPackage,
                  style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                SizedBox(height: 8),
                ..._packages.map((p) => _PackageCard(
                  pkg: p,
                  buying: _buyingId == p['id'],
                  onTap: () => _buy(p),
                  s: s,
                )),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: AppTheme.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(s.topupInfo,
                          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> pkg;
  final bool buying;
  final VoidCallback onTap;
  final S s;
  const _PackageCard({required this.pkg, required this.buying, required this.onTap, required this.s});

  @override
  Widget build(BuildContext context) {
    final coins = (pkg['coins'] as num?)?.toInt() ?? 0;
    final price = (pkg['price_idr'] as num?)?.toInt() ?? 0;
    final bonus = pkg['bonus_label'] as String?;
    return Card(
      margin: EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: buying ? null : onTap,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.amber.shade50, shape: BoxShape.circle,
                ),
                child: Icon(Icons.monetization_on, color: Colors.amber.shade700, size: 24),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('$coins 🪙',
                          style: AppText.title),
                        if (bonus != null) ...[
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(bonus,
                              style: AppText.caption.copyWith(color: Colors.green, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 2),
                    Text('Rp ${_fmt(price)}',
                      style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              buying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: onTap,
                      child: Text(s.topupBuy),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(int n) {
    final str = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return buf.toString();
  }
}
