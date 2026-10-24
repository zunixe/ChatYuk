part of 'chat_composer_input.dart';

// Widget bantu composer: _ForceRebuild (pemicu rebuild area mic/send) dan
// _AttachPanelSlide (animasi panel lampiran). Dipisah dari
// chat_composer_input.dart karena file utama menembus 1000 baris
// (REVIEW_2026-10-24 ARCH-01/R-11). Perilaku tidak berubah.

/// Memaksa subtree rebuild saat [token] berubah, TANPA mengganti identity
/// elemen anak (tidak seperti key pada widget) — sehingga gesture
/// tahan-rekam pada `MicRecordButton` tidak terputus.
///
/// Dipakai untuk area tombol mic/send yang hidup di dalam
/// `ValueListenableBuilder<TextEditingValue>` (hanya mendengar teks):
/// memilih video/foto tidak mengubah teks, jadi tanpa pemicu tambahan
/// tombol TIDAK pernah berubah dari mic → send.
class _ForceRebuild extends InheritedWidget {
  final int token;
  const _ForceRebuild({required this.token, required super.child});

  @override
  bool updateShouldNotify(_ForceRebuild oldWidget) =>
      oldWidget.token != token;
}

/// Panel lampiran yang MUNCUL DARI BAWAH dan TURUN lagi saat ditutup.
///
/// Kenapa bukan sekadar `AnimatedSize` + `AnimatedSwitcher`: saat menutup,
/// switcher menumpuk child lama & baru sehingga `AnimatedSize` terus mengukur
/// tinggi MAKSIMUM → composer tidak ikut menyusut, lalu ruang kosong lenyap
/// mendadak (penutupan terasa tersendat; terukur: posisi composer tetap
/// selama animasi).
///
/// Di sini satu [AnimationController] menggerakkan tiga hal sekaligus:
///  - tinggi wadah  (0 → tinggi panel)  → composer naik/turun mulus,
///  - slide isi     (0.35 → 0 offset)   → isi naik dari bawah / turun,
///  - opacity       (0 → 1)             → memudar masuk/keluar.
class _AttachPanelSlide extends StatefulWidget {
  final bool open;
  final Widget child;
  const _AttachPanelSlide({required this.open, required this.child});

  @override
  State<_AttachPanelSlide> createState() => _AttachPanelSlideState();
}

class _AttachPanelSlideState extends State<_AttachPanelSlide>
    with SingleTickerProviderStateMixin {
  static const Duration _dur = Duration(milliseconds: 200);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _dur,
  );
  late final Animation<double> _curved = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.open) _c.value = 1;
  }

  @override
  void didUpdateWidget(_AttachPanelSlide old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tinggi asli panel diukur sekali (offstage) lalu dipakai sebagai target
    // tinggi wadah — agar animasi tinggi tidak bergantung layout anak.
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        final t = _curved.value; // 0..1
        if (t == 0) return const SizedBox.shrink();
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: t, // tinggi menyusut/tumbuh bersama animasi
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: FractionalTranslation(
                translation: Offset(0, 0.35 * (1 - t)),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
