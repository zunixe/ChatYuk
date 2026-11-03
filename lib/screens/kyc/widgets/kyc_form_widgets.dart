import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import 'kyc_camera_widgets.dart';

/// Kartu dasar section (latar card + padding konsisten).
class KycCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  const KycCard({super.key, required this.child, this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color ?? AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

/// Kartu langkah bernomor: bulatan nomor (✓ bila selesai) + judul + hint.
class KycStepCard extends StatelessWidget {
  final int number;
  final String title;
  final String hint;
  final bool done;
  final Widget child;

  const KycStepCard({
    super.key,
    required this.number,
    required this.title,
    required this.hint,
    required this.done,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => KycCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? kKycOk
                        : AppTheme.primary.withValues(alpha: 0.18),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '$number',
                          style: AppText.label.copyWith(color: AppTheme.primary),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: AppText.bodyStrong)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

/// Area foto: kosong → ikon + label; terisi → pratinjau + chip "Ulangi".
class KycPhotoTile extends StatelessWidget {
  final Uint8List? bytes;
  final IconData emptyIcon;
  final String tapLabel;
  final String retakeLabel;
  final bool busy;
  final double aspect;
  final VoidCallback onTap;

  const KycPhotoTile({
    super.key,
    required this.bytes,
    required this.emptyIcon,
    required this.tapLabel,
    required this.retakeLabel,
    required this.busy,
    required this.onTap,
    this.aspect = 1.586,
  });

  @override
  Widget build(BuildContext context) {
    final has = bytes != null;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: has ? kKycOk : AppTheme.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (has)
                      // MEMORY: thumbnail saja — bytes asli dikirim ke server.
                      Image.memory(bytes!, fit: BoxFit.cover, cacheWidth: 600)
                    else
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(emptyIcon, size: 40, color: AppTheme.textSecondary),
                            const SizedBox(height: 8),
                            Text(
                              tapLabel,
                              style: AppText.label
                                  .copyWith(color: AppTheme.primary),
                            ),
                          ],
                        ),
                      ),
                    if (has)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.refresh,
                                  size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                retakeLabel,
                                style: AppText.caption
                                    .copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Catatan berikon (hasil verifikasi / peringatan).
class KycNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const KycNote({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: AppText.caption.copyWith(color: color)),
            ),
          ],
        ),
      );
}

/// Tampilan status (pending/approved) — ikon + judul + penjelasan.
class KycStatusView extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const KycStatusView({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 14),
              Text(title, style: AppText.titleEmphasis),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style:
                    AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
}
