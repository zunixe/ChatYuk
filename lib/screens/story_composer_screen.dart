import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/story_provider.dart';
import '../services/storage_photo_service.dart';
import '../widgets/story_text_overlay.dart';
import 'dart:convert';

/// Kompres foto story di isolate (pola post composer): resize 1080px,
/// JPEG q85 — cukup tajam untuk fullscreen tanpa boros kuota.
String _processStoryImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return '';
  final resized = img.copyResize(decoded, width: 1080);
  final jpg = img.encodeJpg(resized, quality: 85);
  return base64Encode(jpg);
}

/// Halaman buat story: preview foto 9:16 + teks overlay (drag bebas,
/// warna/ukuran/latar) + pilih visibility. Anon tidak sampai ke sini
/// (tombol + tersembunyi; RLS server juga menolak).
class StoryComposerScreen extends StatefulWidget {
  final XFile picked;
  const StoryComposerScreen({super.key, required this.picked});

  @override
  State<StoryComposerScreen> createState() => _StoryComposerScreenState();
}

class _StoryComposerScreenState extends State<StoryComposerScreen> {
  final _textCtrl = TextEditingController();
  final _textFocus = FocusNode();
  Uint8List? _bytes;
  String _b64 = '';

  double _textX = 0.5;
  // Default di tengah halaman (bukan bawah) supaya kursor tidak
  // ketutup keyboard saat mulai mengetik. User bisa geser manual.
  double _textY = 0.45;
  // Skala pinch-to-zoom (1 jari = geser, 2 jari = besar/kecil).
  double _textScale = 1.0;
  double _scaleBase = 1.0;
  // Drag teks ke tong sampah (atas tengah) → teks dihapus ala IG.
  bool _dragOverTrash = false;
  int _colorIndex = StoryText.defaultColorIndex;
  int _sizeIndex = 1;
  bool _withBg = false;
  String _visibility = 'registered';
  bool _publishing = false;
  bool _showTextTools = false;
  bool _showTextArea = false;

  Color get _textColor => _colorIndex >= 0 &&
          _colorIndex < StoryText.palette.length
      ? StoryText.palette[_colorIndex]
      : StoryText.palette.first;

  bool get _hasText => _textCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {}));
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.picked.readAsBytes();
    if (!mounted) return;
    setState(() => _bytes = bytes);
    final b64 = await compute(_processStoryImage, bytes);
    if (!mounted) return;
    setState(() => _b64 = b64);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    if (uid == null || _b64.isEmpty) return;
    setState(() => _publishing = true);
    try {
      final path = await StoragePhotoService.instance
          .uploadStoryImage(uid: uid, base64: _b64);
      if (path == null || path.isEmpty) throw Exception('upload_failed');
      final ok = await context.read<StoryProvider>().publish(
            imagePath: path,
            textOverlay: _textCtrl.text.trim(),
            textX: _textX,
            textY: _textY,
            textColor: _colorIndex,
            textSize: _sizeIndex,
            textScale: _textScale,
            textBg: _withBg,
            visibility: _visibility,
            myUid: uid,
            myNickname: auth.profile?.nickname ?? 'Anon',
            myAvatar: auth.profile?.avatar ?? '',
          );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.storyPublishFail)),
        );
      }
    } catch (e) {
      debugPrint('[StoryComposer] publish error: $e');
      if (mounted) {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.storyPublishFail)),
        );
      }
    }
  }

  // ── Pinch-to-zoom + drag (satu handler untuk 1 & 2 jari) ──
  // onScaleUpdate jalan untuk geser satu jari (scale≈1) maupun cubit:
  // focalPointDelta = gerakan, scale = rasio terhadap awal gestur.
  void _onScaleStart(ScaleStartDetails d) {
    _scaleBase = _textScale;
  }

  void _onScale(ScaleUpdateDetails d, Size boxSize) {
    setState(() {
      _textScale = (_scaleBase * d.scale).clamp(0.5, 3.0);
      if (d.focalPointDelta.distance > 0) {
        _textX =
            (_textX + d.focalPointDelta.dx / boxSize.width).clamp(0.0, 1.0);
        _textY =
            (_textY + d.focalPointDelta.dy / boxSize.height).clamp(0.0, 1.0);
      }
      // Zona hapus: atas tengah (di bawah ikon tong sampah).
      _dragOverTrash =
          _textY < 0.10 && (_textX - 0.5).abs() < 0.18;
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dragOverTrash) {
      setState(() {
        _textCtrl.clear();
        _showTextArea = false;
        _showTextTools = false;
        _dragOverTrash = false;
        _textScale = 1.0;
        _textX = 0.5;
        _textY = 0.45;
      });
      _textFocus.unfocus();
      return;
    }
    if (_dragOverTrash) setState(() => _dragOverTrash = false);
  }

  // ── UX teks ala IG ──
  // Tombol "T" kanan atas foto → munculkan area teks DI ATAS foto (posisi
  // = posisi overlay nanti). Tap area teks → panel warna + ukuran.
  // Typing langsung di dalam foto; drag di luar area teks = pindahkan.
  void _toggleTextArea() {
    setState(() {
      _showTextArea = !_showTextArea;
      if (_showTextArea) _showTextTools = true;
    });
    if (_showTextArea) {
      _textFocus.requestFocus();
    } else {
      _textFocus.unfocus();
    }
  }

  void _onTextTap() {
    // Tap area teks → tampilkan/munculkan panel gaya (warna + ukuran).
    setState(() => _showTextTools = true);
    _textFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      // Foto TETAP seukuran layar walau keyboard muncul — panel bawah
      // naik sejajar keyboard lewat viewInsets (foto tidak dimenezkan).
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          s.storyComposerTitle,
          style: AppText.title.copyWith(color: Colors.white),
        ),
        actions: [
          if (_publishing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              tooltip: s.storyBtnPublish,
              icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
              onPressed: _b64.isEmpty ? null : _publish,
            ),
        ],
      ),
      body: _bytes == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : LayoutBuilder(
              builder: (ctx, c) => Stack(
                fit: StackFit.expand,
                children: [
                  // ── Foto seukuran layar ──
                  Positioned.fill(
                    child: Image.memory(_bytes!, fit: BoxFit.fitHeight),
                  ),
                  // ── Zona interaktif: drag teks / tap tutup panel ──
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _hasText && !_showTextArea
                          ? _onScaleStart
                          : null,
                      onScaleUpdate: _hasText && !_showTextArea
                          ? (d) => _onScale(d, c.biggest)
                          : null,
                      onScaleEnd: _hasText && !_showTextArea
                          ? _onScaleEnd
                          : null,
                      // Klik 2x pada teks jadi → mode edit.
                      onDoubleTap: _hasText && !_showTextArea
                          ? () {
                              setState(() {
                                _showTextArea = true;
                                _showTextTools = true;
                              });
                              _textFocus.requestFocus();
                            }
                          : null,
                      onTap: () {
                        if (_showTextTools || _showTextArea) {
                          setState(() {
                            _showTextTools = false;
                            _showTextArea = false;
                          });
                          _textFocus.unfocus();
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          StoryTextOverlay(
                            text: _textCtrl.text,
                            x: _textX,
                            y: _textY,
                            colorIndex: _colorIndex,
                            sizeIndex: _sizeIndex,
                            scale: _textScale,
                            withBg: _withBg,
                          ),
                          // ── Tong sampah atas tengah — drag teks ke sini
                          //    untuk hapus (muncul saat teks ada & drag aktif) ──
                          if (_hasText && !_showTextArea)
                            Positioned(
                              top: 8,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Icon(
                                  Icons.delete_outline,
                                  size: 34,
                                  color: _dragOverTrash
                                      ? AppTheme.danger
                                      : Colors.white54,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // ── Area teks interaktif ──
                          if (_showTextArea)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (c.biggest.height * _textY - 60)
                                  .clamp(8.0, c.biggest.height - 200)
                                  .toDouble(),
                              child: GestureDetector(
                                onTap: _onTextTap,
                                onScaleStart: _onScaleStart,
                                onScaleUpdate: (d) =>
                                    _onScale(d, c.biggest),
                                onScaleEnd: _onScaleEnd,
                                child: Center(
                                  child: Container(
                                    width: c.biggest.width - 32,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    // Tanpa border/bubble — teks + kursor
                                    // langsung di tengah foto.
                                    child: TextField(
                                      controller: _textCtrl,
                                      focusNode: _textFocus,
                                      keyboardType: TextInputType.multiline,
                                      maxLines: 3,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: StoryText.size(_sizeIndex) *
                                            _textScale,
                                        fontWeight: FontWeight.w800,
                                        color: _textColor,
                                        height: 1.2,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.6),
                                            blurRadius: 6,
                                            offset: const Offset(1, 1),
                                          ),
                                        ],
                                      ),
                                      cursorColor: Colors.white,
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        hintText: s.storyAddTextHint,
                                        hintStyle: TextStyle(
                                          fontSize:
                                              StoryText.size(_sizeIndex) *
                                                  _textScale,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // ── Tombol "Aa" kanan atas ──
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: _toggleTextArea,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: _showTextArea
                                      ? Colors.white
                                      : Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    'Aa',
                                    style: AppText.label.copyWith(
                                      color: _showTextArea
                                          ? Colors.black
                                          : Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── Overlay bawah: panel gaya + bar visibility —
                  //    naik sejajar keyboard (foto tetap ukuran layar). ──
                  Positioned(
                    left: 0,
                    right: 0,
                    // Keyboard + nav bar Android — panel tak kepotong.
                    bottom: MediaQuery.of(ctx).viewInsets.bottom +
                        MediaQuery.of(ctx).padding.bottom,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showTextArea && _showTextTools)
                          Container(
                            color: Colors.black87,
                            padding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 36,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: StoryText.palette.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (_, i) {
                                      final sel = i == _colorIndex;
                                      return GestureDetector(
                                        onTap: () =>
                                            setState(() => _colorIndex = i),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: StoryText.palette[i],
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: sel
                                                  ? Colors.white
                                                  : Colors.white24,
                                              width: sel ? 3 : 1,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    for (int i = 0; i < 3; i++) ...[
                                      _sizeBtn(s, i),
                                      const SizedBox(width: 8),
                                    ],
                                    const Spacer(),
                                    IconButton(
                                      tooltip: s.storyTextBgTooltip,
                                      onPressed: () =>
                                          setState(() => _withBg = !_withBg),
                                      icon: Icon(
                                        Icons.crop_square_rounded,
                                        color: _withBg
                                            ? AppTheme.primary
                                            : Colors.white38,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        Container(
                          color: Colors.black87,
                          width: double.infinity,
                          padding:
                              const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: _visibilitySelector(s),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sizeBtn(S s, int i) {
    final label = ['S', 'M', 'L'][i];
    final sel = i == _sizeIndex;
    return GestureDetector(
      onTap: () => setState(() => _sizeIndex = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primary : Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppText.label.copyWith(
            color: sel ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _visibilitySelector(S s) {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<String>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            segments: [
              ButtonSegment(
                value: 'everyone',
                label: Text(s.storyVisibilityEveryone,
                    style: AppText.caption),
              ),
              ButtonSegment(
                value: 'registered',
                label: Text(s.storyVisibilityRegistered,
                    style: AppText.caption),
              ),
              ButtonSegment(
                value: 'friends',
                label: Text(s.storyVisibilityFriends,
                    style: AppText.caption),
              ),
            ],
            selected: {_visibility},
            showSelectedIcon: false,
            onSelectionChanged: (v) =>
                setState(() => _visibility = v.first),
          ),
        ),
      ],
    );
  }
}
