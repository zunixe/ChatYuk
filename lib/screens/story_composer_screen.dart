import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui' as ui;

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/media/native_image.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/story_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../widgets/story_text_overlay.dart';
import 'dart:convert';
import 'dart:io';
import 'package:video_player/video_player.dart';

part 'story_composer/story_composer_media.dart';
part 'story_composer/story_composer_edit.dart';
part 'story_composer/story_composer_build.dart';


/// Baca file story di isolate (bytes mentah tak menyeberang ke main thread).
/// Kompresi di NATIVE (`NativeImage.processStory` / `processRawRgba`) +
/// fallback Dart (lib/core/media/chat_photo_helper.dart).
Uint8List _readStoryFile(String path) => File(path).readAsBytesSync();

/// Halaman buat story: preview foto 9:16 + teks overlay (drag bebas,
/// warna/ukuran/latar) + pilih visibility. Anon tidak sampai ke sini
/// (tombol + tersembunyi; RLS server juga menolak).
class StoryComposerScreen extends ConsumerStatefulWidget {
  final XFile picked;
  /// Penanda video EKSPLISIT dari kamera/galeri — jangan tebak dari
  /// ekstensi file (kamera Xiaomi bisa menyimpan ekstensi lain sehingga
  /// video diperlakukan sebagai foto).
  final bool isVideo;
  const StoryComposerScreen({
    super.key,
    required this.picked,
    this.isVideo = false,
  });

  @override
  ConsumerState<StoryComposerScreen> createState() => _StoryComposerScreenState();
}

/// State + field bersama StoryComposerScreen — dipakai mixin (file `part`).
abstract class _StoryComposerBase extends ConsumerState<StoryComposerScreen> {
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

  // ── VIDEO ──
  /// Video dari kamera ATAU galeri (penanda eksplisit; ekstensi fallback).
  bool get _isVideo {
    if (widget.isVideo) return true;
    final p = widget.picked.path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.3gp') ||
        p.endsWith('.mkv') ||
        p.endsWith('.webm');
  }

  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _videoError = false;
  double? _compressPct;
  int _segIndex = 0;
  // Tahan (long-press) pada video = jeda sementara untuk melihat.
  bool _holdPaused = false;
  // Segmen potongan: tiap 15 dtk, MAKS 2 segmen (video >60s → 2 pertama).
  List<({int startMs, int durMs})> _segments = const [];
  static const int _segLenMs = 15000;
  static const int _maxSegments = 2;

  static List<({int startMs, int durMs})> _planSegments(int totalMs) {
    final out = <({int startMs, int durMs})>[];
    var start = 0;
    while (out.length < _maxSegments && start < totalMs) {
      final remaining = totalMs - start;
      if (remaining < 1000) break; // server butuh >= 1 dtk
      final dur = remaining > _segLenMs ? _segLenMs : remaining;
      out.add((startMs: start, durMs: dur));
      start += _segLenMs;
    }
    return out;
  }

  // Kontrak lintas-mixin.
  bool get _hasText;
  Color get _textColor;
  Future<void> _publish();
  Future<void> _publishVideo();
  Future<Uint8List> _renderTransformed(Uint8List src);
  void _deleteText();
  void _toggleTextArea();
  Widget _videoBody(S s);
  double _cardHeight(BuildContext ctx);
  TextStyle _composerTextStyle();
  Widget _selectPreview(S s);
  Widget _visibilitySelector(S s);
  void _onScaleStart(ScaleStartDetails d);
  void _onScale(ScaleUpdateDetails d, Size boxSize);
  void _onScaleEnd(ScaleEndDetails d);

}


class _StoryComposerScreenState extends _StoryComposerBase
    with _ScMediaMx, _ScEditMx, _ScBuildMx {
}
