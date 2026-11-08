import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/strings.dart';
import '../core/kyc/camera_frames.dart';
import '../core/media/face_check.dart';
import '../providers/riverpod/locale_provider.dart';
import '../screens/kyc/widgets/kyc_camera_widgets.dart';
import '../utils.dart';

/// Kamera dalam-app untuk foto profil: wajah dideteksi LIVE di preview dan
/// hint tampil LANGSUNG DI LAYAR KAMERA.
///
/// (Dulu kamera sistem + snackbar → pesan penolakan tertutup layar kamera,
/// user tidak pernah tahu kenapa fotonya ditolak.)
///
/// Perilaku:
/// - Tidak ada wajah → hint "Hadapkan wajah ke kamera", shutter mati.
/// - Lebih dari satu wajah → hint, shutter mati.
/// - Tepat satu wajah → shutter aktif — user JEPRET SENDIRI (tanpa
///   auto-capture, tanpa kerangka/oval; cukup deteksi wajah).
/// - Hasil jepretan dicek ulang (bukan wajah) → pesan DI LAYAR KAMERA,
///   user jepret ulang — tanpa keluar layar.
///
/// Return path file yang lolos, atau null bila batal.
class FaceCaptureCameraScreen extends StatefulWidget {
  const FaceCaptureCameraScreen({super.key});

  @override
  State<FaceCaptureCameraScreen> createState() =>
      _FaceCaptureCameraScreenState();
}

class _FaceCaptureCameraScreenState extends State<FaceCaptureCameraScreen>
    with WidgetsBindingObserver {
  CameraDescription? _cam;
  CameraController? _ctrl;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  // Opsi SAMA dengan FaceCheck (cek file/galeri) — hasil identifikasi
  // konsisten di kedua jalur.
  final _detector = FaceDetector(options: FaceCheck.options);

  bool _initializing = true;
  bool _permDenied = false;
  bool _streamOn = false;
  bool _detecting = false;
  bool _capturing = false;
  int _errors = 0;

  /// Status wajah live: 0 = tidak ada, 1 = tepat satu (ok), >1 = banyak.
  int _faceCount = 0;

  /// Pesan penolakan hasil jepretan (tampil di layar kamera sampai frame
  /// berikutnya mengubah status wajah).
  FaceCheckResult? _captureRejected;

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
        _cam != null) {
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
        dlog('[FaceCam] availableCameras error: $e');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (cams.isEmpty || !mounted) {
      // Kamera tak tersedia → tutup; pemanggil menampilkan pesan.
      if (mounted) Navigator.pop(context);
      return;
    }
    _cam = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    _rotation = rotationForCamera(_cam!);
    await _initCamera();
  }

  Future<void> _initCamera() async {
    final cam = _cam;
    if (cam == null || _ctrl != null) return;
    final ctrl = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    setState(() => _initializing = true);
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
    } catch (e) {
      dlog('[FaceCam] init error: $e');
      await ctrl.dispose();
      if (mounted) Navigator.pop(context);
      return;
    }
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
      dlog('[FaceCam] stream error: $e');
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
    if (_detecting || _capturing || !mounted) return;
    final input = cameraFrameToInputImage(img, _rotation);
    if (input == null) return _onDetectError('format ${img.format.group}');
    _detecting = true;
    _detector
        .processImage(input)
        .then((faces) {
          if (!mounted || _capturing) return;
          _errors = 0;
          _applyFaceState(faces);
        })
        .catchError((Object e) {
          _onDetectError(e);
        })
        .whenComplete(() => _detecting = false);
  }

  void _applyFaceState(List<Face> faces) {
    final changed = faces.length != _faceCount;
    _faceCount = faces.length;
    if (_captureRejected != null && faces.isNotEmpty) {
      _captureRejected = null; // wajah kembali → pesan penolakan hilang
    }
    if (changed || _captureRejected != null) setState(() {});
  }

  void _onDetectError(Object e) {
    dlog('[FaceCam] detect error: $e');
    if (++_errors >= 15 && mounted) setState(() {});
  }

  bool get _detectBroken => _errors >= 15;

  Future<void> _capture() async {
    final ctrl = _ctrl;
    if (ctrl == null || _capturing) return;
    setState(() {
      _capturing = true;
      _captureRejected = null;
    });
    _stopStream();
    try {
      final x = await ctrl.takePicture();
      final r = await FaceCheck.checkFile(x.path);
      if (!mounted) return;
      if (r == FaceCheckResult.ok || r == FaceCheckResult.failed) {
        Navigator.pop(context, x.path);
        return;
      }
      // Bukan wajah → PESAN DI LAYAR KAMERA (bukan snackbar yang ketutup),
      // user jepret ulang tanpa keluar layar.
      setState(() {
        _captureRejected = r;
        _capturing = false;
      });
      try {
        ctrl.startImageStream(_onFrame);
        _streamOn = true;
      } catch (_) {}
    } catch (e) {
      dlog('[FaceCam] capture error: $e');
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
    if (_captureRejected == FaceCheckResult.multiple) {
      return (s.photoVerifyMultiFace, kKycWarn, Icons.group_outlined);
    }
    if (_captureRejected == FaceCheckResult.noFace) {
      return (
        s.photoVerifyNoFace,
        kKycWarn,
        Icons.sentiment_dissatisfied_outlined,
      );
    }
    if (_detectBroken) {
      return (s.faceCamBroken, kKycWarn, Icons.error_outline);
    }
    return switch (_faceCount) {
      0 => (s.faceCamNoFace, Colors.white, Icons.face_outlined),
      1 => (s.faceCamReady, kKycOk, Icons.check_circle_outline),
      _ => (s.faceCamMulti, kKycWarn, Icons.group_outlined),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = _readS(context);
    final ctrl = _ctrl;
    final (hint, color, icon) = _hint(s);
    final faceOk = _faceCount == 1 || _detectBroken;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _permDenied
            ? Stack(
                children: [
                  KycCameraPermissionView(s: s),
                  const Positioned(top: 8, left: 8, child: KycCloseButton()),
                ],
              )
            : _initializing || ctrl == null || !ctrl.value.isInitialized
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  KycCameraPreview(controller: ctrl),
                  // Tanpa kerangka/oval — cukup deteksi wajah + hint.
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 130,
                    child: Center(
                      child: KycHintPill(text: hint, color: color, icon: icon),
                    ),
                  ),
                  const Positioned(top: 4, left: 4, child: KycCloseButton()),
                  Positioned(
                    bottom: 28,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: KycShutterButton(
                        enabled: faceOk,
                        busy: _capturing,
                        onTap: _capture,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  S _readS(BuildContext context) =>
      ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
}

/// Layar penolakan: menampilkan FOTO yang ditolak + alasannya LANGSUNG di
/// layar (bukan dialog/snackbar yang bisa tertutup layar lain), plus aksi
/// "Pilih Foto Lagi" / "Batal".
class FaceRejectPreviewScreen extends StatelessWidget {
  final String path;
  final FaceCheckResult result;

  const FaceRejectPreviewScreen({
    super.key,
    required this.path,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final msg = result == FaceCheckResult.multiple
        ? s.photoVerifyMultiFace
        : s.photoVerifyNoFace;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: Image.file(File(path), fit: BoxFit.contain)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xF2000000), Color(0x00000000)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KycHintPill(
                      text: msg,
                      color: kKycWarn,
                      icon: Icons.face_outlined,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(s.btnCancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(s.photoVerifyRetry),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(top: 4, left: 4, child: KycCloseButton()),
          ],
        ),
      ),
    );
  }
}
