import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';

/// Warna status kamera KYC (siap = hijau, peringatan = oranye).
const kKycOk = Color(0xFF2ECC71);
const kKycWarn = Color(0xFFF5A623);

/// Preview kamera memenuhi layar (crop, bukan letterbox) — preview
/// `camera` berorientasi landscape, jadi lebar/tinggi ditukar di portrait.
class KycCameraPreview extends StatelessWidget {
  final CameraController controller;
  const KycCameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final ps = controller.value.previewSize;
    if (ps == null) return CameraPreview(controller);
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ps.height,
            height: ps.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

/// Overlay viewfinder: gelap di luar lubang (kartu / oval) + garis status.
class KycViewfinderPainter extends CustomPainter {
  /// true = oval wajah; false = kartu KTP (rasio ID-1 85,6 × 54 mm).
  final bool oval;
  final Color color;
  final double progress; // 0..1 → busur progres di sekeliling oval

  const KycViewfinderPainter({
    required this.oval,
    required this.color,
    this.progress = 0,
  });

  static Rect cardRect(Size size) {
    final w = size.width * 0.88;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: w,
      height: w / 1.586,
    );
  }

  static Rect ovalRect(Size size) => Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.40),
        width: size.width * 0.66,
        height: size.width * 0.66 * 1.3,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = oval ? ovalRect(size) : cardRect(size);
    final hole = oval
        ? (Path()..addOval(rect))
        : (Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14))));
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(hole, Offset.zero);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.62));

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (oval) {
      canvas.drawOval(rect, stroke..color = color.withValues(alpha: 0.5));
      if (progress > 0) {
        canvas.drawArc(
          rect.inflate(6),
          -1.5708,
          6.2832 * progress.clamp(0, 1),
          false,
          Paint()
            ..color = kKycOk
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
      }
      return;
    }
    // Kartu: sudut siku (gaya pemindai dokumen) — lebih jelas dari kotak penuh.
    const l = 28.0;
    final c = [
      [rect.topLeft, const Offset(l, 0), const Offset(0, l)],
      [rect.topRight, const Offset(-l, 0), const Offset(0, l)],
      [rect.bottomLeft, const Offset(l, 0), const Offset(0, -l)],
      [rect.bottomRight, const Offset(-l, 0), const Offset(0, -l)],
    ];
    stroke.strokeWidth = 4;
    for (final k in c) {
      canvas.drawLine(k[0], k[0] + k[1], stroke);
      canvas.drawLine(k[0], k[0] + k[2], stroke);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(KycViewfinderPainter old) =>
      old.color != color || old.progress != progress || old.oval != oval;
}

/// Pil teks instruksi di atas preview.
class KycHintPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const KycHintPill({
    super.key,
    required this.text,
    this.color = Colors.white,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Container(
          key: ValueKey(text),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppText.bodyStrong.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Tombol jepret bulat.
class KycShutterButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  const KycShutterButton({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled && !busy ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled ? Colors.white : Colors.white38,
              width: 4,
            ),
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: enabled ? Colors.white : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                ),
        ),
      );
}

/// Izin kamera ditolak — jelaskan + tombol ke pengaturan (dulu layar
/// langsung tertutup tanpa pesan).
class KycCameraPermissionView extends StatelessWidget {
  final S s;
  const KycCameraPermissionView({super.key, required this.s});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  size: 40, color: Colors.white70),
              const SizedBox(height: 14),
              Text(
                s.kycCamPermTitle,
                textAlign: TextAlign.center,
                style: AppText.bodyStrong.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                s.kycCamPermBody,
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: openAppSettings,
                child: Text(s.kycOpenSettings),
              ),
            ],
          ),
        ),
      );
}

/// Tombol tutup (kiri atas) untuk layar kamera.
class KycCloseButton extends StatelessWidget {
  const KycCloseButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.close, color: Colors.white, size: 24),
        onPressed: () => Navigator.pop(context),
      );
}
