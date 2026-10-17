import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import '../config/strings.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import '../providers/riverpod/nav_provider.dart';
import '../providers/riverpod/timeline_provider.dart';
import '../core/cache/post_photo_cache.dart';
import '../core/bounded_task.dart';
import '../core/media/native_image.dart';
import '../core/media/post_photo_prepare.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../providers/riverpod/theme_provider.dart';
import '../core/perf/perf_probe.dart';
import '../config/theme.dart';

// Foto post (resize lebar 1080 + JPEG q78 + dimensi) kini diproses di NATIVE
// via `NativeImage.processPost` (fallback Dart di chat_photo_helper.dart).

/// Composer post timeline — header profil, visibilitas, text form + hashtag
/// chip badge, multi-foto (galeri multi-pick & kamera), tombol Post pin bawah.
class PostComposerScreen extends ConsumerStatefulWidget {
  const PostComposerScreen({super.key});

  @override
  ConsumerState<PostComposerScreen> createState() => _PostComposerScreenState();
}

enum _MediaSource { gallery, camera }

class _PostComposerScreenState extends ConsumerState<PostComposerScreen> {
  final _picker = ImagePicker();
  final _textCtrl = TextEditingController();
  final List<Uint8List> _images = [];
  // Dimensi (w,h) sejajar dengan _images — dikirim ke server supaya feed
  // bisa menampilkan rasio asli tanpa layout shift.
  final List<({int w, int h})> _imageDims = [];
  // BlurHash sejajar _images (placeholder instan di feed). '' = tak tersedia.
  final List<String> _imageBlurhashes = [];
  // Progress upload (per-foto selesai / total).
  int _uploadDone = 0;
  int _uploadTotal = 0;
  String _visibility = 'public';
  bool _posting = false;
  bool _picking = false;
  static const _maxImages = 5; // ikuti batas backend (create_post <= 5)
  static const _maxText = 500;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  /// Proses foto pilih → bytes siap upload + dimensi + BlurHash.
  /// Logika & fallback (kompresi gagal → file asli) ada di
  /// `preparePostPhoto` (`core/media/post_photo_prepare.dart`) agar testable.
  Future<({Uint8List bytes, int w, int h, String blurhash})?> _prepare(
    Uint8List raw,
  ) => preparePostPhoto(raw);

  /// Ambil foto dari galeri — multi-pick sekaligus (maks 10 total).
  Future<void> _pickGallery() async {
    if (_picking || _images.length >= _maxImages) return;
    setState(() => _picking = true);
    try {
      final remaining = _maxImages - _images.length;
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
        limit: remaining,
      );
      if (picked.isEmpty) return;
      final results = await Future.wait(
        picked.map((p) async {
          final bytes = await p.readAsBytes();
          return _prepare(bytes);
        }),
      );
      if (!mounted) return;
      var failed = 0;
      for (final r in results) {
        if (r == null) {
          failed++;
          continue;
        }
        if (_images.length < _maxImages) {
          _images.add(r.bytes);
          _imageDims.add((w: r.w, h: r.h));
          _imageBlurhashes.add(r.blurhash);
        }
      }
      setState(() {});
      if (failed > 0) _toast(ProviderScope.containerOf(context, listen: false).read(localeProvider).s.errPreparePhoto);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Ambil satu foto langsung dari kamera.
  Future<void> _pickCamera() async {
    if (_picking || _images.length >= _maxImages) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final prepared = await _prepare(bytes);
      if (!mounted) return;
      if (prepared != null && _images.length < _maxImages) {
        setState(() {
          _images.add(prepared.bytes);
          _imageDims.add((w: prepared.w, h: prepared.h));
          _imageBlurhashes.add(prepared.blurhash);
        });
      } else if (prepared == null) {
        _toast(ProviderScope.containerOf(context, listen: false).read(localeProvider).s.errPreparePhoto);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Bottom sheet pilih sumber foto: Galeri / Kamera.
  Future<void> _pickMediaSource() async {
    if (_picking || _images.length >= _maxImages) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final source = await showModalBottomSheet<_MediaSource>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppTheme.primary,
              ),
              title: Text(s.btnGallery, style: AppText.bodyStrong),
              onTap: () => Navigator.of(ctx).pop(_MediaSource.gallery),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: AppTheme.primary,
              ),
              title: Text(s.btnCamera, style: AppText.bodyStrong),
              onTap: () => Navigator.of(ctx).pop(_MediaSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == _MediaSource.gallery) {
      await _pickGallery();
    } else if (source == _MediaSource.camera) {
      await _pickCamera();
    }
  }

  /// Parse hashtag dari teks — tampil sebagai chip badge.
  List<String> _extractHashtags(String text) {
    final matches = RegExp(
      r'#([\p{L}\p{N}_]+)',
      unicode: true,
    ).allMatches(text);
    final seen = <String>{};
    for (final m in matches) {
      seen.add('#${m.group(1)}');
    }
    return seen.toList();
  }

  /// User anonim (belum lengkapi email) tidak bisa posting — info ke Profil.
  Future<bool> _ensureRegistered() async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    if (auth.profile?.isRegistered ?? false) return true;
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.promptCompleteEmailTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mark_email_unread_outlined,
              size: 48,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 12),
            Text(s.promptCompleteEmailMsg, textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).popUntil((r) => r.isFirst);
              ProviderScope.containerOf(context, listen: false).read(navProvider.notifier).goTo(3);
            },
            child: Text(s.btnGoProfile),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _post() async {
    // Guard dobel-tap: flag diset SINKRON sebelum await apa pun. Tanpa ini,
    // ketukan kedua selama `await _ensureRegistered()` lolos masuk karena
    // tombol belum disabled (kasus nyata: 2 post "Destination" selisih 124ms).
    if (_posting) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _images.isEmpty) {
      _toast(s.errPostEmpty);
      return;
    }
    if (text.length > _maxText) {
      _toast(s.errPostTooLong);
      return;
    }

    setState(() => _posting = true);
    if (!await _ensureRegistered() || !mounted) {
      if (mounted) setState(() => _posting = false);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final uid = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).uid;
      final paths = <String>[];
      if (uid != null && _images.isNotEmpty) {
        final storage =
            ProviderScope.containerOf(context, listen: false).read(storageProvider);
        final total = _images.length;
        if (mounted) {
          setState(() {
            _uploadTotal = total;
            _uploadDone = 0;
          });
        }
        // Hasil per-indeks → urutan paths sejajar _images/_imageDims/_imageBlurhashes.
        final results = List<String?>.filled(total, null);
        // Konkurensi DIBATASI (3) — dulu semua foto serentak → lonjakan
        // memori/bandwidth di HP kelas menengah.
        await runBounded<Uint8List>(
          items: _images,
          maxConcurrent: 3,
          run: (b64, i) async {
            try {
              results[i] = await storage.uploadPostImage(
                uid: uid,
                base64: base64Encode(b64),
              );
            } catch (_) {
              results[i] = null;
            }
            if (mounted) setState(() => _uploadDone = i + 1);
          },
        );
        // Seed cache lokal tiap foto yang sukses diupload (fire-and-forget)
        // supaya feed refresh langsung tampil tanpa re-download.
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          if (r != null) {
            paths.add(r);
            PostPhotoCache.instance.save(r, _images[i]);
          }
        }
        // Foto gagal upload → jangan naikkan post diam-diam dengan foto
        // yang hilang. Beri tahu user dan batalkan.
        if (paths.length != _images.length) {
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
          setState(() => _posting = false);
          return;
        }
      }
      await ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).createPost(
        text: text,
        imagePaths: paths,
        imageDims: [for (final d in _imageDims) {'w': d.w, 'h': d.h}],
        imageBlurhashes: List<String>.from(_imageBlurhashes),
        visibility: _visibility,
      );
      if (!mounted) return;
      ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).load('all', refresh: true);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s.msgPostSent,
            style: TextStyle(
              fontSize: AppTextSize.s14,
              fontWeight: FontWeight.w600,
              color: _kSnackFg,
            ),
          ),
          backgroundColor: _kSnackBg,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      final label = msg.contains('limit') ? s.errPostLimit : s.errGeneric;
      messenger.showSnackBar(SnackBar(content: Text(label)));
      setState(() => _posting = false);
    } finally {
      if (mounted) setState(() => _uploadTotal = 0);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Palet khusus design "Postingan baru" (warna yang tidak ada di AppTheme) ──
  static const Color _kWarn = Color(0xFFFF6B6F);
  static const Color _kSelectedBg = Color(0xFF1E3A50);
  static const Color _kLink = Color(0xFF4FB3F6);
  static const Color _kChipText = Color(0xFFC9C9C9);
  static const Color _kRadioOff = Color(0xFF4A4A4A);
  static const Color _kHandle = Color(0xFF3D3D3D);
  static const Color _kSnackBg = Color(0xFFF5F5F5);
  static const Color _kSnackFg = Color(0xFF121212);

  bool get _hasContent =>
      _textCtrl.text.trim().isNotEmpty || _images.isNotEmpty;

  S get _s => ProviderScope.containerOf(context, listen: false).read(localeProvider).s;

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('PostComposer');
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    final profile = ref.watch(authProvider.select((a) => a.profile));
    final myName = profile?.nickname ?? 'Anon';
    final suggestions = _suggestedHashtags(profile?.hashtags ?? const []);
    final len = _textCtrl.text.length.clamp(0, _maxText);

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.bgScreen,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: 52,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 24),
          color: AppTheme.textPrimary,
          tooltip: s.btnClose,
          onPressed: _posting ? null : _close,
        ),
        title: Text(s.composerTitleNew, style: AppText.titleEmphasis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _postButton(s)),
          ),
        ],
        shape: Border(
          bottom: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                uid: profile?.uid ?? '',
                name: myName,
                size: 40,
                borderRadius: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 2, top: 2),
                      child: Text(
                        myName,
                        style: TextStyle(
                          fontSize: AppTextSize.s15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _visibilityChip(s),
                    const SizedBox(height: 2),
                    _textField(s),
                    if (_images.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _imagesGrid(),
                    ],
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _suggestionWrap(suggestions),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomToolbar(s, len),
    );
  }

  /// Tombol Posting pill di AppBar — nonaktif saat kosong, spinner saat upload.
  Widget _postButton(S s) {
    final enabled = _hasContent && !_posting;
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: enabled ? _post : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          elevation: 0,
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.bgInput,
          disabledForegroundColor: AppTheme.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        child: _posting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                s.btnPost,
                style: TextStyle(
                  fontSize: AppTextSize.s14,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  /// Chip visibilitas (tinggi 26, target sentuh 40) → bottom sheet.
  Widget _visibilityChip(S s) {
    final (label, icon) = switch (_visibility) {
      'followers' => (s.visFollowers, Icons.people_outline_rounded),
      'subscribers' => (s.visSubscribers, Icons.star_outline_rounded),
      _ => (s.visPublic, Icons.public_rounded),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _posting ? null : _openVisibilitySheet,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Container(
          height: 26,
          padding: const EdgeInsets.fromLTRB(8, 0, 9, 0),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: _kChipText),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.s125,
                  fontWeight: FontWeight.w600,
                  color: _kChipText,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 12,
                color: _kChipText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// TextField tanpa border/fill, tumbuh otomatis, batas 500 karakter.
  Widget _textField(S s) {
    return TextField(
      controller: _textCtrl,
      minLines: 4,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: [LengthLimitingTextInputFormatter(_maxText)],
      style: TextStyle(
        fontSize: AppTextSize.s16,
        height: AppTextSize.lh15,
        color: AppTheme.textPrimary,
      ),
      decoration: InputDecoration(
        isCollapsed: true,
        // Tema global `inputDecorationTheme` = filled + radius 12 → WAJIB
        // dimatikan agar benar-benar tanpa box/latar (spec: borderless).
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        hintText: s.composerHintShare,
        hintStyle: TextStyle(
          fontSize: AppTextSize.s16,
          height: AppTextSize.lh15,
          color: AppTheme.textSecondary,
        ),
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  /// Grid foto 2 kolom (rasio 4:5), radius 12, tombol hapus 26px.
  Widget _imagesGrid() {
    final s = _s;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 4 / 5,
      ),
      itemCount: _images.length,
      itemBuilder: (_, i) {
        final idx = i;
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                _images[idx],
                fit: BoxFit.cover,
                cacheWidth: 640,
                gaplessPlayback: true,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Tooltip(
                message: s.tooltipRemovePhoto,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _removeImage(idx),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _removeImage(int idx) {
    setState(() {
      _images.removeAt(idx);
      if (idx < _imageDims.length) _imageDims.removeAt(idx);
      if (idx < _imageBlurhashes.length) _imageBlurhashes.removeAt(idx);
    });
  }

  /// Saran hashtag dari minat/hashtag user (buang yang sudah ada di teks).
  List<String> _suggestedHashtags(List<String> own) {
    final existing = _extractHashtags(_textCtrl.text)
        .map((e) => e.substring(1).toLowerCase())
        .toSet();
    final out = <String>[];
    for (final raw in own) {
      final clean = raw.replaceAll('#', '').trim();
      if (clean.isEmpty) continue;
      if (existing.contains(clean.toLowerCase())) continue;
      if (out.contains(clean)) continue;
      out.add(clean);
      if (out.length >= 6) break;
    }
    return out;
  }

  Widget _suggestionWrap(List<String> tags) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in tags)
          GestureDetector(
            onTap: () => _addHashtag(t),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '#$t',
                style: TextStyle(
                  fontSize: AppTextSize.s125,
                  fontWeight: FontWeight.w600,
                  color: _kLink,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _addHashtag(String tag) {
    final t = _textCtrl.text;
    final sep = (t.isEmpty || t.endsWith(' ')) ? '' : ' ';
    var next = '$t$sep#$tag';
    if (next.length > _maxText) next = next.substring(0, _maxText);
    _textCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  void _insertHash() {
    final v = _textCtrl.value;
    final sel = v.selection;
    final pos = sel.isValid ? sel.start : v.text.length;
    if (v.text.length >= _maxText) return;
    final next = v.text.replaceRange(pos, pos, '#');
    _textCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: pos + 1),
    );
    setState(() {});
  }

  /// Toolbar bawah: tambah foto / emoji / hashtag + counter & cincin progres.
  Widget _bottomToolbar(S s, int len) {
    final warn = len >= (_maxText * 0.9);
    final color = warn ? _kWarn : AppTheme.textSecondary;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgScreen,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              _toolButton(
                Icons.photo_library_outlined,
                s.tooltipAddPhoto,
                _pickMediaSource,
              ),
              _toolButton(
                Icons.emoji_emotions_outlined,
                s.tooltipAddEmoji,
                () => EmojiPickerSheet.show(context, _textCtrl),
              ),
              _toolButton(Icons.tag, s.tooltipHashtag, _insertHash),
              const Spacer(),
              Text(
                '$len/$_maxText',
                style: TextStyle(
                  fontSize: AppTextSize.s125,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 26,
                height: 26,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: 1,
                      strokeWidth: 3,
                      color: AppTheme.bgInput,
                      strokeCap: StrokeCap.round,
                    ),
                    CircularProgressIndicator(
                      value: (len / _maxText).clamp(0.0, 1.0),
                      strokeWidth: 3,
                      color: color,
                      strokeCap: StrokeCap.round,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 44,
        height: 40,
        child: InkWell(
          onTap: _posting ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: Center(child: Icon(icon, size: 24, color: _kLink)),
        ),
      ),
    );
  }

  /// Sheet "Siapa yang bisa membalas" (3 opsi + radio).
  Future<void> _openVisibilitySheet() async {
    final s = _s;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _kHandle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(s.titleWhoCanReply, style: AppText.titleEmphasis),
              const SizedBox(height: 12),
              _visOption(
                ctx,
                'public',
                s.visPublic,
                s.visPublicDescLong,
                Icons.public_rounded,
              ),
              _visOption(
                ctx,
                'followers',
                s.visFollowers,
                s.visFollowersDescLong,
                Icons.people_outline_rounded,
              ),
              _visOption(
                ctx,
                'subscribers',
                s.visSubscribers,
                s.visSubscribersDescLong,
                Icons.star_outline_rounded,
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _visibility = picked);
  }

  Widget _visOption(
    BuildContext ctx,
    String value,
    String label,
    String desc,
    IconData icon,
  ) {
    final on = _visibility == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).pop(value),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? _kSelectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.bgInput,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: _kLink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppTextSize.s15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: AppTextSize.s125,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: on ? AppTheme.primary : _kRadioOff,
                    width: 2,
                  ),
                  color: on ? AppTheme.primary : Colors.transparent,
                ),
                child: on
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tutup composer — konfirmasi bila ada teks/foto belum dikirim.
  Future<void> _close() async {
    if (_posting) return;
    if (!_hasContent) {
      Navigator.of(context).pop();
      return;
    }
    final s = _s;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.composerDiscardTitle),
        content: Text(s.composerDiscardMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.btnDiscard),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }
}
