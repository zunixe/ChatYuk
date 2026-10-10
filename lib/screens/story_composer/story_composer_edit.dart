part of '../story_composer_screen.dart';

// ignore_for_file: unused_element

mixin _ScEditMx on _StoryComposerBase {
  void dispose() {
    // Kembalikan nav bar default saat keluar composer (tanpa warna —
    // API warna deprecated di Android 15, lihat initState).
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _videoCtrl?.dispose();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final uid = auth.uid;
    if (uid == null || _bytes == null) return;
    setState(() => _publishing = true);
    try {
      // Bake transformasi (zoom/rotasi/geser) + teks ke gambar final.
      final transformed =
          _imgScale != 1.0 || _imgRotation != 0 || _imgOffset != Offset.zero
          ? await _renderTransformed(_bytes!)
          : _bytes!;
      final b64 = await NativeImage.processStory(transformed);
      if (b64 == null || b64.isEmpty) throw Exception('compress_failed');
      final path = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(storageProvider).uploadStoryImage(uid: uid, base64: b64);
      if (path == null || path.isEmpty) throw Exception('upload_failed');
      final ok = await ProviderScope.containerOf(context, listen: false)
          .read(storyProvider.notifier)
          .publish(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.storyPublishFail)));
      }
    } catch (e) {
      dlog('[StoryComposer] publish error: $e');
      if (mounted) {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.storyPublishFail)));
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
        _textX = (_textX + d.focalPointDelta.dx / boxSize.width).clamp(
          0.0,
          1.0,
        );
        _textY = (_textY + d.focalPointDelta.dy / boxSize.height).clamp(
          0.0,
          1.0,
        );
      }
      // Zona hapus: atas tengah (di bawah ikon tong sampah).
      _dragOverTrash = _textY < 0.10 && (_textX - 0.5).abs() < 0.18;
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
      _textCtrl.selection = TextSelection.collapsed(
        offset: _textCtrl.text.length,
      );
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

  TextStyle _composerTextStyle() {
    return TextStyle(
      fontSize: StoryText.size(_sizeIndex) * _textScale,
      fontWeight: FontWeight.w800,
      color: _textColor,
      height: StoryText.lineHeight,
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
        : Text(t, style: _composerTextStyle(), textAlign: TextAlign.center);
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
}
