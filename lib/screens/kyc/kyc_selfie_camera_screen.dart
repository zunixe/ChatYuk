import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../core/kyc/camera_frames.dart';
import '../../core/kyc/kyc_capture.dart';
import '../../core/kyc/liveness.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../utils.dart';
import 'widgets/kyc_camera_widgets.dart';

/// Kamera wajah KYC dengan LIVENESS: wajah lurus di oval → tantangan acak
/// (kedip, toleh kiri-kanan) → hadap lurus → dipotret OTOMATIS. Wajah yang
/// berganti di tengah proses (tracking id berubah) mengulang dari awal —
/// mencegah foto/video orang lain disodorkan sebagian.
///
/// Bila deteksi tidak jalan di device ini (stream/ML Kit gagal terus),
/// tombol manual muncul dan hasilnya ditandai `live=false` (admin cek).
/// Return [KycSelfieCapture], atau null bila batal / init gagal
/// ([lastInitFailed] = true → pemanggil fallback ke kamera sistem).
class KycSelfieCameraScreen extends StatefulWidget {
  static bool lastInitFailed = false;

  const KycSelfieCameraScreen({super.key});

  @override
  State<KycSelfieCameraScreen> createState() => _KycSelfieCameraScreenState();
}

class _KycSelfieCameraScreenState extends State<KycSelfieCameraScreen>
    with WidgetsBindingObserver {
  CameraDescription? _cam;
  CameraController? _ctrl;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableClassification: true, // probabilitas mata terbuka (kedip)
      enableTracking: true, // id wajah konsisten antar frame
      minFaceSize: 0.2,
    ),
  );
  final _tracker = LivenessTracker();

  bool _initializing = true;
  bool _permDenied = false;
  bool _camInit = false;
  bool _streamOn = false;
  bool _detecting = false;
  bool _capturing = false;
  bool _manualAllowed = false;
  int _errors = 0;
  bool _showRestart = false;
  Timer? _restartTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restartTimer?.cancel();
    _stopStream();
    _ctrl?.dispose();
    _detector.close();
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
        dlog('[KycFace] availableCameras error: $e');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (cams.isEmpty) return _failInit();
    _cam = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    _rotation = rotationForCamera(_cam!);
    await _initCamera();
  }

  void _failInit() {
    KycSelfieCameraScreen.lastInitFailed = true;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _initCamera() async {
    if (_camInit) return;
    _camInit = true;
    final ctrl = CameraController(
      _cam!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
    } catch (e) {
      dlog('[KycFace] init error: $e');
      await ctrl.dispose();
      _camInit = false;
      return _failInit();
    }
    _camInit = false;
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    setState(() {
      _ctrl = ctrl;
      _initializing = false;
    });
    try {
      ctrl.startImageStream(_onFrame);
      _streamOn = true;
    } catch (e) {
      dlog('[KycFace] stream error: $e');
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
    // Tanpa jeda tetap: kedip hanya ±200 ms, jadi setiap frame diproses
    // selama detektor tidak sibuk.
    if (_detecting || _capturing || !mounted) return;
    final input = cameraFrameToInputImage(img, _rotation);
    if (input == null) return _onDetectError('format ${img.format.group}');
    _detecting = true;
    _detector.processImage(input).then((faces) {
      if (!mounted || _capturing) return;
      _errors = 0;
      final sample = _toSample(faces, img);
      final before = _tracker.phase;
      final phase = _tracker.feed(sample);
      if (_tracker.restarted) _flashRestart();
      if (phase == LivenessPhase.done) {
        _capture(live: true);
      } else if (phase != before || _tracker.current != null) {
        setState(() {});
      }
    }).catchError((Object e) {
      _onDetectError(e);
    }).whenComplete(() => _detecting = false);
  }

  void _onDetectError(Object e) {
    dlog('[KycFace] detect error: $e');
    if (++_errors >= 15 && !_manualAllowed && mounted) {
      setState(() => _manualAllowed = true);
    }
  }

  FaceSample _toSample(List<Face> faces, CameraImage img) {
    if (faces.isEmpty) return FaceSample.none;
    if (faces.length > 1) return FaceSample(count: faces.length);
    final f = faces.first;
    // Ukuran frame setelah rotasi (sensor portrait-kan 90/270°).
    final rotated = _rotation == InputImageRotation.rotation90deg ||
        _rotation == InputImageRotation.rotation270deg;
    final fw = rotated ? img.height : img.width;
    final fh = rotated ? img.width : img.height;
    final box = f.boundingBox;
    final cx = box.center.dx / fw;
    final cy = box.center.dy / fh;
    final framed = box.width >= fw * 0.30 &&
        (cx - 0.5).abs() < 0.2 &&
        (cy - 0.45).abs() < 0.25;
    return FaceSample(
      count: 1,
      trackingId: f.trackingId,
      yaw: f.headEulerAngleY ?? 0,
      pitch: f.headEulerAngleX ?? 0,
      leftEye: f.leftEyeOpenProbability,
      rightEye: f.rightEyeOpenProbability,
      framed: framed,
    );
  }

  void _flashRestart() {
    _restartTimer?.cancel();
    setState(() => _showRestart = true);
    _restartTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showRestart = false);
    });
  }

  Future<void> _capture({required bool live}) async {
    final ctrl = _ctrl;
    if (ctrl == null || _capturing) return;
    setState(() => _capturing = true);
    _stopStream();
    try {
      final x = await ctrl.takePicture();
      if (!mounted) return;
      Navigator.pop(
        context,
        KycSelfieCapture(
          path: x.path,
          live: live,
          steps: List.of(_tracker.completed),
        ),
      );
    } catch (e) {
      dlog('[KycFace] capture error: $e');
      if (mounted) {
        setState(() => _capturing = false);
        try {
          ctrl.startImageStream(_onFrame);
          _streamOn = true;
        } catch (_) {}
      }
    }
  }

  (String, Color, IconData) _hint(S s) {
    if (_showRestart) return (s.kycLiveRestart, kKycWarn, Icons.refresh);
    return switch (_tracker.phase) {
      LivenessPhase.multiple => (s.kycCamMulti, kKycWarn, Icons.group_outlined),
      LivenessPhase.position =>
        (s.kycFaceGuide, Colors.white, Icons.face_outlined),
      LivenessPhase.challenge => _tracker.current == LivenessChallenge.blink
          ? (s.kycLiveBlink, Colors.white, Icons.remove_red_eye_outlined)
          : (s.kycLiveTurn, Colors.white, Icons.swap_horiz),
      LivenessPhase.straight ||
      LivenessPhase.done =>
        (s.kycLiveStraight, kKycOk, Icons.check_circle_outline),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false)
        .read(localeProvider)
        .s;
    final ctrl = _ctrl;
    final (hint, color, icon) = _hint(s);
    final done = _tracker.phase == LivenessPhase.straight ||
        _tracker.phase == LivenessPhase.done;
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
                    final oval = KycViewfinderPainter.ovalRect(box.biggest);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        KycCameraPreview(controller: ctrl),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: KycViewfinderPainter(
                              oval: true,
                              color: done ? kKycOk : Colors.white,
                              progress: _tracker.progress,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          top: 16,
                          child: Text(
                            s.kycLiveProgress(
                              _tracker.step,
                              _tracker.totalSteps,
                            ),
                            textAlign: TextAlign.center,
                            style: AppText.label.copyWith(color: Colors.white70),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          top: oval.bottom + 24,
                          child: Center(
                            child: KycHintPill(
                              text: hint,
                              color: color,
                              icon: icon,
                            ),
                          ),
                        ),
                        const Positioned(
                            top: 4, left: 4, child: KycCloseButton()),
                        if (_manualAllowed || _capturing)
                          Positioned(
                            bottom: 28,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: KycShutterButton(
                                enabled: _manualAllowed,
                                busy: _capturing,
                                onTap: () => _capture(live: false),
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
