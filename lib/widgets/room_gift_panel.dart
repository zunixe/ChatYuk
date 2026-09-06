import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/gifts.dart';
import '../../config/theme.dart';
import '../../providers/locale_provider.dart';
import '../../providers/points_provider.dart';

/// Panel pilih gift untuk room live (ala streaming).
/// Return `GiftPick` (gift + qty) saat user tap item.
class RoomGiftPanel extends StatefulWidget {
  const RoomGiftPanel({super.key, required this.points});

  final PointsProvider points;

  static Future<GiftPick?> show(BuildContext context) {
    final points = context.read<PointsProvider>();
    return showModalBottomSheet<GiftPick>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(child: RoomGiftPanel(points: points)),
    );
  }

  @override
  State<RoomGiftPanel> createState() => _RoomGiftPanelState();
}

class GiftPick {
  final GiftItem gift;
  final int qty;
  const GiftPick(this.gift, this.qty);
  int get total => gift.coins * qty;
}

class _RoomGiftPanelState extends State<RoomGiftPanel> {
  int _qty = 1;

  bool _canAfford(GiftItem g, int qty) {
    final total = g.coins * qty;
    return total <= widget.points.paidBalance ||
        total <= widget.points.bonusBalance;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.giftTitle, style: AppText.title),
          const SizedBox(height: 4),
          Text(
            s.giftPick,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            '${s.paidBalanceLabel}: ${widget.points.paidBalance}'
            '  •  Bonus: ${widget.points.bonusBalance}',
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.8,
              ),
              itemCount: kGiftCatalog.length,
              itemBuilder: (ctx, i) {
                final g = kGiftCatalog[i];
                final afford = _canAfford(g, _qty);
                return InkWell(
                  onTap: afford
                      ? () => Navigator.of(ctx).pop(GiftPick(g, _qty))
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgInput.withValues(
                        alpha: afford ? 1 : 0.4,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: afford
                            ? Colors.pinkAccent.withValues(alpha: 0.4)
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(g.emoji, style: const TextStyle(fontSize: AppGlyph.lg)),
                        const SizedBox(height: 4),
                        Text(
                          '${g.coins * _qty} 🪙',
                          style: AppText.caption.copyWith(
                            color: afford
                                ? const Color(0xFFB8860B)
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('x1', style: AppText.bodySmall),
              Expanded(
                child: Slider(
                  value: _qty.toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  label: 'x$_qty',
                  onChanged: (v) => setState(() => _qty = v.round()),
                ),
              ),
              Text('x$_qty', style: AppText.title),
            ],
          ),
        ],
      ),
    );
  }
}
