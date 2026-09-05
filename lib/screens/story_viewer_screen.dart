import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/story_model.dart';
import '../providers/locale_provider.dart';
import '../providers/story_provider.dart';
import '../services/storage_photo_service.dart';
import '../services/media_disk_cache.dart';
import '../utils.dart';
import '../widgets/story_text_overlay.dart';

/// Cache RAM bytes slide (path → image) — bertahan antar slide/penonton
/// selama sesi viewer supaya mundur/maju tidak download ulang.
final Map<String, Uint8List> _slideBytesCache = {};

/// Viewer story fullscreen (gaya IG):
/// - Progress segmented atas (1 segmen per slide), auto-advance 5 detik.
/// - Hold = pause. Tap kanan/kiri = next/prev slide. Swipe vertikal = tutup.
/// - Horizontal PageView antar penonton (urutan tray).
/// - Slide milik sendiri: tombol hapus + tombol daftar penonton.
class StoryViewerScreen extends StatefulWidget {
  final List<StoryTrayItem> items;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late PageController _pageCtrl;
  late int _person;
  List<StorySlide> _slides = [];
  int _slide = 0;
  bool _loading = true;
  bool _paused = false;
  Timer? _autoTimer;
  final Map<String, Uint8List?> _localImg = {};

  static const _slideDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _person = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _person);
    _loadPerson();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  StoryTrayItem get _item => widget.items[_person];
  bool get _own => _item.own;

  Future<void> _loadPerson() async {
    _autoTimer?.cancel();
    setState(() {
      _loading = true;
      _slide = 0;
    });
    final sp = context.read<StoryProvider>();
    final slides = await sp.slidesFor(_item.authorId);
    if (!mounted) return;
    setState(() {
      _slides = slides;
      _loading = false;
    });
    if (slides.isEmpty) return;
    _markSeen();
    _startTimer();
    _preload(slides);
  }

  void _preload(List<StorySlide> slides) async {
    // Paralel (dulu sequential await — slide ke-N nunggu slide ke-1).
    await Future.wait(
      slides.where((sl) => !_localImg.containsKey(sl.imagePath)).map(
        (sl) async {
          _localImg[sl.imagePath] = await _bytes(sl.imagePath);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<Uint8List?> _bytes(String path) async {
    final cached = _slideBytesCache[path];
    if (cached != null) return cached;
    try {
      // Disk dulu (repeat view instan) — baru network + simpan disk.
      var b = MediaDiskCache.instance.readSync(path);
      b ??= await MediaDiskCache.instance.read(path);
      b ??= await StoragePhotoService.instance.downloadBytes(path);
      if (b != null && b.isNotEmpty) {
        _slideBytesCache[path] = b;
        if (_slideBytesCache.length > 60) {
          _slideBytesCache.remove(_slideBytesCache.keys.first);
        }
        unawaited(MediaDiskCache.instance.write(path, b));
      }
      return b;
    } catch (_) {
      return null;
    }
  }

  void _startTimer() {
    _autoTimer?.cancel();
    _paused = false;
    _autoTimer = Timer(_slideDuration, _next);
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _autoTimer?.cancel();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _startTimer();
  }

  void _next() {
    if (_slide < _slides.length - 1) {
      setState(() => _slide++);
      _markSeen();
      _startTimer();
    } else {
      _nextPerson();
    }
  }

  void _prev() {
    if (_slide > 0) {
      setState(() => _slide--);
      _startTimer();
    } else {
      _prevPerson();
    }
  }

  void _nextPerson() {
    if (_person < widget.items.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _prevPerson() {
    if (_person > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _markSeen() {
    if (_slide < _slides.length) {
      context
          .read<StoryProvider>()
          .markSeen(_slides[_slide].id, _item.authorId);
    }
  }

  Future<void> _deleteSlide() async {
    final s = context.read<LocaleProvider>().s;
    final sp = context.read<StoryProvider>();
    final ok = await sp.deleteSlide(_slides[_slide].id, _item.authorId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? s.storyDeleted : s.storyDeleteFail),
        backgroundColor: ok ? AppTheme.online : AppTheme.danger,
      ),
    );
    if (!ok) return;
    // Slide terakhir milik orang ini → tutup viewer; else muat ulang.
    if (_slides.length <= 1) {
      Navigator.pop(context);
    } else {
      sp.invalidateSlides(_item.authorId);
      _loadPerson();
    }
  }

  Future<void> _confirmDelete() async {
    final s = context.read<LocaleProvider>().s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.storyDeleteSlideTitle),
        content: Text(s.storyDeleteSlideMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnDelete,
              style: AppText.button
                  .copyWith(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) _deleteSlide();
  }

  Future<void> _showViewers() async {
    final s = context.read<LocaleProvider>().s;
    final sp = context.read<StoryProvider>();
    final slide = _slides[_slide];
    final viewers = await sp.fetchViewers(slide.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 20, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${s.storyViewersTitle} · ${viewers.length}',
                    style: AppText.bodyStrong,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.divider),
            if (viewers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.storyViewersEmpty,
                  style: AppText.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: viewers.length,
                  itemBuilder: (_, i) {
                    final v = viewers[i];
                    return ListTile(
                      dense: true,
                      leading: _viewerAvatar(v.avatar, v.nickname),
                      title: Text(v.nickname, style: AppText.bodyStrong),
                      subtitle: Text(
                        formatRelativeTime(
                          v.viewedAt.toLocal(),
                          isId: s.isId,
                        ),
                        style: AppText.bodySmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _viewerAvatar(String avatar, String nickname) {
    Uint8List? bytes;
    if (avatar.isNotEmpty &&
        !StoragePhotoService.instance.isAvatarPath(avatar)) {
      try {
        bytes = base64Decode(avatar);
      } catch (_) {}
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
      backgroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes != null
          ? null
          : Text(
              nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
              style: TextStyle(
                color: AppTheme.primary,
                fontSize: AppGlyph.avatarInitial(32),
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.items.length,
        onPageChanged: (i) {
          _person = i;
          _loadPerson();
        },
        itemBuilder: (_, i) => _buildPerson(i),
      ),
    );
  }

  Widget _buildPerson(int index) {
    if (index != _person) {
      // Halaman tetangga — render ringan (background saja).
      return Container(color: Colors.black);
    }
    final s = context.watch<LocaleProvider>().s;
    return GestureDetector(
      onTapDown: (_) => _pause(),
      onTapUp: (_) => _resume(),
      onLongPressStart: (_) => _pause(),
      onLongPressEnd: (_) => _resume(),
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null && d.primaryVelocity! > 300) {
          Navigator.pop(context);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Foto slide
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _slides.isEmpty
                  ? Center(
                      child: Text(
                        s.storyEmptyTray,
                        style: AppText.body
                            .copyWith(color: Colors.white54),
                      ),
                    )
                  : _buildSlide(),

          // ── Progress segmented atas ──
          if (_slides.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  for (int i = 0; i < _slides.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: i == _slides.length - 1 ? 0 : 4),
                        child: LinearProgressIndicator(
                          value: i < _slide
                              ? 1
                              : i == _slide
                                  ? 1
                                  : 0,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                              Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── Zona tap kanan/kiri — DI BAWAH baris tombol header supaya
          // tombol delete/close/penonton tetap bisa ditekan.
          if (!_loading && _slides.isNotEmpty) ...[
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _prev,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Header: nama penonton + waktu + tombol aksi ──
          // (DI ATAS zona tap — urutan Stack ini penting: tombol harus
          // menang hit-test dari zona next/prev.)
          if (_slides.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _own ? s.storyMine : _item.authorName,
                      style: AppText.bodyStrong.copyWith(
                          color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_slides.isNotEmpty)
                    Text(
                      formatRelativeTime(
                        _slides[_slide].createdAt.toLocal(),
                        isId: s.isId,
                      ),
                      style: AppText.caption
                          .copyWith(color: Colors.white54),
                    ),
                  const Spacer(),
                  // Aksi milik sendiri: penonton + hapus
                  if (_own && !_loading && _slides.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.visibility,
                          color: Colors.white, size: 20),
                      tooltip: s.storyViewersTitle,
                      onPressed: _showViewers,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white, size: 20),
                      tooltip: s.btnDelete,
                      onPressed: _confirmDelete,
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSlide() {
    final slide = _slides[_slide];
    final bytes = _localImg[slide.imagePath];
    return Center(
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.cover)
            else
              Container(color: Colors.white10),
            StoryTextOverlay(
              text: slide.textOverlay,
              x: slide.textX,
              y: slide.textY,
              colorIndex: slide.textColorIndex,
              sizeIndex: slide.textSizeIndex,
              scale: slide.textScale,
              rotation: slide.textRotation,
              withBg: slide.textBg,
            ),
          ],
        ),
      ),
    );
  }
}
