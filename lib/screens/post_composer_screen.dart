import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/timeline_provider.dart';
import '../services/post_photo_cache.dart';
import '../services/storage_photo_service.dart';
import '../services/timeline_service.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../providers/theme_provider.dart';

/// Proses foto (resize + JPEG) di isolate sebelum upload.
Uint8List? _processPostImage(List<int> bytes) {
  try {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) return null;
    final resized = img.copyResize(decoded, width: 1200);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  } catch (_) {
    return null;
  }
}

/// Composer post timeline — header profil, visibilitas, text form + hashtag
/// chip badge, multi-foto (galeri multi-pick & kamera), tombol Post pin bawah.
class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({super.key});

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

enum _MediaSource { gallery, camera }

class _PostComposerScreenState extends State<PostComposerScreen> {
  final _picker = ImagePicker();
  final _textCtrl = TextEditingController();
  final List<Uint8List> _images = [];
  String _visibility = 'public';
  bool _posting = false;
  bool _picking = false;
  double _fieldHeight = 120;

  static const _maxImages = 5;
  static const _maxText = 2000;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

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
          return compute(_processPostImage, bytes);
        }),
      );
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          if (r != null && _images.length < _maxImages) _images.add(r);
        }
      });
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
      final processed = await compute(_processPostImage, bytes);
      if (!mounted) return;
      setState(() {
        if (processed != null && _images.length < _maxImages) {
          _images.add(processed);
        }
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Bottom sheet pilih sumber foto: Galeri / Kamera.
  Future<void> _pickMediaSource() async {
    if (_picking || _images.length >= _maxImages) return;
    final s = context.read<LocaleProvider>().s;
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
              leading: const Icon(Icons.photo_library_outlined, color: AppTheme.primary),
              title: Text(s.btnGallery, style: AppText.bodyStrong),
              onTap: () => Navigator.of(ctx).pop(_MediaSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppTheme.primary),
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
    final matches = RegExp(r'#([\p{L}\p{N}_]+)', unicode: true).allMatches(text);
    final seen = <String>{};
    for (final m in matches) {
      seen.add('#${m.group(1)}');
    }
    return seen.toList();
  }

  /// User anonim (belum lengkapi email) tidak bisa posting — info ke Profil.
  Future<bool> _ensureRegistered() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    if (auth.profile?.isRegistered ?? false) return true;
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.promptCompleteEmailTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_unread_outlined,
                size: 48, color: AppTheme.primary),
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
              context.read<NavProvider>().goTo(3);
            },
            child: Text(s.btnGoProfile),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _post() async {
    final s = context.read<LocaleProvider>().s;
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _images.isEmpty) {
      _toast(s.errPostEmpty);
      return;
    }
    if (text.length > _maxText) {
      _toast(s.errPostTooLong);
      return;
    }
    if (!await _ensureRegistered() || !mounted) return;

    setState(() => _posting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uid = context.read<AuthProvider>().uid;
      final paths = <String>[];
      if (uid != null && _images.isNotEmpty) {
        final uploads = _images.map((b64) => StoragePhotoService.instance.uploadPostImage(
              uid: uid,
              base64: base64Encode(b64),
            ));
        final results = await Future.wait(uploads);
        // Seed cache lokal tiap foto yang sukses diupload (fire-and-forget)
        // supaya feed refresh langsung tampil tanpa re-download.
        for (var i = 0; i < results.length; i++) {
          final p = results[i];
          if (p != null) {
            paths.add(p);
            PostPhotoCache.instance.save(p, _images[i]);
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
      await TimelineService().createPost(text: text, imagePaths: paths, visibility: _visibility);
      if (!mounted) return;
      context.read<TimelineProvider>().load('all', refresh: true);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(s.msgPosted)));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      final label = msg.contains('limit') ? s.errPostLimit : s.errGeneric;
      messenger.showSnackBar(SnackBar(content: Text(label)));
      setState(() => _posting = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    final myName = profile?.nickname ?? 'Anon';
    final hashtags = _extractHashtags(_textCtrl.text);

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppTheme.headerGradient,
          ),
        ),
        title: Text(s.btnPost, style: AppText.title.copyWith(color: Colors.white)),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header profil — avatar + nama + "Posting sebagai" ──
            Row(
              children: [
                ProfileAvatar(uid: auth.uid ?? '', name: myName, size: 44, borderRadius: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(myName, style: AppText.bodyStrong),
                      SizedBox(height: 2),
                      Text(
                        s.postingAs,
                        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // ── Card tulis — text input + drag handle resize (pojok kanan) ──
            Container(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 4),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                children: [
                  SizedBox(
                    height: _fieldHeight,
                    child: TextField(
                      controller: _textCtrl,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      maxLength: _maxText,
                      style: AppText.body,
                      decoration: InputDecoration(
                        hintText: s.hintWritePost,
                        hintStyle: AppText.body.copyWith(color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.bgCard,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide(color: AppTheme.bgCard, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide(color: AppTheme.bgCard, width: 1.5),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide(color: AppTheme.bgCard, width: 1.5),
                        ),
                        counterText: '',
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  // Pojok kanan bawah: emoji kecil + handle drag naik/turun
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Row(
                      children: [
                        _mediaIconButton(
                          Icons.sentiment_satisfied_alt,
                          Colors.amber.shade700,
                          s.btnEmoji,
                          () => EmojiPickerSheet.show(context, _textCtrl),
                        ),
                        SizedBox(width: 6),
                        Tooltip(
                          message: s.tooltipResize,
                          child: GestureDetector(
                            onVerticalDragUpdate: (d) => setState(
                              () => _fieldHeight = (_fieldHeight + d.delta.dy).clamp(80, 320),
                            ),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppTheme.textSecondary.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.unfold_more, size: 18, color: AppTheme.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),

            // ── Hashtag chip badge — muncul otomatis saat mengetik #tag ──
            if (hashtags.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.tag, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(s.labelHashtags, style: AppText.label),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in hashtags)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tag, size: 14, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text(tag, style: AppText.caption.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // ── Foto: kotak tambah (awal) / grid foto + kotak plus ──
            if (_images.isEmpty)
              _emptyAddTile(s)
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _images.length + 1, // + kotak plus
                itemBuilder: (_, i) {
                  if (i < _images.length) {
                    final idx = i;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_images[idx], fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _images.removeAt(idx)),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return _addTile(s);
                },
              ),
            if (_images.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                '${_images.length}/$_maxImages ${s.photoCountLabel}',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ],
            SizedBox(height: 16),

            // ── Visibilitas — card putih ala profil: ikon + label + chip ──
            Container(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.visibility_outlined, size: 18, color: AppTheme.primary),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.labelVisibility, style: AppText.bodyStrong),
                            SizedBox(height: 1),
                            Text(
                              _visDesc(s),
                              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      _visChip(s, 'public', Icons.public, s.visPublic),
                      SizedBox(width: 8),
                      _visChip(s, 'followers', Icons.people_outline_rounded, s.visFollowers),
                      SizedBox(width: 8),
                      _visChip(s, 'subscribers', Icons.star_outline_rounded, s.visSubscribers),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -2))],
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _posting ? null : _post,
              icon: _posting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(s.btnPost, style: AppText.button),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Tombol media ikon bulat (galeri/kamera) — tanpa spinner, hanya
  /// fade saat picker sedang diproses supaya UI tetap tenang.
  /// [color] ikon & latar mengikuti komposisi warna ala menu profil.
  Widget _mediaIconButton(IconData icon, Color color, String label, VoidCallback onTap) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: _picking ? null : onTap,
        child: AnimatedOpacity(
          opacity: _picking ? 0.4 : 1,
          duration: const Duration(milliseconds: 180),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }

  /// Kotak tambah foto — tampil saat belum ada foto sama sekali.
  /// Klik → bottom sheet pilih Galeri / Kamera.
  Widget _emptyAddTile(S s) {
    return _mediaTile(
      icon: Icons.add_photo_alternate_outlined,
      label: s.btnAdd,
      onTap: _pickMediaSource,
    );
  }

  Widget _mediaTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _picking ? null : onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primary, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppText.bodyStrong.copyWith(color: AppTheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  /// Kotak plus untuk tambah foto — selalu tampil di akhir grid.
  Widget _addTile(S s) {
    return GestureDetector(
      onTap: _picking || _images.length >= _maxImages ? null : _pickMediaSource,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _images.length >= _maxImages ? Icons.check_circle : Icons.add_photo_alternate_outlined,
              color: AppTheme.primary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              _images.length >= _maxImages ? '$_maxImages' : s.btnAdd,
              style: AppText.caption.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  String _visDesc(S s) {
    switch (_visibility) {
      case 'followers': return s.visFollowersDesc;
      case 'subscribers': return s.visSubscribersDesc;
      default: return s.visPublicDesc;
    }
  }

  Widget _visChip(S s, String value, IconData icon, String label) {
    final selected = _visibility == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _visibility = value),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppTheme.primary : AppTheme.divider, width: selected ? 1.4 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? AppTheme.primary : AppTheme.textSecondary),
              SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
