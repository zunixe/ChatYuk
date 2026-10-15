import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/theme.dart';
import '../utils.dart';
import '../core/media/image_cache_hygiene.dart';
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
  // Register hygiene logout sekali (lazy): bytes stiker user lama tidak boleh
  // tinggal di RAM saat ganti akun. Lihat core/media/image_cache_hygiene.dart.
  static bool _hygieneRegistered = false;
  // Koleksi server (`stickers/<uid>/...`) — TAHAN install ulang.
  List<String> _paths = const [];
  // Sub-tab stiker: 0 = koleksiku, 1 = Emoji Art (Twemoji, CC-BY 4.0).
  int _pack = 0;
  bool _busy = false;

  static void _registerHygiene() {
    if (_hygieneRegistered) return;
    _hygieneRegistered = true;
    ImageCacheHygiene.registerAppCache(_recent.clear);
  }

  /// Sisipkan bytes ke daftar "terbaru" (bounded) + pastikan pembersih
  /// hygiene logout terdaftar.
  void _rememberRecent(Uint8List bytes) {
    _registerHygiene();
    _recent.insert(0, bytes);
    while (_recent.length > _maxRecent) {
      _recent.removeLast();
    }
  }

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

  /// Impor VIDEO pendek (≤6 dtk, ≤8 MB) → upload mp4/mov → kirim langsung
  /// (tanpa halaman edit; editor hanya untuk gambar). Masuk koleksi juga.
  Future<void> _pickVideo() async {
    dlog('[STICKER] pickVideo tapped busy=$_busy');
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 6),
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      dlog('[STICKER] video len=${bytes.length}');
      if (bytes.isEmpty) return;
      if (bytes.length > 8 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ref.read(localeProvider).s.stickerTooBig),
            ),
          );
        }
        return;
      }
      var ext = picked.path.split('.').last.toLowerCase();
      if (ext != 'mp4' && ext != 'mov' && ext != 'webm') ext = 'mp4';
      final uid = ref.read(authProvider.notifier).uid;
      if (uid == null || !mounted) return;
      final path = await ref
          .read(storageProvider)
          .uploadSticker(uid: uid, base64: base64Encode(bytes), ext: ext);
      dlog('[STICKER] video upload path=$path');
      if (path == null || path.isEmpty || !mounted) return;
      final viaPath = widget.onSendStickerPath;
      if (viaPath == null) return;
      await viaPath(path);
      unawaited(_loadSaved());
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      dlog('[STICKER] pick video error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Impor BERKAS stiker jadi (.tgs Lottie / .gif / .webp / .png, ≤8 MB) →
  /// upload ext asli → kirim LANGSUNG (tanpa editor; editor membunuh
  /// animasi). Masuk koleksi juga.
  Future<void> _pickFile() async {
    dlog('[STICKER] pickFile tapped busy=$_busy');
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['tgs', 'gif', 'webp', 'png'],
        allowMultiple: false,
        withData: true,
      );
      final f = res?.files.singleOrNull;
      Uint8List? bytes = f?.bytes;
      if ((bytes == null || bytes.isEmpty) && f?.path != null) {
        try {
          bytes = await File(f!.path!).readAsBytes();
        } catch (_) {}
      }
      if (bytes == null || bytes.isEmpty || !mounted) return;
      var data = bytes;
      dlog('[STICKER] file len=${data.length} ext=${f?.extension}');
      if (data.length > 8 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ref.read(localeProvider).s.stickerTooBig),
            ),
          );
        }
        return;
      }
      var ext = (f?.extension ?? 'png').toLowerCase();
      if (ext != 'tgs' && ext != 'gif' && ext != 'webp') ext = 'png';
      // .tgs = JSON Lottie ter-gzip → buka dulu supaya render langsung baca.
      if (ext == 'tgs' &&
          data.length > 2 &&
          data[0] == 0x1f &&
          data[1] == 0x8b) {
        try {
          data = Uint8List.fromList(gzip.decode(data));
        } catch (_) {}
      }
      final uid = ref.read(authProvider.notifier).uid;
      if (uid == null || !mounted) return;
      final path = await ref
          .read(storageProvider)
          .uploadSticker(uid: uid, base64: base64Encode(data), ext: ext);
      dlog('[STICKER] file upload path=$path');
      if (path == null || path.isEmpty || !mounted) return;
      final viaPath = widget.onSendStickerPath;
      if (viaPath == null) return;
      await viaPath(path);
      unawaited(_loadSaved());
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      dlog('[STICKER] pick file error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {    dlog('[STICKER] pickFromGallery tapped busy=$_busy');
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 95,
      );
      dlog('[STICKER] picked=${picked?.path}');
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      dlog('[STICKER] raw len=${raw.length}');
      if (raw.isEmpty) return;
      // Crop tengah → 512px PNG (jaga transparansi) via native, fallback Dart.
      final b64 = await NativeImage.processStickerPng(raw, size: 512);
      dlog('[STICKER] png b64 len=${b64?.length}');
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
      if (mounted) setState(() => _rememberRecent(edited));
      if (mounted) {
        await widget.onSendSticker(edited);
        // File baru ter-upload oleh handler kirim → segarkan koleksi.
        unawaited(_loadSaved());
        if (mounted) Navigator.of(context).maybePop();
      }
    } catch (e) {
      dlog('[STICKER] pick/impor error: $e');
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
      setState(() => _rememberRecent(bytes));
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
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: _busy ? null : _pickVideo,
                tooltip: s.stickerPickVideo,
                icon: const Icon(Icons.videocam_outlined, size: 18),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: _busy ? null : _pickFile,
                tooltip: s.stickerPickFile,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
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
              ? Column(
                  children: [
                    Expanded(child: TwemojiGrid(onPick: _sendArt)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        s.stickerArtCredit,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
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
                  // Tahan (long-press) = hapus stiker dari koleksi server.
                  onLongPress: () => _confirmDeleteSticker(path),
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

  /// Konfirmasi + hapus stiker koleksi server (long-press tile).
  Future<void> _confirmDeleteSticker(String path) async {
    if (_busy) return;
    final s = ref.read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.stickerDeleteTitle, style: AppText.title),
        content: Text(s.stickerDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final uid = ref.read(authProvider.notifier).uid;
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      final done = await ref
          .read(storageProvider)
          .deleteSticker(uid: uid, path: path);
      if (!mounted) return;
      if (done) {
        setState(() => _paths = _paths.where((p) => p != path).toList());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.stickerDeleted)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.stickerDeleteFail)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
