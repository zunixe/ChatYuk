import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../core/media/native_image.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../chat_info_snack.dart';

/// Viewer FOTO SEKALI-LIHAT gaya GALERI: slide dari bawah (bottom sheet),
/// dengan tombol **HD** di kanan (muat resolusi penuh saat diketuk).
///
/// Dipakai private chat DAN grup/global room (satu widget bersama).
/// - Thumbnail tampil instan; HD dimuat on-demand lewat [fullLoader]
///   (`PhotoCache.load`), bukan di awal → buka viewer tetap ringan.
/// - Timer view-once ([countdown]) tetap tampil di kiri atas.
/// - [onClosed] dipanggil saat sheet ditutup (pemanggil memakai ini untuk
///   mengunci foto permanen pada mode "1x lihat").
Future<void> showViewOnceSheet({
  required BuildContext context,
  required Uint8List bytes,
  Future<String?> Function()? fullLoader,
  ValueNotifier<int>? countdown,
  VoidCallback? onClosed,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    // Slide dari bawah + bisa ditutup dengan menggeser turun (pola galeri).
    builder: (_) => _ViewOnceSheet(
      bytes: bytes,
      fullLoader: fullLoader,
      countdown: countdown,
      onClosed: onClosed,
    ),
  );
}

class _ViewOnceSheet extends StatefulWidget {
  final Uint8List bytes;
  final Future<String?> Function()? fullLoader;
  final ValueNotifier<int>? countdown;
  final VoidCallback? onClosed;
  const _ViewOnceSheet({
    required this.bytes,
    this.fullLoader,
    this.countdown,
    this.onClosed,
  });

  @override
  State<_ViewOnceSheet> createState() => _ViewOnceSheetState();
}

class _ViewOnceSheetState extends State<_ViewOnceSheet> {
  Uint8List? _hd;
  bool _loadingHd = false;
  bool _wantHd = false;

  @override
  void initState() {
    super.initState();
    widget.countdown?.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.countdown?.removeListener(_onTick);
    widget.onClosed?.call();
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  bool get _hasHd => _hd != null;

  /// String bilingual tanpa `ref` (State biasa).
  S get _s =>
      ProviderScope.containerOf(context, listen: false).read(localeProvider).s;

  /// Popup notifikasi kecil (tanpa BuildContext di luar build).
  void _snack(String text) => showChatSnack(context, text);

  /// Putar HD on/off. Saat pertama menyala, muat full-res sekali lalu cache.
  Future<void> _toggleHd() async {
    if (_hasHd) {
      setState(() => _wantHd = !_wantHd);
      return;
    }
    if (_loadingHd) return;
    final loader = widget.fullLoader;
    if (loader == null) {
      _snack(_s.viewOnceHdUnavailable);
      return;
    }
    setState(() => _loadingHd = true);
    // File full bisa BELUM selesai di-download (foto room = path storage) →
    // coba ulang terbatas (pola sama PhotoViewerScreen) supaya tak gagal diam.
    Uint8List? bytes;
    for (var attempt = 0; attempt < 3 && bytes == null; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: attempt * 2));
        if (!mounted) return;
      }
      try {
        final data = await loader();
        if (data == null || data.isEmpty) continue;
        bytes = await NativeImage.decodeBytes(data);
      } catch (_) {}
    }
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _loadingHd = false);
      _snack(_s.viewOnceHdUnavailable);
      return;
    }
    setState(() {
      _hd = bytes;
      _wantHd = true;
      _loadingHd = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final media = MediaQuery.sizeOf(context);
    final shown = _wantHd && _hasHd ? _hd! : widget.bytes;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: media.height * 0.88,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Handle geser (ala galeri).
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Bar atas: tutup (kiri) · timer · HD (kanan).
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: s.btnClose,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.timer, color: Colors.white70, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _timerText(s),
                        style: AppText.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      _hdButton(s),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: Colors.black,
                        child: Center(
                          child: InteractiveViewer(
                            maxScale: 5,
                            minScale: 1,
                            child: Image.memory(
                              shown,
                              fit: BoxFit.contain,
                              // Cap decode 1080px utk thumbnail; HD tanpa cap
                              // (pakai bytes asli dari cache full-res).
                              cacheWidth: _wantHd && _hasHd ? null : 1080,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white54,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _timerText(S s) {
    final c = widget.countdown;
    if (c == null) return '';
    final v = c.value;
    if (v <= 0) return s.viewOnceViewed;
    return '$v s';
  }

  /// Tombol HD di kanan: outline (belum HD) → spinner (memuat) → aktif (HD).
  Widget _hdButton(S s) {
    final active = _wantHd && _hasHd;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _loadingHd ? null : _toggleHd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppTheme.primary : Colors.white54,
          ),
        ),
        child: _loadingHd
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                'HD',
                style: AppText.label.copyWith(
                  color: active ? Colors.white : Colors.white70,
                ),
              ),
      ),
    );
  }
}
