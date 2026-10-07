import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/connectivity_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../config/theme.dart';

/// Banner "tidak ada koneksi" global — tampil di atas semua layar via
/// MaterialApp.builder saat connectivity none. Non-blocking (IgnorePointer
/// saat hidden) + animasi slide agar tidak mengganggu.
class OfflineBanner extends ConsumerWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ref.watch(connectivityProvider) — hanya bool `online`. Perubahan status
    // lain tak ada (state = bool) → subtree hanya rebuild saat online berubah.
    final online = ref.watch(connectivityProvider);
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: online,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              offset: online ? const Offset(0, -1.2) : Offset.zero,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: AppTheme.danger,
                  elevation: 4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Builder(builder: (ctx) {
                        final s = ref.watch(localeProvider).s;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            s.offlineBanner,
                            style: AppText.caption.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
