import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../utils.dart';

/// Layar kamera selfie KYC — preview kamera depan dengan panduan oval
/// DI DALAM viewfinder (gelap di luar oval) + deteksi wajah real-time
/// ML Kit di image stream:
///  - tepat 1 wajah & menghadap lurus → oval hijau + shutter aktif
///  - 0 wajah / >1 wajah / menoleh   → oval abu + shutter nonaktif
/// Return `XFile` foto jepretan, atau null bila batal/gagal init
/// (pemicu fallback ke image_picker di pemanggil).
class KycSelfieCameraScreen extends StatefulWidget {
  /// true bila pop terjadi karena init GAGAL (bukan user membatalkan) —
  /// pemanggil fallback ke kamera sistem. Pola sama dgn
  /// StoryCameraCaptureScreen.lastInitFailed.
  static bool lastInitFailed = false;

  const KycSelfieCameraScreen({super.key});

  @override
  State<KycSelfieCameraScreen> createState() =>
      _KycSelfieCameraScreenState();
}

enum _FaceState { none, multiple, notStraight, ready }

class _KycSelfieCameraScreenState extends State<KycSelfieCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _ctrl;
  bool _initializing = true;
  bool _capturing = false;
  int _camIndex = -1;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;

  FaceDetector? _detector;
  bool _streamOn = false;
  bool _detecting = false;
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);
  _FaceState _faceState = _FaceState.none;

  static const _detectInterval = Duration(milliseconds: 350);
  static const _maxYawDeg = 20.0;
  // Wajah minimal 18% lebar frame — terlalu jauh → dianggap tak valid.
  static const _minFaceWidthRatio = 0.18;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStream();
    _detector?.close();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopStream();
      ctrl.dispose();
      _ctrl = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _setup() async {
    try {
      final st = await Permission.camera.request();
      if (!st.isGranted && !st.isLimited) {
        if (mounted) Navigator.pop(context);
        return;
      }
    } catch (e) {
      dlog('[KycCam] permission error: $e');
    }
    _cameras = await _availableCamerasSafe();
    if (_cameras.isEmpty) {
      KycSelfieCameraScreen.lastInitFailed = true;
      if (mounted) Navigator.pop(context);
      return;
    }
    // Kamera depan untuk selfie.
    _camIndex = _cameras
        .indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    if (_camIndex < 0) _camIndex = 0;
    _rotation = InputImageRotationValue.fromRawValue(
            _cameras[_camIndex].sensorOrientation) ??
        InputImageRotation.rotation0deg;
    _detector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );
    await _initCamera();
  }

  /// Sama dengan StoryCameraCaptureScreen — `availableCameras()` bisa
  /// menggantung di MIUI; timeout + retry.
  Future<List<CameraDescription>> _availableCamerasSafe() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final cams =
            await availableCameras().timeout(const Duration(seconds: 4));
        if (cams.isNotEmpty) return cams;
      } catch (e) {
        dlog('[KycCam] availableCameras attempt$attempt error: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return const <CameraDescription>[];
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;
    final ctrl = CameraController(
      _cameras[_camIndex],
      ResolutionPreset.medium, // deteksi stream tidak butuh resolusi besar
      enableAudio: false,
      // nv21 = format yang langsung diterima ML Kit di Android —
      // hindari perakitan manual plane yuv420.
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await _ctrl?.dispose();
    _ctrl = ctrl;
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
    } catch (e) {
      dlog('[KycCam] init error: $e');
      await ctrl.dispose();
      if (identical(_ctrl, ctrl)) {
        _ctrl = null;
        KycSelfieCameraScreen.lastInitFailed = true;
        if (mounted) Navigator.pop(context); // pemanggil fallback picker
      }
      return;
    }
    if (mounted) setState(() => _initializing = false);
    _startStream();
  }

  // ── Deteksi wajah real-time di image stream ────────────────────────────

  void _startStream() {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _streamOn) return;
    try {
      ctrl.startImageStream(_onFrame);
      _streamOn = true;
    } catch (e) {
      dlog('[KycCam] startImageStream error: $e');
      // Gagal stream → tetap bisa jepret manual tanpa gate wajah.
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
    final detector = _detector;
    if (detector == null ||
        _detecting ||
        _capturing ||
        !mounted ||
        DateTime.now().difference(_lastDetect) < _detectInterval) {
      return;
    }
    _detecting = true;
    _lastDetect = DateTime.now();
    final input = _toInputImage(img);
    if (input == null) {
      _detecting = false;
      return;
    }
    detector.processImage(input).then((faces) {
      if (!mounted) return;
      setState(() => _faceState = _classify(faces, img));
    }).catchError((Object e) {
      dlog('[KycCam] detect error: $e');
    }).whenComplete(() => _detecting = false);
  }

  InputImage? _toInputImage(CameraImage img) {
    // Hanya jalur nv21 (Android) yang disupport — format lain → lewati
    // deteksi stream (jepret tetap divalidasi post-capture).
    if (img.format.group != ImageFormatGroup.nv21 ||
        img.planes.isEmpty) {
      return null;
    }
    return InputImage.fromBytes(
      bytes: img.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(img.width.toDouble(), img.height.toDouble()),
        rotation: _rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: img.planes.first.bytesPerRow,
      ),
    );
  }

  _FaceState _classify(List<Face> faces, CameraImage img) {
    if (faces.isEmpty) return _FaceState.none;
    if (faces.length > 1) return _FaceState.multiple;
    final f = faces.first;
    // Menoleh terlalu jauh kiri/kanan → bukan selfie frontal.
    final yaw = f.headEulerAngleY?.abs() ?? 0;
    if (yaw > _maxYawDeg) return _FaceState.notStraight;
    // Terlalu jauh dari kamera (wajah kecil di frame).
    if (f.boundingBox.width < img.width * _minFaceWidthRatio) {
      return _FaceState.notStraight;
    }
    return _FaceState.ready;
  }

  // ── Jepret ─────────────────────────────────────────────────────────────

  Future<void> _shoot() async {
    final ctrl = _ctrl;
    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        _capturing ||
        _faceState != _FaceState.ready) {
      return;
    }
    setState(() => _capturing = true);
    _stopStream();
    try {
      final x = await ctrl.takePicture();
      if (!mounted) return;
      Navigator.pop(context, x);
    } catch (e) {
      dlog('[KycCam] shoot error: $e');
      if (mounted) {
        setState(() => _capturing = false);
        _startStream();
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false)
        .read(localeProvider)
        .s;
    final ctrl = _ctrl;
    final ready = _faceState == _FaceState.ready;
    final hint = switch (_faceState) {
      _FaceState.ready => s.kycCamReady,
      _FaceState.multiple => s.kycCamMulti,
      _FaceState.notStraight => s.kycCamLookStraight,
      _FaceState.none => s.kycFaceGuide,
    };
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _initializing || ctrl == null || !ctrl.value.isInitialized
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(ctrl),
                  // Overlay gelap + oval panduan; warna mengikuti status.
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _FaceOvalOverlayPainter(
                        color: ready
                            ? const Color(0xFF2ECC71)
                            : Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  // Teks panduan di bawah oval.
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: MediaQuery.of(context).size.height * 0.20,
                    child: Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: AppText.bodyStrong.copyWith(
                        color: ready
                            ? const Color(0xFF2ECC71)
                            : Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Positioned(
                    bottom: 28,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _shoot,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ready ? Colors.white : Colors.white38,
                              width: 4,
                            ),
                          ),
                          child: _capturing
                              ? const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Container(
                                  margin: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: ready
                                        ? const Color(0xFF2ECC71)
                                        : Colors.white24,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Overlay viewfinder: seluruh layar digelapkan KECUALI oval wajah di
/// tengah (teknik even-odd fill seperti overlay kartu di app eKYC),
/// plus border oval berwarna status.
class _FaceOvalOverlayPainter extends CustomPainter {
  final Color color;
  const _FaceOvalOverlayPainter({required this.color});

  static Rect _oval(Size size) => Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.42),
        width: size.width * 0.62,
        height: size.height * 0.42,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _oval(size);
    // Gelapkan area di luar oval (fillType evenOdd → lubang di oval).
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(rect);
    canvas.drawPath(
      dim,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_FaceOvalOverlayPainter old) => old.color != color;
}
