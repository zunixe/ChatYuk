import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;

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
  // Resize sisi TERPANJANG ke 1440 — foto portrait maupun landscape tetap
  // tajam satu layar HP saat ditampilkan fit di viewer (tanpa crop).
  final isPortrait = decoded.height >= decoded.width;
  final resized = isPortrait
      ? img.copyResize(decoded, height: 1440)
      : img.copyResize(decoded, width: 1440);
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
  double _textY = 0.36;
  // Skala pinch-to-zoom (1 jari = geser, 2 jari = besar/kecil + putar).
  double _textScale = 1.0;
  double _scaleBase = 1.0;
  double _textRotation = 0;
  double _rotationBase = 0;
  // Drag teks ke tong sampah (atas tengah) → teks dihapus ala IG.
  bool _dragOverTrash = false;
  int _colorIndex = StoryText.defaultColorIndex;
  int _sizeIndex = 1;
  bool _withBg = false;
  // Default: anon = public (dikunci server), registered = pengikut.
  String _visibility = 'followers';
  bool _publishing = false;
  bool _showTextTools = false;
  // Panel alat aktif di atas bar tombol: '' (tidak ada), 'size', 'color'.
  String _toolsPanel = '';
  bool _showTextArea = false;
  // Mode edit (keyboard) vs select (drag). TextField HANYA tampil saat
  // edit — saat select tampil teks statis supaya drag selalu sampai
  // ke detector area (tidak direbut TextField → kadang bisa kadang tidak).
  bool _textEditing = false;
  // Rebuild HANYA saat teks kosong↔isi (untuk ikon sampah). Ketikan
  // per-huruf TIDAK rebuild — full-rebuild tiap huruf balapan dengan
  // IME dan terbukti menutup keyboard sendiri di composer.
  bool _textWasEmpty = true;
  // Drag teks sedang berjalan (1 jari di area teks) — tong sampah tampil.
  bool _textDragging = false;
  // Gestur saat ini menggeser TEKS (routing manual di 1 detector —
  // tanpa arena, tanpa balapan). False = foto / mati.
  bool _draggingText = false;
  // Posisi tap (lokal kartu) — untuk bedakan tap teks vs tap foto.
  Offset? _tapDownLocal;

  // ── Transformasi foto (zoom/putar/geser) — di-bake ke gambar saat publish ──
  double _imgScale = 1.0;
  double _imgScaleBase = 1.0;
  double _imgRotation = 0;
  double _imgRotationBase = 0;
  Offset _imgOffset = Offset.zero;

  Color get _textColor => _colorIndex >= 0 &&
          _colorIndex < StoryText.palette.length
      ? StoryText.palette[_colorIndex]
      : StoryText.palette.first;

  bool get _hasText => _textCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Nav bar Android opaque hitam selama composer aktif — tanpa ini
    // area bawah (menu android) transparan/translusen karena edge-to-edge.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    // Nav bar DISEMBUNYIKAN selama composer aktif — tumit jempol sering
    // nyenggol tombol back 3-button saat ngetik → keyboard ketutup sendiri
    // padahal fokus tidak hilang. Back tetap via tombol AppBar + gesture.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    // Anon dipaksa public (server juga menegakkan) — set sejak awal
    // supaya UI langsung benar dan nilai terkirim pasti 'everyone'.
    if (context.read<AuthProvider>().isAnonymous) {
      _visibility = 'everyone';
    }
    _textCtrl.addListener(() {
      final empty = _textCtrl.text.trim().isEmpty;
      if (empty != _textWasEmpty) {
        _textWasEmpty = empty;
        if (mounted) setState(() {});
      }
    });
    _textFocus.addListener(() {
      final editing = _textFocus.hasFocus;
      if (editing != _textEditing && mounted) {
        setState(() => _textEditing = editing);
      }
    });
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.picked.readAsBytes();
    if (!mounted) return;
    setState(() => _bytes = bytes);
    try {
      final b64 = await compute(_processStoryImage, bytes);
      if (!mounted) return;
      setState(() => _b64 = b64);
    } catch (e) {
      debugPrint('[StoryComposer] process error: $e');
      // Fallback: pakai bytes mentah — send tidak pernah mati permanen.
      if (!mounted) return;
      setState(() => _b64 = base64Encode(bytes));
    }
  }

  /// Render foto dgn transformasi jadi PNG bytes (untuk dibake ke final).
  Future<Uint8List> _renderTransformed(Uint8List src) async {
    final codec =
        await ui.instantiateImageCodec(src, targetWidth: 1080);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0,
        image.width.toDouble(), image.height.toDouble()));
    canvas.translate(image.width / 2, image.height / 2);
    canvas.rotate(_imgRotation);
    canvas.scale(_imgScale);
    canvas.translate(-image.width / 2 + _imgOffset.dx,
        -image.height / 2 + _imgOffset.dy);
    canvas.drawImage(image, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
        image.width, image.height);
    final data = await rendered.toByteData(
        format: ui.ImageByteFormat.png);
    image.dispose();
    rendered.dispose();
    return data!.buffer.asUint8List();
  }

  @override
  void dispose() {
    // Kembalikan nav bar default (transparan) saat keluar composer.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    if (uid == null || _bytes == null) return;
    setState(() => _publishing = true);
    try {
      // Bake transformasi (zoom/rotasi/geser) + teks ke gambar final.
      final transformed = _imgScale != 1.0 ||
              _imgRotation != 0 ||
              _imgOffset != Offset.zero
          ? await _renderTransformed(_bytes!)
          : _bytes!;
      final b64 = await compute(_processStoryImage, transformed);
      final path = await StoragePhotoService.instance
          .uploadStoryImage(uid: uid, base64: b64);
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
    _rotationBase = _textRotation;
  }

  void _onScale(ScaleUpdateDetails d, Size boxSize) {
    setState(() {
      _textScale = (_scaleBase * d.scale).clamp(0.5, 3.0);
      _textRotation = _rotationBase + d.rotation;
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
      _deleteText();
      return;
    }
    if (_dragOverTrash || _textDragging) {
      setState(() {
        _dragOverTrash = false;
        _textDragging = false;
      });
    }
  }

  /// Hapus teks (drag ke sampah / tap ikon sampah saat teks kepilih).
  void _deleteText() {
    setState(() {
      _textCtrl.clear();
      _showTextArea = false;
      _showTextTools = false;
      _toolsPanel = '';
      _dragOverTrash = false;
      _textDragging = false;
      _draggingText = false;
      _textScale = 1.0;
      _textRotation = 0;
      _textX = 0.5;
      _textY = 0.36;
    });
    _textFocus.unfocus();
  }

  // ── UX teks ala IG ──
  // Tombol "T" kanan atas foto → munculkan area teks DI ATAS foto (posisi
  // = posisi overlay nanti). Tap area teks → panel warna + ukuran.
  // Typing langsung di dalam foto; drag di luar area teks = pindahkan.
  void _toggleTextArea() {
    setState(() {
      _showTextArea = !_showTextArea;
      if (_showTextArea) {
        _showTextTools = true;
        // TextField harus ADA di tree dulu sebelum fokus diminta.
        _textEditing = true;
      }
    });
    if (_showTextArea) {
      _textCtrl.selection =
          TextSelection.collapsed(offset: _textCtrl.text.length);
      // Tunggu rebuild selesai baru minta fokus (keyboard).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocus.requestFocus();
      });
    } else {
      _textFocus.unfocus();
    }
  }

  /// Tinggi kartu foto (pixel) — dipakai hitung posisi absolut TextField
  /// edit di layer atas (posisi teks statis pakai koordinat kartu).
  double _cardHeight(BuildContext ctx) {
    return MediaQuery.of(ctx).size.height -
        MediaQuery.of(ctx).padding.top -
        40 /* AppBar */ -
        20 /* top offset kartu */ -
        (MediaQuery.of(ctx).padding.bottom + 68) /* bottom offset */;
  }

  TextStyle _composerTextStyle() {    return TextStyle(
      fontSize: StoryText.size(_sizeIndex) * _textScale,
      fontWeight: FontWeight.w800,
      color: _textColor,
      height: 1.2,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.6),
          blurRadius: 6,
          offset: const Offset(1, 1),
        ),
      ],
    );
  }

  /// Preview teks mode SELECT — gaya identik TextField edit supaya
  /// tidak ada lompatan visual saat pindah mode.
  Widget _selectPreview(S s) {
    final t = _textCtrl.text;
    final body = t.isEmpty
        ? Text(
            s.storyAddTextHint,
            style: TextStyle(
              fontSize: StoryText.size(_sizeIndex) * _textScale,
              fontWeight: FontWeight.w800,
              color: Colors.white38,
            ),
            textAlign: TextAlign.center,
          )
        : Text(
            t,
            style: _composerTextStyle(),
            textAlign: TextAlign.center,
          );
    if (!_withBg || t.isEmpty) return body;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return PopScope(
      canPop: false,
      // Back (sistem/gesture) → konfirmasi dulu, jangan langsung keluar.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
      // Foto TETAP seukuran layar walau keyboard muncul — panel bawah
      // naik sejajar keyboard lewat viewInsets (foto tidak dimenezkan).
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      // Toolbar ATAS DIPENDEK — maksimalkan ruang foto (toolbar default
      // M3 56px + title besar makan layar; story butuh preview maksimal).
      appBar: AppBar(
        toolbarHeight: 40,
        backgroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: _confirmExit,
        ),
        title: Text(
          s.storyComposerTitle,
          style: AppText.bodyStrong.copyWith(color: Colors.white),
        ),
        actions: [
          if (_publishing)
            const Padding(
              padding: EdgeInsets.all(10),
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
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.send_rounded,
                  color: AppTheme.primary, size: 20),
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
                  // ── Kartu foto = ukuran story di viewer (WYSIWYG) ──
                  // Body mulai di bawah AppBar 40px → top:20 badan =
                  // padTop+60 absolut (pas dengan kartu viewer). Bottom
                  // padBottom+68 = ruang kolom balasan di viewer.
                  // Border putih tipis = batas area story yang jelas.
                  Positioned(
                    top: 20,
                    bottom: MediaQuery.of(ctx).padding.bottom + 68,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white24,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        // Foto TETAP — tidak mengecil/redup saat ketik teks.
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..translate(_imgOffset.dx, _imgOffset.dy)
                            ..rotateZ(_imgRotation)
                            ..scale(_imgScale),
                          child: Image.memory(_bytes!,
                              // COVER (fill) — foto memenuhi kartu
                              // persis seperti tampil di viewer nanti
                              // (WYSIWYG). Kelebihan zoom ter-clip rapi,
                              // tidak transparan.
                              fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                  // ── Gesture: teks aktif → kontrol teks; else → foto ──
                  Positioned(
                    top: 20,
                    bottom:
                        MediaQuery.of(ctx).padding.bottom + 68,
                    left: 0,
                    right: 0,
                    child: LayoutBuilder(
                      builder: (kctx, k) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // SATU detector untuk semua gestur kartu (tanpa arena).
                      // MODE TEKS (_showTextArea): SEMUA gestur hanya ke teks
                      // — foto DIKUNCI total (tidak bisa ke-zoom/putar/geser
                      // walau cubit dimulai di luar teks). Selesai teks
                      // (tap luar / Aa) baru foto bisa dipilih lagi.
                      // MODE FOTO: semua gestur ke foto.
                      onScaleStart: (d) {
                        _draggingText = false;
                        _imgScaleBase = _imgScale;
                        _imgRotationBase = _imgRotation;
                        if (_showTextArea) {
                          _onScaleStart(d);
                        }
                      },
                      onScaleUpdate: (d) {
                        if (!_showTextArea) {
                          // FOTO: zoom/putar/geser.
                          setState(() {
                            _imgScale =
                                (_imgScaleBase * d.scale).clamp(1.0, 5.0);
                            _imgRotation =
                                _imgRotationBase + d.rotation;
                            _imgOffset += d.focalPointDelta;
                          });
                          return;
                        }
                        // TEKS: saat ngetik (keyboard kebuka), 1 jari milik
                        // kursor TextField — jangan rebut. Selain itu
                        // (keyboard tutup / 2 jari) semua ke teks.
                        if (_textFocus.hasFocus && d.pointerCount < 2) {
                          return;
                        }
                        if (!_draggingText) {
                          _draggingText = true;
                          if (!_textDragging) {
                            setState(() => _textDragging = true);
                          }
                        }
                        _onScale(d, k.biggest);
                      },
                      onScaleEnd: (d) {
                        if (_draggingText) {
                          _draggingText = false;
                          _onScaleEnd(d);
                        }
                      },
                      onTapDown: (d) {
                        _tapDownLocal =
                            (kctx.findRenderObject() as RenderBox?)
                                ?.globalToLocal(d.globalPosition);
                      },
                      // 1 tap teks = SELECT (bisa digeser ke sampah).
                      // 2 tap teks = EDIT (keyboard). Tap gambar = foto.
                      onDoubleTap: () {
                        // Keyboard lagi kebuka → abaikan semua.
                        if (_textFocus.hasFocus) return;
                        // Double-tap TEPAT di teks → mode edit (keyboard).
                        final p = _tapDownLocal;
                        if (!_hasText || p == null) return;
                        final w = k.biggest.width;
                        final h = k.biggest.height;
                        final hit =
                            (p.dx - _textX * w).abs() < w * 0.35 &&
                                (p.dy - _textY * h).abs() < 120;
                        if (!hit) return;
                        setState(() {
                          _showTextArea = true;
                          _showTextTools = true;
                          // TextField harus ADA di tree dulu sebelum fokus.
                          _textEditing = true;
                        });
                        _textCtrl.selection = TextSelection.collapsed(
                            offset: _textCtrl.text.length);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _textFocus.requestFocus();
                        });
                      },
                      onTap: () {
                        // Keyboard lagi kebuka → tap luar diabaikan
                        // (keyboard cuma tutup via Aa / back / publish).
                        // Jadi ngetik tidak pernah ketutup sendiri.
                        if (_textFocus.hasFocus) return;
                        final p = _tapDownLocal;
                        _tapDownLocal = null;
                        if (p == null) return;
                        final w = k.biggest.width;
                        final h = k.biggest.height;
                        // Tap IKON SAMPAH saat teks kepilih → hapus langsung.
                        if (_showTextArea &&
                            _hasText &&
                            (p.dx - w / 2).abs() < 40 &&
                            p.dy < 60) {
                          _deleteText();
                          return;
                        }
                        // Tap kena teks yang sudah jadi → SELECT / EDIT.
                        // Tap gambar → pilih gambar (mode foto).
                        if (_hasText) {
                          final hitText =
                              (p.dx - _textX * w).abs() < w * 0.35 &&
                                  (p.dy - _textY * h).abs() < 120;
                          if (hitText) {
                            // Lagi ngetik (fokus di TextField) → jangan
                            // ganggu (tap ini untuk pindah kursor).
                            if (_textFocus.hasFocus) return;
                            if (_showTextArea) {
                              // Sudah kepilih → tap lagi = EDIT (keyboard).
                              // (Double-tap sering kalah arena vs pinch,
                              // jadi tap-kedua jadi jalan utama.)
                              setState(() {
                                _showTextTools = true;
                                _textEditing = true;
                              });
                              _textCtrl.selection =
                                  TextSelection.collapsed(
                                      offset: _textCtrl.text.length);
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                if (mounted) _textFocus.requestFocus();
                              });
                            } else {
                              // Belum kepilih → SELECT (bisa drag ke sampah).
                              setState(() {
                                _showTextArea = true;
                                _showTextTools = true;
                              });
                            }
                            return;
                          }
                        }
                        if (_showTextTools || _showTextArea) {
                          setState(() {
                            _showTextTools = false;
                            _showTextArea = false;
                            _toolsPanel = '';
                          });
                          _textFocus.unfocus();
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Preview disembunyikan saat mode ketik (TextField
                          // yang tampil) — kalau dua-duanya aktif teks dobel.
                          if (!_showTextArea)
                            StoryTextOverlay(
                              text: _textCtrl.text,
                              x: _textX,
                              y: _textY,
                              colorIndex: _colorIndex,
                              sizeIndex: _sizeIndex,
                              scale: _textScale,
                              rotation: _textRotation,
                              withBg: _withBg,
                            ),
                          // ── Tong sampah atas tengah — drag teks ke sini
                          // untuk hapus (selalu tampil kalau teks ada:
                          // terlihat saat select, drag, maupun preview) ──
                          if (_hasText)
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
                        ],
                      ),
                    ),
                    ),
                  ),
                  // ── Area teks: DI LUAR semua gesture detector (struktur
                  // persis kolom chat — tanpa arena, tanpa onDoubleTap).
                  // SELECT = teks statis (IgnorePointer, drag via detector
                  // luar). EDIT = TextField live. Posisi identik keduanya.
                  if (_showTextArea)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (MediaQuery.of(ctx).padding.top +
                              60 +
                              _cardHeight(ctx) * _textY -
                              60)
                          .clamp(
                              MediaQuery.of(ctx).padding.top + 60,
                              MediaQuery.of(ctx).padding.top +
                                  60 +
                                  _cardHeight(ctx) -
                                  200)
                          .toDouble(),
                      child: Center(
                        child: Transform.rotate(
                          angle: _textRotation,
                          child: Container(
                            width: MediaQuery.of(ctx).size.width - 32,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            child: _textEditing
                                ? TextField(
                                    controller: _textCtrl,
                                    focusNode: _textFocus,
                                    keyboardType: TextInputType.multiline,
                                    maxLines: 3,
                                    textAlign: TextAlign.center,
                                    style: _composerTextStyle(),
                                    cursorColor: Colors.white,
                                    textInputAction: TextInputAction.newline,
                                    decoration: InputDecoration(
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      hintText: s.storyAddTextHint,
                                      hintStyle: TextStyle(
                                        fontSize: StoryText.size(_sizeIndex) *
                                            _textScale,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  )
                                : IgnorePointer(
                                    child: _selectPreview(s),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  // ── Tombol "Aa" kanan atas kartu — SEJAJAR body (di luar
                  // detector gestur supaya tap-nya tidak bocor ke bawah).
                  Positioned(
                    top: 28,
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
                  // ── Overlay bawah: panel gaya + bar visibility —
                  //    naik sejajar keyboard + TIDAK overlap nav bar. ──
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
                                // Bar ukuran — muncul saat tombol "T" dipilih.
                                if (_toolsPanel == 'size')
                                  SizedBox(
                                    height: 36,
                                    child: Row(
                                      children: [
                                        for (int i = 0; i < 3; i++) ...[
                                          _sizeBtn(s, i),
                                          const SizedBox(width: 8),
                                        ],
                                      ],
                                    ),
                                  ),
                                // Bar warna — muncul saat tombol warna dipilih.
                                if (_toolsPanel == 'color')
                                  SizedBox(
                                    height: 36,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: StoryText.palette.length,
                                      separatorBuilder: (_, _) =>
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
                                // Dua tombol: ukuran (T) + warna. Klik =
                                // toggle bar opsinya di atas.
                                Row(
                                  children: [
                                    _toolToggle(
                                      icon: Icons.title_rounded,
                                      label: 'T',
                                      active: _toolsPanel == 'size',
                                      onTap: () => setState(() =>
                                          _toolsPanel = _toolsPanel == 'size'
                                              ? ''
                                              : 'size'),
                                    ),
                                    const SizedBox(width: 10),
                                    _toolToggle(
                                      icon: Icons.palette_outlined,
                                      label: '',
                                      active: _toolsPanel == 'color',
                                      onTap: () => setState(() =>
                                          _toolsPanel = _toolsPanel == 'color'
                                              ? ''
                                              : 'color'),
                                    ),
                                    const Spacer(),
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
      ),
    );
  }

  /// Back → konfirmasi dulu (Buang / Lanjut). Langsung keluar hanya
  /// kalau belum ada edit (teks kosong + foto utuh) atau saat publish.
  Future<void> _confirmExit() async {
    if (_publishing) return;
    final dirty = _hasText ||
        _imgScale != 1.0 ||
        _imgRotation != 0 ||
        _imgOffset != Offset.zero;
    if (!dirty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final s = context.read<LocaleProvider>().s;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.storyDiscardTitle),
        content: Text(s.storyDiscardMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.storyKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.storyDiscardYes,
              style: AppText.button.copyWith(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Widget _toolToggle({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 36,
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: label.isNotEmpty
            ? Center(
                child: Text(
                  label,
                  style: AppText.label.copyWith(
                    color: active ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : Icon(icon, size: 20, color: active ? Colors.white : Colors.white70),
      ),
    );
  }

  Widget _sizeBtn(S s, int i) {    final label = ['S', 'M', 'L'][i];
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
    final isAnon = context.read<AuthProvider>().isAnonymous;
    // Anon: HANYA public — dikunci server (dipaksa 'everyone').
    if (isAnon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.public, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              s.storyVisibilityEveryone,
              style: AppText.caption.copyWith(color: Colors.white),
            ),
          ],
        ),
      );
    }
    // Registered: semua orang / pengikut / teman (default pengikut).
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
                value: 'followers',
                label: Text(s.storyVisibilityFollowers,
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
