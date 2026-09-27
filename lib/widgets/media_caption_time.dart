import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Caption + jam di bawah media (foto/video/maps) dengan aturan SAMA seperti
/// bubble teks: caption pendek → caption di kiri, jam **rata kanan sejajar
/// tepi media** pada baris yang sama; caption panjang → caption penuh lalu jam
/// di baris bawah, rata kanan. Jarak caption↔jam konsisten (6px + jam turun
/// 3px) supaya tinggi bubble seragam dengan chat teks.
///
/// Berbeda dengan `CaptionWithTime` (jam nempel di ujung caption), widget ini
/// mengunci jam ke tepi kanan selebar media — jadi jam sejajar tepi kanan
/// video/maps/foto, bukan menggantung di tengah.
class MediaCaptionTime extends StatelessWidget {
  /// Caption tak kosong (panggil hanya bila ada).
  final String text;

  /// Jam kirim ("" = tidak tampil, hanya caption).
  final String timeStr;

  /// Gaya caption (mis. `AppText.chatBody`).
  final TextStyle textStyle;

  /// Gaya jam (biasanya `chatTime` + `textSecondary`).
  final TextStyle timeStyle;

  /// Centang dibaca (pengirim / monitor admin).
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;

  /// Jarak kiri untuk TEKS caption (jam tetap rata kanan selebar media).
  final double leftInset;

  const MediaCaptionTime({
    super.key,
    required this.text,
    required this.timeStr,
    required this.textStyle,
    required this.timeStyle,
    this.showChecks = false,
    this.isPending = false,
    this.isQueued = false,
    this.isRead = false,
    this.leftInset = 0,
  });

  Widget _timeRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(timeStr, style: timeStyle),
        if (showChecks) ...[
          const SizedBox(width: 3),
          Icon(
            (isPending || isQueued) ? Icons.done : Icons.done_all,
            size: 12,
            color: (!isQueued && !isPending && isRead)
                ? AppTheme.primary
                : AppTheme.textSecondary,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tanpa jam: caption polos.
    if (timeStr.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: leftInset),
        child: Text(text, style: textStyle),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width * 0.8;
        final dir = Directionality.of(context);
        final tp = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          maxLines: 1,
          textDirection: dir,
        )..layout();
        final timeTp = TextPainter(
          text: TextSpan(text: timeStr, style: timeStyle),
          textDirection: dir,
        )..layout();
        final timeRowW = timeTp.width + 6 + (showChecks ? 15.0 : 0);
        // Muat sebaris: [caption] ...spacer... [jam rata kanan], jam turun 3px.
        final singleLine = !text.contains('\n') &&
            leftInset + tp.width + timeRowW <= available;
        if (singleLine) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: EdgeInsets.only(left: leftInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (available - leftInset - timeRowW)
                        .clamp(0.0, available),
                  ),
                  child: Text(
                    text,
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Spacer → jam menempel tepi kanan (rata kanan sejajar media).
              const Spacer(),
              Transform.translate(
                offset: const Offset(0, 3),
                child: _timeRow(),
              ),
            ],
          );
        }
        // Panjang: caption penuh, jam di baris bawah, rata kanan (atas 2).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(left: leftInset),
              child: Text(text, style: textStyle),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: _timeRow(),
              ),
            ),
          ],
        );
      },
    );
  }
}
