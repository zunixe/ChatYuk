import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/theme.dart';
import '../core/media/native_image.dart';
import '../providers/riverpod/locale_provider.dart';
import 'emoji_picker_sheet.dart';
import 'sticker_bubble.dart';

/// Sheet bersama **Emoji | Sticker** untuk composer chat (private & room).
///
/// Tab Sticker: impor dari GALERI (S3) → crop 512px PNG (ImageBridge) →
/// kirim. Grid menampilkan item terbaru (preview bytes sebelum terkirim).
class StickerEmojiSheet extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Future<void> Function(Uint8List stickerPngBytes) onSendSticker;
  const StickerEmojiSheet({
    super.key,
    required this.controller,
    required this.onSendSticker,
  });

  @override
  ConsumerState<StickerEmojiSheet> createState() => _StickerEmojiSheetState();
}

class _StickerEmojiSheetState extends ConsumerState<StickerEmojiSheet> {
  // Bounded: preview sticker terbaru (bytes PNG) — bukan cache permanen.
  static final List<Uint8List> _recent = [];
  static const int _maxRecent = 24;
  bool _busy = false;

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 95,
      );
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      if (raw.isEmpty) return;
      // Crop tengah → 512px PNG (jaga transparansi) via native, fallback Dart.
      final b64 = await NativeImage.processStickerPng(raw, size: 512);
      if (b64 == null || b64.isEmpty) return;
      final bytes = _b64(b64);
      if (bytes == null) return;
      if (mounted) setState(() => _recent.insert(0, bytes));
      while (_recent.length > _maxRecent) {
        _recent.removeLast();
      }
      if (mounted) {
        await widget.onSendSticker(bytes);
        if (mounted) Navigator.of(context).maybePop();
      }
    } catch (_) {
      // Gagal impor → diamkan (sheet tetap terbuka).
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
        Expanded(
          child: _recent.isEmpty
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
                  itemCount: _recent.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () async {
                      await widget.onSendSticker(_recent[i]);
                      if (mounted) Navigator.of(context).maybePop();
                    },
                    child: StickerBytes(bytes: _recent[i], size: 72),
                  ),
                ),
        ),
      ],
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
