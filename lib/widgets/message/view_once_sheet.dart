import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';

/// Viewer FOTO SEKALI-LIHAT gaya GALERI: slide dari bawah (bottom sheet).
///
/// Dipakai private chat DAN grup/global room (satu widget bersama).
/// - Thumbnail tampil instan.
/// - Timer view-once ([countdown]) tetap tampil di kiri atas.
/// - [onClosed] dipanggil saat sheet ditutup (pemanggil memakai ini untuk
///   mengunci foto permanen pada mode "1x lihat").
///
/// CATATAN: TIDAK ada tombol HD di viewer — kualitas foto ditentukan saat
/// KIRIM (toggle HD di preview composer). Foto yang dikirim HD ya tampil HD,
/// yang standar ya standar.
Future<void> showViewOnceSheet({
  required BuildContext context,
  required Uint8List bytes,
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
      countdown: countdown,
      onClosed: onClosed,
    ),
  );
}

class _ViewOnceSheet extends StatefulWidget {
  final Uint8List bytes;
  final ValueNotifier<int>? countdown;
  final VoidCallback? onClosed;
  const _ViewOnceSheet({
    required this.bytes,
    this.countdown,
    this.onClosed,
  });

  @override
  State<_ViewOnceSheet> createState() => _ViewOnceSheetState();
}

class _ViewOnceSheetState extends State<_ViewOnceSheet> {
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

  /// String bilingual tanpa `ref` (State biasa).
  S get _s =>
      ProviderScope.containerOf(context, listen: false).read(localeProvider).s;

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final media = MediaQuery.sizeOf(context);
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
                              widget.bytes,
                              fit: BoxFit.contain,
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
}
