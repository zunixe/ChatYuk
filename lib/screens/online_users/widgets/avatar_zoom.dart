import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Dialog zoom foto avatar (InteractiveViewer). Menampilkan foto bila ada
/// base64, atau lingkaran inisial bila tidak. Bitmap zoom di-evict dari
/// ImageCache saat dialog ditutup (pola PhotoViewerScreen).
void showAvatarZoomDialog(
  BuildContext context, {
  required String b64,
  required Color bgColor,
  required String initial,
}) {
  Uint8List? bytes;
  if (b64.isNotEmpty) {
    try {
      bytes = base64Decode(b64);
    } catch (_) {}
  }
  if (bytes == null && initial.isEmpty) return;
  final zoomBytes = bytes;
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: zoomBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      // Cap 1080px: dialog zoom tidak butuh full-res 12MP.
                      child: Image.memory(
                        zoomBytes,
                        fit: BoxFit.contain,
                        cacheWidth: 1080,
                      ),
                    )
                  : CircleAvatar(
                      radius: 90,
                      backgroundColor: bgColor,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppGlyph.xl,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    ),
  ).then((_) {
    // Keluarkan bitmap zoom dari ImageCache (pola PhotoViewerScreen).
    if (zoomBytes != null && zoomBytes.isNotEmpty) {
      try {
        PaintingBinding.instance.imageCache.evict(MemoryImage(zoomBytes));
      } catch (_) {}
    }
  });
}
