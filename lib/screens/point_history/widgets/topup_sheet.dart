import 'package:flutter/material.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../services/points_service.dart';
import '../../../services/topup_service.dart';

/// Bottom sheet pilih paket topup YukCoin (Google Play Billing).
/// Harga & paket dari server (topup_packages) + product dari Play.
void showTopupSheet(BuildContext context, S s) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _TopupSheet(),
  );
}

class _TopupSheet extends StatefulWidget {
  const _TopupSheet();

  @override
  State<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends State<_TopupSheet> {
  List<Map<String, dynamic>> _packages = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Pakai paket dari TopupService bila ada (Play); else ambil dari server
    // (build admin → verifikasi UI paket).
    var pkgs = TopupService.instance.packages;
    if (pkgs.isEmpty) {
      try {
        pkgs = await PointsService().listTopupPackages();
      } catch (_) {}
    }
    if (mounted) setState(() { _packages = pkgs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = S(isId: Localizations.localeOf(context).languageCode == 'id');
    // Tombol beli aktif hanya bila Play Billing tersedia (build Play).
    final canBuy = TopupService.instance.available;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.yukcoinTopup, style: AppText.title),
            const SizedBox(height: 4),
            Text(
              s.yukcoinPickPackage,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
            if (!canBuy) ...[
              const SizedBox(height: 6),
              Text(
                s.yukcoinTopupSoon,
                style: AppText.caption.copyWith(color: Colors.orange),
              ),
            ],
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_packages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    s.yukcoinTopupSoon,
                    style: AppText.body.copyWith(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              ..._packages.map(
                (p) => _PackageTile(package: p, canBuy: canBuy),
              ),
          ],
        ),
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  final Map<String, dynamic> package;
  final bool canBuy;
  const _PackageTile({required this.package, this.canBuy = false});

  @override
  Widget build(BuildContext context) {
    final coins = (package['coins'] as num?)?.toInt() ?? 0;
    final priceIdr = (package['price_idr'] as num?)?.toInt() ?? 0;
    final label = package['bonus_label'] as String?;
    final productId = package['play_product_id'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: (productId == null || !canBuy)
              ? null
              : () {
                  TopupService.instance.buy(productId);
                  Navigator.of(context).pop();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.monetization_on_outlined,
                    color: AppTheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Text('$coins', style: AppText.bodyStrong),
                      const SizedBox(width: 4),
                      Text(
                        '🪙',
                        style: AppText.bodySmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                      if (label != null && label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            label,
                            style: AppText.label.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  'Rp ${_thousand(priceIdr)}',
                  style: AppText.bodyStrong.copyWith(color: AppTheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _thousand(int n) {
    final str = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return buf.toString();
  }
}
