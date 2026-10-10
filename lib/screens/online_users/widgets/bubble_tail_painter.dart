import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Segitiga kecil (tail) untuk bubble pesan-terakhir di kartu user.
class BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isTop;
  BubbleTailPainter({required this.color, required this.isTop});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (isTop) {
      path.moveTo(size.width / 2 - 7, size.height);
      path.lineTo(size.width / 2 + 7, size.height);
      path.lineTo(size.width / 2, 0);
    } else {
      path.moveTo(size.width / 2 - 7, 0);
      path.lineTo(size.width / 2 + 7, 0);
      path.lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.1), 2, false);
    canvas.drawPath(path, paint);
    final border = Paint()
      ..color = AppTheme.divider.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
