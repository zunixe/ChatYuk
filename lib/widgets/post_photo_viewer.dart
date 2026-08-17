import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../services/post_photo_cache.dart';
import 'private_chat_message.dart';

/// Viewer foto post — popup smooth (fade + scale), bukan halaman baru.
/// Multi foto: swipe kiri/kanan + counter, zoom pinch, full-res lazy per foto.
class PostPhotoViewer {
  static void show(
    BuildContext context, {
    required List<String> paths,
    required List<Uint8List> thumbs,
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
        initialIndex: initialIndex,
      ),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ViewerBody extends StatefulWidget {
  final List<String> paths;
  final List<Uint8List> thumbs;
  final int initialIndex;
  const _ViewerBody({
    required this.paths,
    required this.thumbs,
    required this.initialIndex,
  });

  @override
  State<_ViewerBody> createState() => _ViewerBodyState();
}

class _ViewerBodyState extends State<_ViewerBody> {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
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
                thumb: widget.thumbs[i],
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
          ],
        ),
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  final String path;
  final Uint8List thumb;
  const _ViewerPage({required this.path, required this.thumb});

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  Uint8List? _fullBytes;

  @override
  void initState() {
    super.initState();
    _loadFull();
  }

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
    return Stack(
      children: [
        Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
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
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
              ),
            ),
          ),
      ],
    );
  }
}