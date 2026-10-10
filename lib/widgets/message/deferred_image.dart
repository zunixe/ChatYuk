import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';

// Image yang belum di-load (pesan lama di luar window 50) — placeholder
// dengan auto-load di latar (screen memanggil fetchImage otomatis);
// tap = retry manual. Spinner saat fetch berjalan (feedback nyata,
// dulu: klik "tidak berefek" karena fetch gagal diam-diam).
class DeferredImage extends StatefulWidget {
  final Future<void> Function()? onTap;
  const DeferredImage({super.key, this.onTap});

  @override
  State<DeferredImage> createState() => _DeferredImageState();
}

class _DeferredImageState extends State<DeferredImage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    return GestureDetector(
      onTap: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onTap?.call();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: Container(
        width: 200,
        height: 120,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppTheme.primary,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: AppTheme.textSecondary, size: 22),
                  SizedBox(height: 4),
                  Text(
                    s.msgPhotoTapToLoad,
                    style: AppText.chatCaption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
