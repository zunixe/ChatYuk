import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../providers/riverpod/avatar_provider.dart';
import '../../../widgets/user_avatar.dart';

/// Avatar kotak (radius 8) untuk panel admin — memakai widget avatar
/// MODULAR [UserAvatar] untuk render foto (decode isolate + cap + anti-kedip),
/// sehingga tidak lagi menyalin logika decode/cache sendiri.
///
/// Bytes di-resolve lewat [AvatarProvider] (RAM→disk→network, RPC ber-privacy)
/// lalu dioper apa adanya ke [UserAvatar]. Tap → dialog zoom.
class AdminAvatarCircle extends StatefulWidget {
  final String uid;
  final String name;
  final Color color;
  const AdminAvatarCircle({
    super.key,
    required this.uid,
    required this.name,
    required this.color,
  });

  @override
  State<AdminAvatarCircle> createState() => AdminAvatarCircleState();
}

class AdminAvatarCircleState extends State<AdminAvatarCircle> {
  /// Sumber avatar (base64) untuk diteruskan ke [UserAvatar]. '' = inisial.
  String _src = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // ANTI-KEDIP: baca cache RAM sinkron dulu (frame pertama langsung avatar),
    // baru resolve async bila belum ada (pola ProfileAvatar).
    try {
      final sync = ProviderScope.containerOf(context, listen: false)
          .read(avatarProvider)
          .cachedSync(widget.uid);
      if (sync != null && sync.isNotEmpty) {
        _src = sync;
        _loaded = true;
      }
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    if (widget.uid.isEmpty) return;
    if (_loaded && _src.isNotEmpty) return; // sudah dari cache sinkron.
    try {
      final b64 = await ProviderScope.containerOf(context, listen: false).read(avatarProvider).get(widget.uid);
      if (!mounted) return;
      setState(() {
        _src = b64;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _zoom() async {
    // Ambil bytes dari cache render modular kalau sudah ada (dipakai kartu),
    // else resolve ulang dari provider.
    var bytes = cachedUserAvatarBytes(widget.uid);
    if (bytes == null) {
      try {
        final b64 = _src.isNotEmpty
            ? _src
            : await ProviderScope.containerOf(context, listen: false).read(avatarProvider).get(widget.uid);
        if (b64.isNotEmpty) bytes = base64Decode(b64);
      } catch (_) {}
    }
    if (!mounted) return;
    showDialog<void>(
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
                child: bytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        // Cap 1080px: dialog zoom tidak butuh full-res.
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          cacheWidth: 1080,
                        ),
                      )
                    : CircleAvatar(
                        radius: 90,
                        backgroundColor: widget.color,
                        child: Text(
                          widget.name.isNotEmpty
                              ? widget.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
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
      if (bytes != null && bytes.isNotEmpty) {
        try {
          PaintingBinding.instance.imageCache.evict(MemoryImage(bytes));
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _src.isNotEmpty;
    return GestureDetector(
      onTap: _zoom,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: hasPhoto
              ? Colors.transparent
              : widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: _loaded
            ? UserAvatar(
                key: ValueKey(widget.uid),
                uid: widget.uid,
                avatarB64: _src,
                initial: widget.name.isNotEmpty
                    ? widget.name[0].toUpperCase()
                    : '?',
                color: widget.color,
                borderRadius: 8,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
