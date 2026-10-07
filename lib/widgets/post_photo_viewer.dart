import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../providers/riverpod/locale_provider.dart';
import '../core/cache/post_photo_cache.dart';
import 'private_chat_message.dart';
import '../config/theme.dart';

/// Viewer foto post — popup smooth (fade + scale), bukan halaman baru.
/// Multi foto: swipe kiri/kanan + counter, zoom pinch, full-res lazy per foto.
class PostPhotoViewer {
  static void show(
    BuildContext context, {
    required List<String> paths,
    required List<Uint8List> thumbs,
    List<double?> aspects = const [],
    int initialIndex = 0,
  }) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.95),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _ViewerBody(
        paths: paths,
        thumbs: thumbs,
        aspects: aspects,
        initialIndex: initialIndex,
      ),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.92,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }
}

class _ViewerBody extends ConsumerStatefulWidget {
  final List<String> paths;
  final List<Uint8List> thumbs;
  final List<double?> aspects;
  final int initialIndex;
  const _ViewerBody({
    required this.paths,
    required this.thumbs,
    required this.aspects,
    required this.initialIndex,
  });

  @override
  ConsumerState<_ViewerBody> createState() => _ViewerBodyState();
}

class _ViewerBodyState extends ConsumerState<_ViewerBody> {
  late final int _safeInitial =
      widget.paths.isEmpty ? 0 : widget.initialIndex.clamp(0, widget.paths.length - 1);
  late final PageController _page = PageController(initialPage: _safeInitial);
  late int _index = _safeInitial;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _page,
              itemCount: widget.paths.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _ViewerPage(
                path: widget.paths[i],
                thumb: i < widget.thumbs.length ? widget.thumbs[i] : Uint8List(0),
                aspect: i < widget.aspects.length ? widget.aspects[i] : null,
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: s.btnClose,
              ),
            ),
            if (widget.paths.length > 1)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_index + 1}/${widget.paths.length}',
                    style: AppText.micro.copyWith(color: Colors.white),
                  ),
                ),
              ),
            // Thumbnail strip bawah — klik untuk lompat ke foto itu.
            if (widget.paths.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      itemCount: widget.paths.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _page.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: i == _index
                                  ? Colors.white
                                  : Colors.white24,
                              width: i == _index ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              widget.thumbs[i],
                              fit: BoxFit.cover,
                              cacheWidth: 128,
                              gaplessPlayback: true,
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
    );
  }
}

class _ViewerPage extends StatefulWidget {
  final String path;
  final Uint8List thumb;
  /// Rasio asli (w/h) dari feed — kalau ada, area gambar dibatasi rasio ini
  /// supaya proporsi yang tampil = proporsi thumbnail yang diklik.
  final double? aspect;
  const _ViewerPage({required this.path, required this.thumb, this.aspect});

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  Uint8List? _fullBytes;
  final TransformationController _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    _loadFull();
  }

  @override
  void dispose() {
    // Keluarkan bitmap full-res dari ImageCache (pola PhotoViewerScreen) —
    // tiap buka-tutup viewer menumpuk bitmap sampai èvict LRU.
    final b = _fullBytes;
    if (b != null && b.isNotEmpty) {
      try {
        PaintingBinding.instance.imageCache.evict(MemoryImage(b));
      } catch (_) {}
    }
    _fullBytes = null;
    _transform.dispose();
    super.dispose();
  }

  // Pan hanya aktif saat sudah zoom — kalau skala 1.0, drag horizontal
  // dilempar ke PageView supaya swipe ganti foto tetap mulus.
  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.01;

  Future<void> _loadFull() async {
    try {
      final b64 = await PostPhotoCache.instance.full(widget.path);
      if (b64 == null || b64.isEmpty || !mounted) return;
      final bytes = await compute(b64ToBytes, b64);
      if (bytes == null || !mounted) return;
      setState(() => _fullBytes = bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _fullBytes ?? widget.thumb;
    final a = widget.aspect;
    Widget image = Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      // Cap 1600px seperti PhotoViewerScreen: full-res 12MP = ~48MB bitmap
      // native; 1600px cukup tajam untuk layar HP + zoom.
      cacheWidth: 1600,
    );
    // Rasio thumbnail diketahui → batasi area gambar supaya proporsi saat
    // dibuka = proporsi yang dilihat di feed (tidak "melebar" di layar).
    if (a != null && a > 0) {
      image = AspectRatio(aspectRatio: a, child: image);
    }
    return Stack(
      children: [
        Center(
          child: InteractiveViewer(
            transformationController: _transform,
            maxScale: 5,
            panEnabled: _zoomed,
            onInteractionUpdate: (_) => setState(() {}),
            child: image,
          ),
        ),
        if (_fullBytes == null)
          const Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
