import 'package:flutter/material.dart';
import '../config/gifts.dart';
import '../config/theme.dart';

/// Overlay animasi gift di room live: banner gift terbang + kombo counter.
/// Pasang sebagai Stack child di atas chat list. Jangan rebuild list.
class GiftFlyOverlay extends StatefulWidget {
  const GiftFlyOverlay({super.key, required this.controller});

  final GiftFlyController controller;

  @override
  State<GiftFlyOverlay> createState() => _GiftFlyOverlayState();
}

/// Controller: room screen memanggil [push] saat pesan type='gift' masuk.
class GiftFlyController extends ChangeNotifier {
  final List<_FlyItem> _flies = [];
  int _seq = 0;

  /// Kombo aktif: giftId → (count, lastAt)
  final Map<String, ({int count, DateTime at})> _combos = {};
  static const _comboWindow = Duration(seconds: 3);

  List<_FlyItem> get flies => List.unmodifiable(_flies);

  /// Kombo aktif untuk ditampilkan (yang terakhir, masih dalam window).
  (GiftItem, int)? get activeCombo {
    final now = DateTime.now();
    String? key;
    DateTime? latest;
    for (final entry in _combos.entries) {
      if (now.difference(entry.value.at) > _comboWindow) continue;
      if (latest == null || entry.value.at.isAfter(latest)) {
        latest = entry.value.at;
        key = entry.key;
      }
    }
    if (key == null) return null;
    final gift = giftById(key);
    final count = _combos[key]?.count ?? 0;
    if (gift == null || count <= 0) return null;
    return (gift, count);
  }

  void push(GiftItem gift, String senderName, int qty) {
    // kombo
    final prev = _combos[gift.id];
    final now = DateTime.now();
    final alive = prev != null && now.difference(prev.at) <= _comboWindow;
    _combos[gift.id] = (
      count: alive ? prev.count + qty : qty,
      at: now,
    );

    // fly item (max 5 biar gak numpuk)
    _seq++;
    _flies.add(_FlyItem(_seq, gift, senderName, qty));
    while (_flies.length > 5) {
      _flies.removeAt(0);
    }
    notifyListeners();

    // auto-hapus fly setelah animasi selesai
    Future.delayed(const Duration(milliseconds: 2600), () {
      _flies.removeWhere((f) => f.id == _seq);
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _combos.clear();
    _flies.clear();
    super.dispose();
  }
}

class _FlyItem {
  final int id;
  final GiftItem gift;
  final String sender;
  final int qty;
  _FlyItem(this.id, this.gift, this.sender, this.qty);
}

class _GiftFlyOverlayState extends State<GiftFlyOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final combo = controller.activeCombo;

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Banner kombo (paling atas kiri)
          if (combo != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: _ComboBadge(gift: combo.$1, count: combo.$2),
            ),
          // Gift terbang
          for (final fly in controller.flies) _FlyBanner(item: fly),
        ],
      ),
    );
  }
}

class _ComboBadge extends StatelessWidget {
  const _ComboBadge({required this.gift, required this.count});

  final GiftItem gift;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x99FF2D95), Color(0x99FF8A00)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(gift.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            'x$count',
            style: AppText.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlyBanner extends StatefulWidget {
  const _FlyBanner({required this.item});

  final _FlyItem item;

  @override
  State<_FlyBanner> createState() => _FlyBannerState();
}

class _FlyBannerState extends State<_FlyBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(-1.2, 0),
      end: const Offset(0, 0),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 15),
    ]).animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      top: 80 + (widget.item.id % 3) * 48.0,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.item.gift.emoji,
                    style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(
                  widget.item.sender,
                  style: AppText.caption.copyWith(color: Colors.white),
                ),
                if (widget.item.qty > 1)
                  Text(
                    ' x${widget.item.qty}',
                    style: AppText.caption.copyWith(
                      color: const Color(0xFFFFC94D),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
