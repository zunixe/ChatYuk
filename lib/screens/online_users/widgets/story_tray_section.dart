import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../core/perf/perf_probe.dart';
import '../../../models/story_model.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/phone_verify_provider.dart';
import '../../../providers/riverpod/story_provider.dart';
import '../../../widgets/verified_badge.dart';
import 'story_tray.dart';

/// Tray story horizontal di bawah AppBar "Pengguna Online".
///
/// Slot 0 = avatar sendiri (tap → sheet "Status kamu", long-press → zoom foto),
/// lalu tile "+" bila belum punya story, lalu tile story. Perilaku persis
/// seperti sebelumnya; hanya dipindah keluar dari layar agar layar ramping.
class StoryTraySection extends ConsumerStatefulWidget {
  final Uint8List? Function(String b64) resolveOwnAvatar;
  final ImageProvider Function(Uint8List bytes) imageForBytes;
  final String myAvatar;
  final String myNickname;
  final bool myRegistered;
  final String myStatus;
  final bool invisible;
  final bool uploadingAvatar;

  final VoidCallback onShowMyStatus;
  final void Function(String b64, Color bgColor, String initial) onAvatarZoom;
  final VoidCallback onPickAndUploadAvatar;
  final VoidCallback onOpenStoryComposer;
  final void Function(List<StoryTrayItem> items, int index) onOpenViewer;

  const StoryTraySection({
    super.key,
    required this.resolveOwnAvatar,
    required this.imageForBytes,
    required this.myAvatar,
    required this.myNickname,
    required this.myRegistered,
    required this.myStatus,
    required this.invisible,
    required this.uploadingAvatar,
    required this.onShowMyStatus,
    required this.onAvatarZoom,
    required this.onPickAndUploadAvatar,
    required this.onOpenStoryComposer,
    required this.onOpenViewer,
  });

  @override
  ConsumerState<StoryTraySection> createState() => _StoryTraySectionState();
}

class _StoryTraySectionState extends ConsumerState<StoryTraySection> {
  @override
  Widget build(BuildContext context) {
    // PERF: dulu `ctx.watch<StoryProvider>()` dengan ctx = context SCREEN →
    // seluruh halaman Online ikut rebuild tiap StoryProvider notify. Bungkus
    // Consumer sempit: HANYA tray ini yang rebuild saat story berubah.
    final sp = ref.watch(storyProvider);
    PerfProbe.buildCount('Story.tray');
    final s = ref.watch(localeProvider).s;
    return _content(context, sp, s);
  }

  Widget _content(BuildContext context, StoryState sp, S s) {
    // Hanya item berisi slide (slideCount>0) yang tampil & bisa dibuka.
    final items = sp.tray.where((t) => t.slideCount > 0).toList();
    // Anon juga bisa bikin story (dipaksa public) → tile + selalu tampil.
    const showOwnTile = true;
    final showAdd = showOwnTile && !items.any((t) => t.own);
    // Tinggi = isi tile (114 + 2 + label ~12 = 128) + 4 slack — tanpa
    // ini ada 20px kosong antara tulisan Tambah dan filter di bawahnya.
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: 1 + items.length + (showAdd ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          // Slot 0 = avatar sendiri (ikut scroll seperti IG).
          if (i == 0) {
            return _ownAvatarTile(s);
          }
          final j = i - 1;
          // Slot berikutnya = tile "+" kalau belum punya story sendiri.
          if (showAdd && j == 0) {
            return OwnAddTile(onTap: widget.onOpenStoryComposer);
          }
          final it = items[showAdd ? j - 1 : j];
          final idx = showAdd ? j - 1 : j;
          // KEY berbasis identitas (authorId + thumbPath): State tile
          // di-reuse saat urutan berubah / tray refresh, bukan dibuang lalu
          // dibuat ulang (dulu: thumbnail "keload ulang" tiap refresh karena
          // State baru mulai dari _thumb=null). Ganti slide → thumbPath
          // berubah → key berubah → State baru ambil thumb baru (benar).
          return StoryTrayTile(
            key: ValueKey('story_${it.authorId}_${it.thumbPath}'),
            item: it,
            // Badge "+" di tile sendiri untuk tambah slide baru —
            // buka composer (sama seperti tombol + di AppBar).
            isOwnWithAdd: showOwnTile && it.own,
            onTap: () => widget.onOpenViewer(items, idx),
            onAddTap: (showOwnTile && it.own) ? widget.onOpenStoryComposer : null,
          );
        },
      ),
    );
  }

  Widget _ownAvatarTile(S s) {
    final myAvatar = widget.myAvatar;
    final myNickname = widget.myNickname;
    final myRegistered = widget.myRegistered;
    final myStatus = widget.myStatus;
    final invisible = widget.invisible;
    // Tile avatar sendiri TETAP di tengah tray (vertikal) — Center
    // mengembalikan posisi tengah seperti semula.
    return Center(
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  // Tap avatar sendiri → sheet "Status kamu" (status + siapa
                  // yang bisa melihat). Zoom foto tetap via long-press.
                  onTap: widget.onShowMyStatus,
                  onLongPress: () {
                    final b64 = myAvatar;
                    final init = (myNickname.isEmpty ? '?' : myNickname)[0]
                        .toUpperCase();
                    widget.onAvatarZoom(b64, AppTheme.primary, init);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Builder(
                      builder: (_) {
                        final b64 = myAvatar;
                        final bytes = widget.resolveOwnAvatar(b64);
                        // Huruf inisial HANYA kalau memang tidak ada
                        // avatar (string kosong). Selama bytes belum
                        // siap → lingkaran tint polos, tanpa flash "S".
                        final showInitial = b64.isEmpty;
                        return CircleAvatar(
                          radius: 27,
                          backgroundColor: AppTheme.primary.withValues(
                            alpha: 0.15,
                          ),
                          // Di-cap (54px fisik) — jangan decode avatar
                          // full-res untuk lingkaran kecil.
                          backgroundImage: bytes != null
                              ? widget.imageForBytes(bytes)
                              : null,
                          child: showInitial
                              ? Text(
                                  (myNickname.isEmpty ? '?' : myNickname)[0]
                                      .toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: AppGlyph.avatarInitial(54),
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  // Dot status diri sendiri (kiri-bawah) — kamera upload di
                  // kanan-bawah, tidak bertabrakan. Ghost mode → ikon 👻
                  // supaya beda jelas dari online biasa.
                  left: -2,
                  bottom: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: invisible
                          ? AppTheme.bgCard
                          : AppTheme.statusColor(myStatus),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: invisible
                        ? const Center(
                            child: Text('👻',
                                style: TextStyle(fontSize: AppGlyph.nano)),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: widget.uploadingAvatar
                        ? null
                        : widget.onPickAndUploadAvatar,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 3),
                        ],
                      ),
                      child: widget.uploadingAvatar
                          ? Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppTheme.primary,
                              ),
                            )
                          : Icon(
                              Icons.camera_alt,
                              color: AppTheme.primary,
                              size: 11,
                            ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      myNickname,
                      style: AppText.bodyStrong.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (myRegistered) ...[
                      const SizedBox(width: 2),
                      VerifiedBadge(
                        verified: ref.watch(
                          phoneVerifyProvider.select((p) => p.verified),
                        ),
                        size: 13,
                        tooltip: s.phoneVerifiedBadge,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
