import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/riverpod/phone_verify_provider.dart';

/// Dialog verifikasi nomor HP via Telegram.
///
/// Menampilkan tombol "Verifikasi Sekarang" → membuka bot Telegram, lalu
/// menunggu status (polling di provider). Otomatis menutup saat verified.
///
/// Return `true` bila berhasil verified, else null/false.
Future<bool?> showPhoneVerifyDialog(BuildContext context, S s) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _PhoneVerifyDialog(s: s),
  );
}

class _PhoneVerifyDialog extends ConsumerStatefulWidget {
  final S s;
  const _PhoneVerifyDialog({required this.s});

  @override
  ConsumerState<_PhoneVerifyDialog> createState() => _PhoneVerifyDialogState();
}

class _PhoneVerifyDialogState extends ConsumerState<_PhoneVerifyDialog> {
  @override
  void initState() {
    super.initState();
    // Sinkronkan status terbaru saat dialog dibuka.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(phoneVerifyProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    ref.read(phoneVerifyProvider.notifier).stopPolling();
    super.dispose();
  }

  Future<void> _start() async {
    final s = widget.s;
    final code = await ref.read(phoneVerifyProvider.notifier).startAndOpen();
    if (!mounted) return;
    final msg = switch (code) {
      'rate_limited' => s.phoneVerifyRateLimited,
      'phone_empty' => s.phoneVerifyPhoneEmpty,
      'opened' => s.phoneVerifyOpened,
      _ => s.phoneVerifyFailed,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final st = ref.watch(phoneVerifyProvider);

    // Begitu terverifikasi → tutup dialog dengan hasil true.
    ref.listen(phoneVerifyProvider, (prev, next) {
      if (next.verified && mounted) {
        Navigator.of(context).pop(true);
      }
    });

    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: Text(s.phoneVerifyTitle, style: AppText.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.phoneVerifyDesc,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          if (st.busy) ...[
            const SizedBox(height: 16),
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: st.busy ? null : () => Navigator.pop(context),
          child: Text(s.phoneVerifyLater),
        ),
        FilledButton(
          onPressed: st.busy ? null : _start,
          child: Text(s.phoneVerifyBtn),
        ),
      ],
    );
  }
}
