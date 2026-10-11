import 'package:flutter/widgets.dart';

/// Lepas resource dialog/sheet SETELAH animasi tutupnya selesai.
///
/// Masalah (R2, insiden 2026-10-11): `ctrl.dispose()` di `finally` TEPAT
/// setelah `await showDialog` terlalu DINI — dialog masih membangun 1-2 frame
/// selama animasi dismiss, sehingga memakai controller yang sudah di-dispose
/// → assert "A TextEditingController was used after being disposed".
///
/// Solusi: tunda ke frame BERIKUTNYA via `addPostFrameCallback` (setelah
/// Overlay selesai menggambar). Semua kegagalan ditelan — dispose tak boleh
/// merusak UI.
void disposeAfterDialogFrame(List<ChangeNotifier?> notifiers) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final n in notifiers) {
      try {
        n?.dispose();
      } catch (_) {}
    }
  });
}
