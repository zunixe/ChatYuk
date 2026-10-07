import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/story_provider.dart';
import 'admin_story_tab.dart' show storyVisStyle;
import '../providers/riverpod/admin_provider.dart';

/// Viewer story mode ADMIN — tap kartu di tab Story.
///
/// Menampilkan slide seperti lihat story biasa (fullscreen, swipe/tap pindah)
/// TANPA fitur user (reply/like). Header menampilkan author + status
/// "terlihat oleh". Panel bawah: atur visibilitas (public/pengikut/teman/
/// private) + hapus permanen.
class AdminStoryViewerScreen extends ConsumerStatefulWidget {
  /// Daftar slide (map dari `admin_story_all`), urut terbaru-di-atas.
  final List<Map<String, dynamic>> stories;
  final int initialIndex;

  const AdminStoryViewerScreen({
    super.key,
    required this.stories,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<AdminStoryViewerScreen> createState() => _AdminStoryViewerScreenState();
}

class _AdminStoryViewerScreenState extends ConsumerState<AdminStoryViewerScreen> {
  late final PageController _page;
  late List<Map<String, dynamic>> _slides;
  late int _index;
  bool _busy = false;

  /// Cache byte gambar per slide id (hindari reload saat mundur).
  final Map<String, Uint8List> _img = {};

  @override
  void initState() {
    super.initState();
    _slides = List<Map<String, dynamic>>.from(widget.stories);
    _index = widget.initialIndex.clamp(0, (_slides.length - 1).clamp(0, 9999));
    _page = PageController(initialPage: _index);
    _loadCurrent();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _cur =>
      (_index >= 0 && _index < _slides.length) ? _slides[_index] : null;

  Future<void> _loadCurrent() async {
    final m = _cur;
    if (m == null) return;
    final id = '${m['id']}';
    if (_img.containsKey(id)) return;
    final path = '${m['image_path'] ?? ''}';
    if (path.isEmpty) return;
    try {
      final b = await ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier).thumbFor(path);
      if (mounted && b != null) setState(() => _img[id] = b);
    } catch (_) {}
  }

  Future<void> _setVisibility(String state) async {
    final m = _cur;
    if (m == null || _busy) return;
    setState(() => _busy = true);
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final ok = await admin.setStoryVisibility('${m['id']}', state);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        // Update lokal agar badge/тext langsung berubah.
        final mm = Map<String, dynamic>.from(m);
        if (state == 'private') {
          mm['owner_only'] = true;
        } else {
          mm['owner_only'] = false;
          mm['visibility'] = state == 'public' ? 'everyone' : state;
        }
        _slides[_index] = mm;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? s.adminStoryVisibilitySaved : s.adminStoryVisibilityFail),
        backgroundColor: ok ? AppTheme.online : AppTheme.danger,
      ),
    );
  }

  Future<void> _deleteStory() async {
    final m = _cur;
    if (m == null || _busy) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.adminStoryDeleteConfirmTitle),
        content: Text(s.adminStoryDeleteConfirmMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.adminStoryDelete,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final success = await admin.deleteStoryAdmin('${m['id']}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? s.adminStoryDeleted : s.adminStoryDeleteFail),
        backgroundColor: success ? AppTheme.online : AppTheme.danger,
      ),
    );
    setState(() {
      _busy = false;
      _slides.removeAt(_index);
      if (_slides.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (_index >= _slides.length) _index = _slides.length - 1;
      _page.jumpToPage(_index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    if (_slides.isEmpty) return const SizedBox.shrink();
    final m = _cur!;
    final style = storyVisStyle(m, s);
    final state = style.key;
    final name = '${m['author_name'] ?? 'Anon'}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _page,
              itemCount: _slides.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _loadCurrent();
              },
              itemBuilder: (_, i) => _AdminSlide(
                data: _slides[i],
                bytes: _img['${_slides[i]['id']}'],
                onVerticalClose: () => Navigator.pop(context),
              ),
            ),
            // Header: author + status "terlihat oleh" + tutup
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                color: Colors.black38,
                child: Row(
                  children: [
                    Icon(style.icon, size: 16, color: style.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodyStrong.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${s.adminStoryVisibleTo}: ${s.adminStoryVisibleFor(state)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.micro.copyWith(
                              color: style.color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
            // Panel bawah: atur visibilitas + hapus
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.fromLTRB(
                  12,
                  10,
                  12,
                  10 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.adminStorySetVisibility,
                      style: AppText.label.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _visBtn(s, state, 'public', AppTheme.online,
                            Icons.public, s.adminStoryFilterPublic),
                        _visBtn(s, state, 'followers', AppTheme.accent,
                            Icons.group_rounded, s.adminStoryFilterFollowers),
                        _visBtn(s, state, 'friends', AppTheme.female,
                            Icons.favorite_rounded, s.adminStoryFilterFriends),
                        _visBtn(s, state, 'private', AppTheme.danger,
                            Icons.lock, s.adminStoryFilterPrivate),
                        // Hapus permanen
                        InkWell(
                          onTap: _busy ? null : _deleteStory,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.danger.withValues(alpha: 0.7),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.delete_outline,
                                    size: 14, color: AppTheme.danger),
                                const SizedBox(width: 4),
                                Text(
                                  s.adminStoryDelete,
                                  style: AppText.label
                                      .copyWith(color: AppTheme.danger),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visBtn(
    S s,
    String current,
    String value,
    Color color,
    IconData icon,
    String label,
  ) {
    final active = current == value;
    return InkWell(
      onTap: _busy ? null : () => _setVisibility(value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color : color.withValues(alpha: 0.5),
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: AppText.label.copyWith(color: color)),
            if (active) ...[
              const SizedBox(width: 4),
              Icon(Icons.check, size: 13, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminSlide extends StatelessWidget {
  final Map<String, dynamic> data;
  final Uint8List? bytes;
  final VoidCallback onVerticalClose;
  const _AdminSlide({
    required this.data,
    required this.bytes,
    required this.onVerticalClose,
  });

  /// Kotak foto — SAMA persis dengan viewer story user (WYSIWYG):
  /// top = padding.top + 60, bottom = 68, lebar penuh; rounded 18 cover.
  Rect _storyRect(BuildContext ctx) {
    final mq = MediaQuery.of(ctx);
    final top = mq.padding.top + 60;
    const bottom = 68.0;
    final h = mq.size.height - top - bottom;
    return Rect.fromLTWH(0, top, mq.size.width, h);
  }

  @override
  Widget build(BuildContext context) {
    final b = bytes;
    final rect = _storyRect(context);
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) onVerticalClose();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Positioned.fromRect(
            rect: rect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: b == null
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    )
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.memory(
                        b,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        // Cap decode (hemat memori, tetap tajam).
                        cacheWidth: 1080,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
