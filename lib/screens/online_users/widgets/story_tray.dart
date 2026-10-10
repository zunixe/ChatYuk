import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/cache/media_disk_cache.dart';
import '../../../models/story_model.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/storage_provider.dart';
import '../../../providers/riverpod/story_provider.dart';

/// Tile story di tray "Pengguna Online" (thumbnail + badge + mute sheet).
class StoryTrayTile extends StatefulWidget {
  final StoryTrayItem item;
  final VoidCallback onTap;
  final bool isOwnWithAdd;
  final VoidCallback? onAddTap;

  const StoryTrayTile({
    super.key,
    required this.item,
    required this.onTap,
    this.isOwnWithAdd = false,
    this.onAddTap,
  });

  @override
  State<StoryTrayTile> createState() => _StoryTrayTileState();
}

class _StoryTrayTileState extends State<StoryTrayTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    // SINKRON dulu: kalau thumbnail sudah ada di RAM/disk (sesi sebelumnya,
    // atau tile lain author sama), frame pertama LANGSUNG terisi — tidak
    // "keload ulang" seperti cold start sebelumnya. `warmThumb` mengisi RAM
    // provider dari disk (pola sama dengan AvatarB64Service) sehingga state
    // widget tidak lagi satu-satunya tempat menyimpan hasil.
    final sp = ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier);
    sp.warmThumb(widget.item.thumbPath);
    _thumb = sp.thumbCached(widget.item.thumbPath);
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final p = widget.item.thumbPath;
    if (p.isEmpty) return;
    if (ProviderScope.containerOf(context, listen: false).read(storageProvider).isAvatarPath(p)) return;
    // Sudah punya thumbnail (sync hit / didUpdateWidget) → tidak perlu ulang.
    if (_thumb != null) return;
    // Tunggu prewarm disk dulu — kalau ternyata ADA di disk, ambil sinkron
    // tanpa network (ini yang membuat tampil persisten seperti avatar).
    try {
      await MediaDiskCache.instance.waitReady();
    } catch (_) {}
    // ANTI-BLINK FOTO ORANG LAIN: selama menunggu di atas, tile bisa
    // didaur-ulang untuk item lain (didUpdateWidget → path baru). Tanpa cek
    // ini, hasil path LAMA menimpa tile baru → thumbnail orang lain sempat
    // tampil sekilas. Pola sama seperti guard uid di _AsyncAvatarState.
    if (!mounted || widget.item.thumbPath != p) return;
    final sp = ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier);
    if (sp.warmThumb(p)) {
      final cached = sp.thumbCached(p);
      if (mounted && widget.item.thumbPath == p && cached != null) {
        setState(() => _thumb = cached);
      }
      return;
    }
    try {
      final b = await sp.thumbFor(p);
      if (mounted &&
          widget.item.thumbPath == p &&
          b != null &&
          b.isNotEmpty) {
        setState(() => _thumb = b);
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant StoryTrayTile old) {
    super.didUpdateWidget(old);
    // Path berganti (slide baru) → ambil yang baru; kalau sama, biarkan.
    if (old.item.thumbPath != widget.item.thumbPath) {
      final sp = ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier);
      sp.warmThumb(widget.item.thumbPath);
      _thumb = sp.thumbCached(widget.item.thumbPath);
      _loadThumb();
    }
  }

  void _showMuteSheet() {
    final it = widget.item;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                it.muted
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppTheme.primary,
              ),
              title: Text(it.muted ? s.storyUnmute : s.storyMute),
              onTap: () async {
                Navigator.pop(ctx);
                final sp = ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier);
                final ok = await sp.toggleStoryMute(it.authorId, !it.muted);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? s.storyMuted : s.storyUnmuted),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    // Dibisukan → abu transparan TANPA ring (ala IG), walau belum dilihat.
    // Belum dilihat → ring gradient ungu-biru. Sudah dilihat → border
    // PUTIH 2px + shadow, sama seperti avatar di header.
    final seen = !it.hasUnseen || it.muted;
    // RepaintBoundary: tile lain tidak ikut repaint saat satu thumbnail
    // selesai dimuat (tray panjang = scroll lebih mulus).
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        // Tahan = benamkan/tampilkan lagi (kecuali tile sendiri).
        onLongPress: it.own ? null : _showMuteSheet,
        child: Opacity(
          opacity: it.muted ? 0.45 : 1,
          child: SizedBox(
          width: 67,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 67,
                    height: 114,
                    padding: seen ? EdgeInsets.zero : const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      gradient: seen
                          ? null
                          : const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF9C27B0), AppTheme.primary],
                            ),
                      border: seen
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: seen
                          ? [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _thumb != null
                          ? Image.memory(
                              _thumb!,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              // Decode kecil (kotak foto 62x109, x2 density) —
                              // rasio 124:218 = 0.569 sama dengan tile agar
                              // tidak ada crop tambahan saat raster.
                              cacheWidth: 124,
                              cacheHeight: 218,
                            )
                          // Video tanpa poster → ikon video (bukan inisial
                          // nama yang membingungkan).
                          : it.hasVideo
                          ? const Center(
                              child: Icon(
                                Icons.videocam_rounded,
                                color: Colors.white54,
                                size: 26,
                              ),
                            )
                          : Center(
                              child: Text(
                                it.authorName.isNotEmpty
                                    ? it.authorName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: AppGlyph.avatarInitial(64),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Badge video: tile berisi slide mp4.
                  if (it.hasVideo && !widget.isOwnWithAdd)
                    const Positioned(
                      left: 4,
                      bottom: 4,
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  if (widget.isOwnWithAdd)
                    Positioned(
                      // DI DALAM bounds tile (right:2, bottom:2) — dulu -3
                      // (di luar tile) sehingga tidak pernah bisa di-tap.
                      right: 2,
                      bottom: 2,
                      // Badge "+" punya handler sendiri (buka composer) —
                      // lebih dalam dari GestureDetector tile → menang arena.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onAddTap ?? widget.onTap,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 67,
                child: Text(
                  it.own
                      ? ProviderScope.containerOf(context, listen: false).read(localeProvider).s.storyMine
                      : it.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppText.micro.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Tile "+" milik sendiri saat belum punya story aktif.
class OwnAddTile extends StatelessWidget {
  final VoidCallback onTap;
  const OwnAddTile({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 67,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 67,
              height: 114,
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Icon(
                Icons.add,
                size: AppGlyph.md,
                color: AppTheme.primary,
              ),
            ),
            // Label "Tambah" tepat 2px di bawah card — sama seperti label
            // nama di tile story, TANPA gradient shadow.
            const SizedBox(height: 2),
            Text(
              ProviderScope.containerOf(context, listen: false).read(localeProvider).s.storyAddToStory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.micro.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
