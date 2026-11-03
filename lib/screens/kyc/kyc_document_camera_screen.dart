import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/theme.dart';
import '../../core/kyc/camera_frames.dart';
import '../../core/kyc/image_quality.dart';
import '../../core/kyc/kyc_capture.dart';
import '../../core/kyc/ktp_ocr.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../utils.dart';
import 'widgets/kyc_camera_widgets.dart';

/// Kamera KTP: kamera belakang + bingkai kartu. Tiap ~0,6 dtk frame dicek
/// kualitasnya (tajam / silau / gelap) dan dibaca OCR; saat KTP terbaca
/// (label khas + NIK valid) dan tajam dua kali berturut-turut → dipotret
/// otomatis, lalu foto beresolusi penuh dibaca OCR sekali lagi.
/// Tombol manual muncul setelah beberapa detik (kamera lemah / OCR gagal) —
/// hasilnya ditandai tidak terbaca supaya admin memeriksa lebih teliti.
/// Return [KycDocCapture], atau null bila batal / kamera gagal init
/// ([lastInitFailed] = true → pemanggil fallback ke kamera sistem).
class KycDocumentCameraScreen extends StatefulWidget {
  static bool lastInitFailed = false;

  const KycDocumentCameraScreen({super.key});

  @override
  State<KycDocumentCameraScreen> createState() =>
      _KycDocumentCameraScreenState();
}

enum _DocState { align, dark, glare, blurry, notKtp, hold }

class _KycDocumentCameraScreenState extends State<KycDocumentCameraScreen>
    with WidgetsBindingObserver {
  CameraDescription? _cam;
  CameraController? _ctrl;
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  InputImageRotation _rotation = InputImageRotation.rotation0deg;

  bool _initializing = true;
  bool _permDenied = false;
  bool _capturing = false;
  bool _streamOn = false;
  bool _busy = false;
  bool _manualAllowed = false;
  bool _camInit = false;
  int _goodStreak = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  _DocState _state = _DocState.align;
  KtpOcrResult _bestOcr = KtpOcrResult.empty;
  FrameQuality? _lastQuality;
  Timer? _manualTimer;

  static const _interval = Duration(milliseconds: 600);
  static const _needStreak = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualTimer?.cancel();
    _stopStream();
    _ctrl?.dispose();
    _recognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (state == AppLifecycleState.inactive && ctrl != null) {
      _stopStream();
      setState(() => _ctrl = null);
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed &&
        _ctrl == null &&
        _cam != null &&
        !_camInit) {
      _initCamera();
    }
  }

  Future<void> _setup() async {
    final st = await Permission.camera.request();
    if (!mounted) return;
    if (!st.isGranted && !st.isLimited) {
      setState(() {
        _permDenied = true;
        _initializing = false;
      });
      return;
    }
    List<CameraDescription> cams = const [];
    for (var i = 0; i < 3 && cams.isEmpty; i++) {
      try {
        cams = await availableCameras().timeout(const Duration(seconds: 4));
      } catch (e) {
        dlog('[KycDoc] availableCameras error: $e');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (cams.isEmpty) return _failInit();
    _cam = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    _rotation = rotationForCamera(_cam!);
    await _initCamera();
    _manualTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _manualAllowed = true);
    });
  }

  void _failInit() {
    KycDocumentCameraScreen.lastInitFailed = true;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _initCamera() async {
    if (_camInit) return;
    _camInit = true;
    try {
      await _initCameraInner();
    } finally {
      _camInit = false;
    }
  }

  Future<void> _initCameraInner() async {
    final ctrl = CameraController(
      _cam!,
      // OCR KTP butuh detail teks — high (720p) cukup & masih ringan.
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
      try {
        await ctrl.setFocusMode(FocusMode.auto);
      } catch (_) {}
    } catch (e) {
      dlog('[KycDoc] init error: $e');
      await ctrl.dispose();
      return _failInit();
    }
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    setState(() {
      _ctrl = ctrl;
      _initializing = false;
    });
    _startStream();
  }

  void _startStream() {
    final ctrl = _ctrl;
    if (ctrl == null || _streamOn) return;
    try {
      ctrl.startImageStream(_onFrame);
      _streamOn = true;
    } catch (e) {
      dlog('[KycDoc] stream error: $e');
      setState(() => _manualAllowed = true);
    }
  }

  void _stopStream() {
    final ctrl = _ctrl;
    if (ctrl == null || !_streamOn) return;
    _streamOn = false;
    try {
      ctrl.stopImageStream();
    } catch (_) {}
  }

  void _onFrame(CameraImage img) {
    if (_busy || _capturing || !mounted) return;
    if (DateTime.now().difference(_last) < _interval) return;
    _busy = true;
    _last = DateTime.now();
    final q = cameraFrameQuality(img);
    final input = cameraFrameToInputImage(img, _rotation);
    if (q == null || input == null) {
      _busy = false;
      return;
    }
    _recognizer.processImage(input).then((text) {
      if (!mounted || _capturing) return;
      final ocr = KtpOcr.parse([
        for (final b in text.blocks)
          for (final l in b.lines) l.text,
      ]);
      if (ocr.keywordHits > _bestOcr.keywordHits ||
          (ocr.nik != null && _bestOcr.nik == null)) {
        _bestOcr = ocr;
      }
      _lastQuality = q;
      final next = q.dark
          ? _DocState.dark
          : q.glare
              ? _DocState.glare
              : !q.sharp
                  ? _DocState.blurry
                  : !ocr.looksLikeKtp
                      ? (ocr.keywordHits >= 2 ? _DocState.notKtp : _DocState.align)
                      : _DocState.hold;
      _goodStreak = next == _DocState.hold ? _goodStreak + 1 : 0;
      if (next != _state) setState(() => _state = next);
      if (_goodStreak >= _needStreak) {
        _bestOcr = ocr;
        _capture(auto: true);
      }
    }).catchError((Object e) {
      dlog('[KycDoc] ocr error: $e');
    }).whenComplete(() => _busy = false);
  }

  Future<void> _capture({required bool auto}) async {
    final ctrl = _ctrl;
    if (ctrl == null || _capturing) return;
    setState(() => _capturing = true);
    _stopStream();
    try {
      final x = await ctrl.takePicture();
      // Baca ulang dari foto resolusi penuh — lebih akurat dari frame stream.
      var ocr = _bestOcr;
      try {
        final t = await _recognizer.processImage(InputImage.fromFilePath(x.path));
        final full = KtpOcr.parse([
          for (final b in t.blocks)
            for (final l in b.lines) l.text,
        ]);
        if (full.looksLikeKtp || full.keywordHits > ocr.keywordHits) {
          ocr = KtpOcrResult(
            nik: full.nik ?? ocr.nik,
            name: full.name ?? ocr.name,
            birthDate: full.birthDate ?? ocr.birthDate,
            female: full.female ?? ocr.female,
            keywordHits: full.keywordHits,
          );
        }
      } catch (e) {
        dlog('[KycDoc] still ocr error: $e');
      }
      dlog('[KycDoc] captured auto=$auto ocr=${ocr.toJson()} '
          'q=${_lastQuality?.toJson()}');
      if (!mounted) return;
      Navigator.pop(
        context,
        KycDocCapture(
          path: x.path,
          ocr: ocr,
          quality: _lastQuality,
          auto: auto,
        ),
      );
    } catch (e) {
      dlog('[KycDoc] capture error: $e');
      if (mounted) {
        setState(() => _capturing = false);
        _startStream();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false)
        .read(localeProvider)
        .s;
    final ctrl = _ctrl;
    final ready = _state == _DocState.hold;
    final (hint, color, icon) = switch (_state) {
      _DocState.hold => (s.kycDocHold, kKycOk, Icons.check_circle_outline),
      _DocState.dark => (s.kycDocDark, kKycWarn, Icons.wb_sunny_outlined),
      _DocState.glare => (s.kycDocGlare, kKycWarn, Icons.flare_outlined),
      _DocState.blurry => (s.kycDocBlurry, kKycWarn, Icons.blur_on),
      _DocState.notKtp => (s.kycDocNotKtp, kKycWarn, Icons.badge_outlined),
      _DocState.align => (s.kycDocAlign, Colors.white, Icons.badge_outlined),
    };
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _permDenied
            ? Stack(children: [
                KycCameraPermissionView(s: s),
                const Positioned(top: 8, left: 8, child: KycCloseButton()),
              ])
            : _initializing || ctrl == null || !ctrl.value.isInitialized
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : LayoutBuilder(builder: (context, box) {
                    final card = KycViewfinderPainter.cardRect(box.biggest);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        KycCameraPreview(controller: ctrl),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: KycViewfinderPainter(
                              oval: false,
                              color: ready ? kKycOk : Colors.white,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          top: card.top - 64,
                          child: Text(
                            s.kycPhotoId,
                            textAlign: TextAlign.center,
                            style: AppText.title.copyWith(color: Colors.white),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          top: card.bottom + 20,
                          child: Center(
                            child: KycHintPill(
                              text: _capturing ? s.kycDocHold : hint,
                              color: color,
                              icon: icon,
                            ),
                          ),
                        ),
                        if (_manualAllowed && !ready)
                          Positioned(
                            left: 24,
                            right: 24,
                            bottom: 116,
                            child: Text(
                              s.kycDocManual,
                              textAlign: TextAlign.center,
                              style: AppText.caption
                                  .copyWith(color: Colors.white70),
                            ),
                          ),
                        const Positioned(
                            top: 8, left: 8, child: KycCloseButton()),
                        Positioned(
                          bottom: 28,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: KycShutterButton(
                              enabled: ready || _manualAllowed,
                              busy: _capturing,
                              onTap: () => _capture(auto: false),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
      ),
    );
  }
}
