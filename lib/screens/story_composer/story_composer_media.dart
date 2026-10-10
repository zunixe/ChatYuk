part of '../story_composer_screen.dart';

// ignore_for_file: unused_element

mixin _ScMediaMx on _StoryComposerBase {
  Future<void> _initVideo() async {
    final ctrl = VideoPlayerController.file(File(widget.picked.path));
    _videoCtrl = ctrl;
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 15));
      await ctrl.setLooping(true);
      await ctrl.play();
    } catch (e) {
      dlog('[StoryComposer] video init error: $e');
      if (mounted) setState(() => _videoError = true);
      return;
    }
    if (!mounted) return;
    final ms = ctrl.value.duration.inMilliseconds;
    if (ms < 1000) {
      if (mounted) {
        final s = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(localeProvider).s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.storyVideoTooShort)));
        Navigator.pop(context);
      }
      return;
    }
    _segments = _StoryComposerBase._planSegments(ms);
    if (mounted) setState(() => _videoReady = true);
  }

  /// Publish video: potong per 15 dtk (maks 2 segmen) → tiap segmen jadi
  /// satu story. Poster 1 frame jadi thumbnail tray.
  Future<void> _publishVideo() async {
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
    final ctrl = _videoCtrl;
    if (uid == null || ctrl == null || !ctrl.value.isInitialized) return;
    final storage = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(storageProvider);
    final storyProv = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(storyProvider.notifier);
    final segs = _segments.isEmpty
        ? _StoryComposerBase._planSegments(ctrl.value.duration.inMilliseconds)
        : _segments;
    if (segs.isEmpty) return;
    setState(() {
      _publishing = true;
      _compressPct = 0;
      _segIndex = 0;
    });
    try {
      var published = 0;
      for (var i = 0; i < segs.length; i++) {
        if (mounted) setState(() => _segIndex = i);
        final seg = segs[i];
        // 1) Potong + kompres segmen (≤15 dtk) → 720p hemat.
        final out = await storage.compressStoryVideo(
          widget.picked.path,
          startMs: seg.startMs,
          durationMs: seg.durMs,
          onProgress: (p) {
            if (mounted) setState(() => _compressPct = p);
          },
        );
        if (out == null || !await out.exists()) {
          throw Exception('compress_fail');
        }
        final bytes = await out.readAsBytes();
        if (bytes.lengthInBytes > 20 * 1024 * 1024) {
          throw Exception('too_big');
        }
        // 2) Poster (thumbnail tray).
        String posterPath = '';
        final poster = await storage.storyVideoPoster(out.path);
        if (poster != null && poster.isNotEmpty) {
          posterPath =
              await storage.uploadStoryImage(
                uid: uid,
                base64: base64Encode(poster),
              ) ??
              '';
        }
        // 3) Upload video + publish.
        final path = await storage.uploadStoryVideo(uid: uid, bytes: bytes);
        if (path == null || path.isEmpty) throw Exception('upload_failed');
        final ok = await storyProv.publish(
          imagePath: posterPath,
          videoPath: path,
          durationMs: seg.durMs,
          visibility: _visibility,
          myUid: uid,
          myNickname: auth.profile?.nickname ?? 'Anon',
          myAvatar: auth.profile?.avatar ?? '',
        );
        if (ok) published++;
      }
      if (!mounted) return;
      if (published > 0) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _publishing = false;
          _compressPct = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.storyPublishFail)));
      }
    } catch (e) {
      dlog('[StoryComposer] publish video error: $e');
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _compressPct = null;
      });
      final msg = '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.contains('too_big')
                ? s.storyVideoTooBig
                : msg.contains('compress_fail')
                ? s.storyCompressFail
                : s.storyPublishFail,
          ),
        ),
      );
    }
  }

  /// Body video: preview loop + kontrol play/pause (ketuk) & tahan-lihat.
  Widget _videoBody(S s) {
    final ctrl = _videoCtrl;
    final ready = _videoReady && ctrl != null && ctrl.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: _videoError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_off_outlined,
                        color: Colors.white54,
                        size: 48,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.storyRecordFail,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  )
                : !ready
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: ctrl.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(ctrl),
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => setState(() {
                            ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                            _holdPaused = false;
                          }),
                          onLongPressStart: (_) async {
                            if (ctrl.value.isPlaying) await ctrl.pause();
                            if (mounted) setState(() => _holdPaused = true);
                          },
                          onLongPressEnd: (_) async {
                            if (!mounted) return;
                            setState(() => _holdPaused = false);
                            await ctrl.play();
                          },
                          onLongPressCancel: () async {
                            if (!mounted) return;
                            if (_holdPaused) {
                              setState(() => _holdPaused = false);
                              await ctrl.play();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              ctrl.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        if (_compressPct != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _segments.length > 1
                  ? '${s.storyCompressing} ${(_compressPct! * 100).round()}% '
                        '(${_segIndex + 1}/${_segments.length})'
                  : '${s.storyCompressing} ${(_compressPct! * 100).round()}%',
              style: const TextStyle(color: Colors.white70),
            ),
          )
        else if (ready) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${(ctrl.value.duration.inMilliseconds / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          if (_segments.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
              child: Text(
                s.storyVideoSplitInfo,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: Colors.white54),
              ),
            ),
        ],
        Container(
          color: Colors.black87,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: _visibilitySelector(s),
        ),
      ],
    );
  }

  Color get _textColor =>
      _colorIndex >= 0 && _colorIndex < StoryText.palette.length
      ? StoryText.palette[_colorIndex]
      : StoryText.palette.first;

  bool get _hasText => _textCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Android 15: setStatusBarColor/setNavigationBarColor DEPRECATED
    // (Play menolak). Jangan isi systemNavigationBarColor — Scaffold hitam
    // + edge-to-edge transparan memberi visual yang sama tanpa API lama.
    // Hanya ikon terang + matikan scrim kontras bawaan sistem.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    // Nav bar DISEMBUNYIKAN selama composer aktif — tumit jempol sering
    // nyenggol tombol back 3-button saat ngetik → keyboard ketutup sendiri
    // padahal fokus tidak hilang. Back tetap via tombol AppBar + gesture.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    // Anon dipaksa public (server juga menegakkan) — set sejak awal
    // supaya UI langsung benar dan nilai terkirim pasti 'everyone'.
    if (ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier).isAnonymous) {
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
    if (_isVideo) {
      _initVideo();
    } else {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    // Baca file di isolate (bytes mentah 5-10MB tak menyeberang ke main),
    // lalu kompres di NATIVE via NativeImage.processStory (fallback Dart).
    try {
      final bytes = await compute(_readStoryFile, widget.picked.path);
      final b64 = await NativeImage.processStory(bytes);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _b64 = b64 ?? '';
      });
    } catch (e) {
      dlog('[StoryComposer] process error: $e');
      // Fallback: read di main thread, kirim apa adanya.
      try {
        final bytes = await widget.picked.readAsBytes();
        if (!mounted) return;
        setState(() {
          _bytes = bytes;
          _b64 = base64Encode(bytes);
        });
      } catch (e2) {
        dlog('[StoryComposer] fallback read error: $e2');
      }
    }
  }

  /// Render foto dgn transformasi jadi bytes JPEG (untuk dibake ke final).
  ///
  /// PERF: dulu `toByteData(png)` — PNG encode besar & lambat. Sekarang ambil
  /// pixel mentah (rawRgba, tanpa kompresi), lalu encode JPEG di isolate
  /// terpisah (`compute`) supaya tidak jank UI dan hasil jauh lebih kecil.
  Future<Uint8List> _renderTransformed(Uint8List src) async {
    final codec = await ui.instantiateImageCodec(src, targetWidth: 1080);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    );
    canvas.translate(image.width / 2, image.height / 2);
    canvas.rotate(_imgRotation);
    canvas.scale(_imgScale);
    canvas.translate(
      -image.width / 2 + _imgOffset.dx,
      -image.height / 2 + _imgOffset.dy,
    );
    canvas.drawImage(image, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(image.width, image.height);
    final w = rendered.width;
    final h = rendered.height;
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    rendered.dispose();
    final raw = data!.buffer.asUint8List();
    // Encode JPEG di NATIVE (rawRgba → JPEG q90; fallback Dart di isolate).
    return (await NativeImage.processRawRgba(raw, w, h, quality: 90))!;
  }
}
