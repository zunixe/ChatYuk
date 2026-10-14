import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/theme.dart';
import '../core/media/native_image.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import 'emoji_picker_sheet.dart';
import 'sticker_bubble.dart';
import 'sticker_editor.dart';
import 'sticker_packs.dart';

/// Sheet bersama **Emoji | Sticker** untuk composer chat (private & room).
///
/// Tab Sticker: impor dari GALERI (S3) → crop 512px PNG (ImageBridge) →
/// kirim. Grid = koleksi SERVER (tahan install ulang) + impor sesi ini.
class StickerEmojiSheet extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Future<void> Function(Uint8List stickerPngBytes) onSendSticker;
  /// Kirim stiker yang SUDAH ada di server (tanpa upload ulang).
  /// null = fallback download lalu [onSendSticker].
  final Future<void> Function(String stickerPath)? onSendStickerPath;
  const StickerEmojiSheet({
    super.key,
    required this.controller,
    required this.onSendSticker,
    this.onSendStickerPath,
  });

  @override
  ConsumerState<StickerEmojiSheet> createState() => _StickerEmojiSheetState();
}

class _StickerEmojiSheetState extends ConsumerState<StickerEmojiSheet> {
  // Bounded: preview sticker terbaru (bytes PNG) — bukan cache permanen.
  static final List<Uint8List> _recent = [];
  static const int _maxRecent = 24;
  // Koleksi server (`stickers/<uid>/...`) — TAHAN install ulang.
  List<String> _paths = const [];
  // Sub-tab stiker: 0 = koleksiku, 1 = Emoji Art (Twemoji, CC-BY 4.0).
  int _pack = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  /// Muat koleksi stiker dari server (fire-and-forget; grid menyusul).
  Future<void> _loadSaved() async {
    try {
      final uid = ref.read(authProvider.notifier).uid;
      if (uid == null || !mounted) return;
      final paths =
          await ref.read(storageProvider).listStickers(uid, limit: 24);
      if (!mounted) return;
      setState(() => _paths = paths);
    } catch (_) {}
  }

  Future<void> _pickFromGallery() async {
    debugPrint('[STICKER] pickFromGallery tapped busy=$_busy');
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 95,
      );
      debugPrint('[STICKER] picked=${picked?.path}');
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      debugPrint('[STICKER] raw len=${raw.length}');
      if (raw.isEmpty) return;
      // Crop tengah → 512px PNG (jaga transparansi) via native, fallback Dart.
      final b64 = await NativeImage.processStickerPng(raw, size: 512);
      debugPrint('[STICKER] png b64 len=${b64?.length}');
      if (b64 == null || b64.isEmpty) return;
      final bytes = _b64(b64);
      if (bytes == null || !mounted) return;
      // Halaman EDIT ala WA (teks + toggle latar) — kirim dari sana.
      // Batal (back) → tidak terkirim, tidak masuk recent.
      final edited = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => StickerEditorPage(cutout: bytes, raw: raw),
        ),
      );
      if (edited == null || edited.isEmpty || !mounted) return;
      if (mounted) setState(() => _recent.insert(0, edited));
      while (_recent.length > _maxRecent) {
        _recent.removeLast();
      }
      if (mounted) {
        await widget.onSendSticker(edited);
        // File baru ter-upload oleh handler kirim → segarkan koleksi.
        unawaited(_loadSaved());
        if (mounted) Navigator.of(context).maybePop();
      }
    } catch (e) {
      debugPrint('[STICKER] pick/impor error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Uint8List? _b64(String s) {
    try {
      return const Base64Decoder().convert(s);
    } catch (_) {
      return null;
    }
  }

  /// Kirim karya Emoji Art: upscale 72px → 512 PNG via pipeline impor
  /// (tanpa hapus latar — karya sudah transparan), lalu kirim + koleksi.
  Future<void> _sendArt(Uint8List art72) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final b64 = await NativeImage.processStickerPng(
        art72,
        size: 512,
        removeBackground: false,
      );
      final bytes = b64 == null ? null : _b64(b64);
      if (bytes == null || !mounted) return;
      setState(() => _recent.insert(0, bytes));
      while (_recent.length > _maxRecent) {
        _recent.removeLast();
      }
      await widget.onSendSticker(bytes);
      unawaited(_loadSaved());
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Kirim stiker koleksi server: langsung pakai path bila handler
  /// mendukung (tanpa upload ulang); fallback download → bytes.
  Future<void> _sendSaved(String path) async {
    final viaPath = widget.onSendStickerPath;
    if (viaPath != null) {
      await viaPath(path);
      return;
    }
    try {
      final bytes = await ref.read(storageProvider).downloadBytes(path);
      if (bytes == null || bytes.isEmpty) return;
      await widget.onSendSticker(bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    return SafeArea(
      child: DefaultTabController(
        length: 2,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Column(
            children: [
              const SizedBox(height: 8),
              TabBar(
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primary,
                tabs: [
                  Tab(text: s.btnEmoji),
                  Tab(text: s.stickerTabTitle),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TabBarView(
                  children: [
                    // Tab emoji: pakai grid yang sama (delegasi ke helper).
                    Builder(
                      builder: (_) => Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        child: _emojiGridReuse(),
                      ),
                    ),
                    // Tab sticker: tombol impor + grid recent.
                    _stickerTab(s),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emojiGridReuse() {
    // Delegasi: buat El emoji cepat (bukan sumber tunggal — cukup tampil).
    return _StickerEmojiGrid(controller: widget.controller);
  }

  Widget _stickerTab(dynamic s) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFromGallery,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(s.stickerAddFromGallery),
                ),
              ),
            ],
          ),
        ),
        // Sub-tab: koleksiku | Emoji Art (paket bawaan, CC-BY 4.0).
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: Text(s.stickerPackMine),
                icon: const Icon(Icons.collections_bookmark_outlined, size: 16),
              ),
              ButtonSegment(
                value: 1,
                label: Text(s.stickerPackArt),
                icon: const Icon(Icons.emoji_emotions_outlined, size: 16),
              ),
            ],
            selected: {_pack},
            onSelectionChanged: (v) => setState(() => _pack = v.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        Expanded(
          child: _pack == 1
              ? TwemojiGrid(onPick: _sendArt)
              : _mineGrid(s),
        ),
      ],
    );
  }

  /// Grid koleksiku (server + sesi ini).
  Widget _mineGrid(dynamic s) {
    return _paths.isEmpty && _recent.isEmpty
        ? Center(
            child: Text(
              s.stickerEmpty,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            // Koleksi server dulu (tahan install ulang), lalu sesi ini.
            itemCount: _paths.length + _recent.length,
            itemBuilder: (_, i) {
              if (i < _paths.length) {
                final path = _paths[i];
                return GestureDetector(
                  onTap: () async {
                    await _sendSaved(path);
                    if (mounted) Navigator.of(context).maybePop();
                  },
                  child: StickerBubble(data: path, size: 72),
                );
              }
              final bytes = _recent[i - _paths.length];
              return GestureDetector(
                onTap: () async {
                  await widget.onSendSticker(bytes);
                  if (mounted) Navigator.of(context).maybePop();
                },
                child: StickerBytes(bytes: bytes, size: 72),
              );
            },
          );
  }
}

/// Grid emoji ringan (reuse daftar dari EmojiPickerSheet via insertAtCursor).
class _StickerEmojiGrid extends StatelessWidget {
  final TextEditingController controller;
  const _StickerEmojiGrid({required this.controller});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: EmojiPickerSheet.emojiCount,
      itemBuilder: (_, i) {
        final e = EmojiPickerSheet.emojiAt(i);
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => EmojiPickerSheet.insertAtCursor(controller, e),
          child: Center(
            child: Text(e, style: const TextStyle(fontSize: AppGlyph.md)),
          ),
        );
      },
    );
  }
}
