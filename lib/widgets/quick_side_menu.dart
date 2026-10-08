import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/nav_provider.dart';

/// Menu cepat melayang di tepi KANAN halaman Online — pil vertikal berisi
/// dua pintasan: **Timeline** (pindah tab) dan **Global Room** (buka room
/// kategori General, perilaku sama dengan kapsul lama).
///
/// Karakter visual:
///  - Nempel di tepi kanan, hanya SISI KIRI yang membulat (sisi kanan rata
///    dengan tepi layar).
///  - Latar semi-transparan polos (tanpa blur — blur mahal & tidak dipakai
///    di repo ini).
///  - Bisa DI-DRAG naik-turun; posisi terakhir disimpan per akun.
///  - Saat halaman Online dibuka → meluncur masuk dari kanan.
///  - Otomatis tersembunyi saat keyboard terbuka.
///
/// Widget ini murni UI + navigasi: ia hanya memanggil `navProvider` dan
/// callback yang diberikan pemanggil. Tidak ada I/O bisnis di sini
/// (patuh boundary AGENTS.md — screen/widget dilarang import services/).
class QuickSideMenu extends ConsumerStatefulWidget {
  /// Aksi saat pintasan Global Room diketuk. `Future` supaya menu bisa
  /// menunggu sampai halaman yang dibuka DITUTUP, lalu siap diketuk ulang.
  final Future<void> Function() onOpenRoom;

  /// Offset vertikal (px) dari posisi default; + = ke atas. Dipakai untuk
  /// menghitung Highlight Global Room yang aktif (opsional).
  final bool roomActive;

  /// Uid pemilik posisi drag (persist per akun).
  final String? ownerUid;

  const QuickSideMenu({
    super.key,
    required this.onOpenRoom,
    this.roomActive = false,
    this.ownerUid,
  });

  @override
  ConsumerState<QuickSideMenu> createState() => _QuickSideMenuState();
}

class _QuickSideMenuState extends ConsumerState<QuickSideMenu>
    with TickerProviderStateMixin {
  /// 0 = seluruhnya di luar kanan, 1 = menempel tepi.
  late final AnimationController _slide;

  /// Kedip halus ikon Global Room sebagai isyarat bisa diketuk.
  late final AnimationController _pulse;

  bool _leaving = false;

  /// Lebar tiap tombol (persegi) — pil = 2 tombol bertumpuk; tinggi = 2x.
  static const double _btn = 44;
  static const double _gap = 2;

  /// Offset vertikal dari posisi default; disimpan per akun.
  double _dragDy = 0;
  String? _owner;

  static String _prefKeyFor(String owner) => 'online_side_menu_dy_$owner';

  Future<void> _loadPos() async {
    final owner = widget.ownerUid;
    _owner = owner;
    if (mounted) setState(() => _dragDy = 0);
    if (owner == null || owner.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dy = prefs.getDouble(_prefKeyFor(owner));
      if (!mounted || dy == null) return;
      // Ganti akun di tengah proses → abaikan hasil akun lama.
      if (widget.ownerUid != _owner) return;
      setState(() => _dragDy = dy);
    } catch (_) {}
  }

  Future<void> _savePos() async {
    final owner = widget.ownerUid;
    if (owner == null || owner.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyFor(owner), _dragDy);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadPos();
    // Mulai dari 1.0 (MENEMPEL) supaya menu PASTI terlihat walau TickerMode
    // sedang pause (halaman Online ada di dalam IndexedStack + TickerMode).
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      value: 1.0,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  ValueListenable<bool>? _tickerNotifier;
  bool _tickerWasOn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode mati saat tab Online tidak aktif → animasi beku. Pantau
    // agar bisa memainkan animasi masuk tiap kali tab Online dibuka lagi.
    final notifier = TickerMode.getNotifier(context);
    if (!identical(_tickerNotifier, notifier)) {
      _tickerNotifier?.removeListener(_onTickerChanged);
      _tickerNotifier = notifier;
      _tickerNotifier?.addListener(_onTickerChanged);
    }
    _onTickerChanged();
  }

  @override
  void didUpdateWidget(covariant QuickSideMenu old) {
    super.didUpdateWidget(old);
    if (old.ownerUid != widget.ownerUid) _loadPos();
  }

  void _onTickerChanged() {
    final on = _tickerNotifier?.value ?? true;
    if (!mounted) return;
    if (on && !_tickerWasOn) {
      // Tab Online baru dibuka → set di luar dulu TANPA menunggu frame
      // (hindari 1 frame "blink" menempel), lalu meluncur masuk.
      _slide.value = 0;
      _slide.forward();
    }
    _tickerWasOn = on;
  }

  @override
  void dispose() {
    _tickerNotifier?.removeListener(_onTickerChanged);
    _slide.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Ketuk pintasan: luncurkan keluar sebentar, jalankan aksi, lalu masuk lagi.
  Future<void> _tap(Future<void> Function() action) async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _slide.reverse();
    } catch (_) {}
    if (!mounted) return;
    await action();
    if (!mounted) return;
    _leaving = false;
    _slide.value = 0;
    _slide.forward();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    // Aksesibilitas: mode hemat animasi → jangan tween sama sekali.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // Keyboard terbuka → sembunyikan menu supaya tidak menutupi input.
    final keyboardOpen = MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.first,
    ).viewInsets.bottom > 0;

    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Highlight Timeline saat tab aktif = Timeline (index 2).
    final timelineActive = ref.watch(navProvider.select((t) => t == 2));

    final panelH = _btn * 2 + _gap;

    return LayoutBuilder(
      builder: (_, constraints) {
        final maxBottom = (constraints.maxHeight - panelH - 8.0)
            .clamp(8.0, double.infinity)
            .toDouble();
        final bottom = (60 + bottomInset + _dragDy)
            .clamp(8.0, maxBottom)
            .toDouble();

        return AnimatedBuilder(
          animation: Listenable.merge([_slide, _pulse]),
          builder: (_, _) {
            // `_slide.value`: 0 = di luar kanan, 1 = menempel tepi.
            final out = reduceMotion
                ? 0.0
                : (1 - Curves.easeOutCubic.transform(_slide.value.clamp(0.0, 1.0)));
            final opacity = (1 - out).clamp(0.0, 1.0);
            // Lebar pil — travel lebih besar supaya benar-benar di luar layar.
            const travel = 80.0;

            return Stack(
              children: [
                Positioned(
                  right: -travel * out,
                  bottom: bottom,
                  child: Visibility(
                    visible: !keyboardOpen,
                    child: Opacity(
                      opacity: opacity,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // Drag vertikal 1:1; horizontal diabaikan (tetap nempel
                        // kanan). Tap tetap jalan (hanya drag vertikal yang
                        // masuk arena gesture).
                        onVerticalDragStart: (_) => HapticFeedback.lightImpact(),
                        onVerticalDragUpdate: (d) {
                          setState(() => _dragDy += -d.delta.dy);
                        },
                        onVerticalDragEnd: (_) => unawaited(_savePos()),
                        child: RepaintBoundary(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              // Semi-transparan polos (tanpa blur).
                              color: AppTheme.bgCard.withValues(alpha: 0.78),
                              // Hanya sisi KIRI yang membulat; kanan rata.
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(24),
                              ),
                              border: Border.all(
                                color: AppTheme.divider.withValues(alpha: 0.5),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 10,
                                  offset: const Offset(-2, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _item(
                                  icon: Icons.dynamic_feed_rounded,
                                  active: timelineActive,
                                  tooltip: s.navTimeline,
                                  semanticLabel: s.quickMenuTimeline,
                                  reduceMotion: reduceMotion,
                                  onTap: () => _tap(() async {
                                    ref.read(navProvider.notifier).goTo(2);
                                  }),
                                ),
                                SizedBox(height: _gap),
                                _item(
                                  icon: Icons.public_rounded,
                                  active: widget.roomActive,
                                  tooltip: s.titleRooms,
                                  semanticLabel: s.quickMenuGlobalRoom,
                                  reduceMotion: reduceMotion,
                                  pulse: _pulse,
                                  onTap: () => _tap(widget.onOpenRoom),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _item({
    required IconData icon,
    required bool active,
    required String tooltip,
    required String semanticLabel,
    required bool reduceMotion,
    required VoidCallback onTap,
    Animation<double>? pulse,
  }) {
    final tint = active ? AppTheme.primary : AppTheme.textSecondary;
    Widget body = Container(
      width: _btn,
      height: _btn,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? AppTheme.primary.withValues(alpha: 0.12) : null,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(22),
        ),
      ),
      child: Icon(icon, size: 22, color: tint),
    );
    // Ikon Global Room "bernapas" halus saat idle (isyarat bisa diketuk),
    // tapi hanya kalau animasi tidak dimatikan user.
    if (pulse != null && !reduceMotion) {
      body = FadeTransition(
        opacity: Tween<double>(begin: 0.72, end: 1.0).animate(
          CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
        ),
        child: body,
      );
    }
    return Semantics(
      button: true,
      selected: active,
      label: semanticLabel,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(left: Radius.circular(22)),
          ),
          child: body,
        ),
      ),
    );
  }
}
