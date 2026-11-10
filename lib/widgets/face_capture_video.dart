import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/kyc/camera_frames.dart';
import '../core/media/face_check.dart';
import '../providers/riverpod/locale_provider.dart';
import '../screens/kyc/widgets/kyc_camera_widgets.dart';
import '../utils.dart';

/// Kamera dalam-app untuk REKAM VIDEO profil dengan verifikasi wajah LIVE
/// DI LAYAR REKAM (kewajiban akun female).
///
/// (Sebelumnya: kamera sistem → verifikasi wajah dijalankan SETELAH rekaman
/// selesai — user tidak melihat status wajah saat merekam.)
///
/// Perilaku:
/// - 0 wajah / >1 wajah → hint merah di layar, tombol rekam MATI.
/// - Tepat satu wajah → tombol rekam aktif.
/// - Saat stop, video diperiksa cepat (sampling frame) dengan spinner
///   "Memeriksa wajah…" DI LAYAR REKAM; gagal → video dihapus + pesan tetap
///   di layar ini, user rekam ulang tanpa keluar layar.
/// - Auto-stop di [maxMs] (default 30 dtk).
///
/// CATATAN (JANGAN DIUBAH tanpa cek ulang): rekaman TIDAK memakai
/// `startVideoRecording` dengan frame-callback. Callback + video capture
/// bersamaan memicu bug plugin `camera_android_camerax` (issue #180075):
/// PREVIEW berputar 90° / tampak "wide" selama merekam (file video tetap
/// benar). Karena itu stream frame hanya dipakai di preview idle (sebelum
/// rekam) dan verifikasi hasil rekaman dilakukan setelah stop — tetap di
/// layar ini.
///
/// Return path file video yang lolos, atau null bila batal.
class FaceCaptureVideoScreen extends StatefulWidget {
  /// Durasi maksimum rekaman (auto-stop).
  final int maxMs;
  const FaceCaptureVideoScreen({super.key, this.maxMs = 30000});

  @override
  State<FaceCaptureVideoScreen> createState() => _FaceCaptureVideoScreenState();
}

class _FaceCaptureVideoScreenState extends State<FaceCaptureVideoScreen>
    with WidgetsBindingObserver {
  CameraDescription? _cam;
  CameraController? _ctrl;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  // Opsi SAMA dengan FaceCheck (cek file/galeri) — hasil identik.
  final _detector = FaceDetector(options: FaceCheck.options);

  bool _initializing = true;
  bool _permDenied = false;
  bool _micGranted = false;
  bool _streamOn = false;
  bool _detecting = false;
  bool _stopping = false;
  int _errors = 0;

  /// Status wajah live: 0 = tidak ada, 1 = tepat satu (ok), >1 = banyak.
  int _faceCount = 0;

  bool _recording = false;
  bool _checking = false;
  final Stopwatch _rec = Stopwatch();
  Timer? _tick;

  /// Pesan penolakan hasil rekaman (tampil di layar sampai wajah kembali).
  String? _rejectMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _stopStream();
    final c = _ctrl;
    _ctrl = null;
    if (c != null) {
      // Masih merekam (mis. app ditutup) → hentikan supaya file tidak
      // menggantung di recorder native.
      if (_recording) {
        unawaited(_discardRecording(c));
      }
      c.dispose();
    }
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (state == AppLifecycleState.inactive && ctrl != null) {
      _tick?.cancel();
      _tick = null;
      _stopStream();
      setState(() => _ctrl = null);
      if (_recording) unawaited(_discardRecording(ctrl));
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
    // Mikrofon opsional: ditolak → rekam tanpa audio (jangan blokir).
    try {
      final m = await Permission.microphone.request();
      _micGranted = m.isGranted || m.isLimited;
    } catch (e) {
      dlog('[FaceVideo] mic permission error: $e');
      _micGranted = false;
    }
    List<CameraDescription> cams = const [];
    for (var i = 0; i < 3 && cams.isEmpty; i++) {
      try {
        cams = await availableCameras().timeout(const Duration(seconds: 4));
      } catch (e) {
        dlog('[FaceVideo] availableCameras error: $e');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (cams.isEmpty || !mounted) {
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
      // 720p: target kompres galeri 720p — jangan upscale dari 480p.
      ResolutionPreset.high,
      enableAudio: _micGranted,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    setState(() => _initializing = true);
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
    } catch (e) {
      dlog('[FaceVideo] init error: $e');
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
    _resumeIdleStream();
  }

  void _resumeIdleStream() {
    final ctrl = _ctrl;
    if (ctrl == null || _streamOn) return;
    try {
      ctrl.startImageStream(_onFrame);
      _streamOn = true;
    } catch (e) {
      dlog('[FaceVideo] stream error: $e');
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

  /// Frame stream IDLE (preview sebelum merekam) — status wajah live.
  /// Stream dimatikan selama merekam (lihat catatan bug plugin di atas).
  void _onFrame(CameraImage img) {
    if (_detecting || _stopping || _recording || !mounted) return;
    final input = cameraFrameToInputImage(img, _rotation);
    if (input == null) return _onDetectError('format ${img.format.group}');
    _detecting = true;
    _detector
        .processImage(input)
        .then((faces) {
          if (!mounted || _stopping) return;
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
    final hadReject = _rejectMsg != null;
    if (hadReject && faces.isNotEmpty) _rejectMsg = null;
    if (changed || hadReject) setState(() {});
  }

  void _onDetectError(Object e) {
    dlog('[FaceVideo] detect error: $e');
    if (++_errors >= 15 && mounted) setState(() {});
  }

  bool get _detectBroken => _errors >= 15;

  bool get _faceOk => _faceCount == 1 || _detectBroken;

  Future<void> _startRecording() async {
    final ctrl = _ctrl;
    if (ctrl == null || _recording || _stopping || _checking || !_faceOk) {
      return;
    }
    setState(() => _rejectMsg = null);
    // Stream idle dimatikan. Rekaman TANPA frame-callback: callback +
    // video capture bersamaan membuat PREVIEW berputar 90° (bug plugin
    // camera_android_camerax #180075 — "tampilan jadi wide" saat merekam).
    _stopStream();
    try {
      await ctrl.startVideoRecording();
    } catch (e) {
      dlog('[FaceVideo] start error: $e');
      _resumeIdleStream();
      return;
    }
    if (!mounted) return;
    _rec
      ..reset()
      ..start();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_rec.elapsedMilliseconds >= widget.maxMs) {
        unawaited(_stopRecording());
      } else {
        setState(() {}); // timer UI
      }
    });
    setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    final ctrl = _ctrl;
    if (ctrl == null || !_recording || _stopping) return;
    _tick?.cancel();
    _tick = null;
    setState(() => _stopping = true);
    _rec.stop();
    XFile? file;
    try {
      file = await ctrl.stopVideoRecording();
    } catch (e) {
      dlog('[FaceVideo] stop error: $e');
    }
    if (!mounted) return;
    if (file == null) {
      setState(() {
        _recording = false;
        _stopping = false;
        _rejectMsg = _readS(context).faceCamVideoReject;
      });
      _resumeIdleStream();
      return;
    }
    // Verifikasi DI LAYAR REKAM (spinner) — sampling frame dari file hasil.
    setState(() => _checking = true);
    final check = await FaceCheck.checkVideo(
      file.path,
      durationMs: _rec.elapsedMilliseconds,
    );
    if (!mounted) return;
    // `failed` (detektor tak tersedia) diloloskan — pola sama foto.
    final pass = check == FaceCheckResult.ok || check == FaceCheckResult.failed;
    if (pass) {
      Navigator.pop(context, file.path);
      return;
    }
    // Gagal verifikasi → TETAP DI LAYAR REKAM, pesan tampil di sini.
    try {
      await File(file.path).delete();
    } catch (e) {
      dlog('[FaceVideo] delete rejected error: $e');
    }
    setState(() {
      _recording = false;
      _stopping = false;
      _checking = false;
      _rejectMsg = _readS(context).faceCamVideoReject;
    });
    _resumeIdleStream();
  }

  /// Hentikan + buang rekaman yang sedang berjalan (batal/tutup app).
  Future<void> _discardRecording(CameraController ctrl) async {
    try {
      final f = await ctrl.stopVideoRecording();
      await File(f.path).delete();
    } catch (e) {
      dlog('[FaceVideo] discard error: $e');
    }
  }

  Future<void> _cancel() async {
    final ctrl = _ctrl;
    if (ctrl != null && _recording) {
      _tick?.cancel();
      _tick = null;
      await _discardRecording(ctrl);
    }
    if (mounted) Navigator.pop(context);
  }

  (String, Color, IconData) _hint(S s) {
    if (_checking) {
      return (s.faceCamChecking, Colors.white, Icons.face_retouching_natural);
    }
    if (_rejectMsg != null) {
      return (_rejectMsg!, kKycWarn, Icons.sentiment_dissatisfied_outlined);
    }
    if (_detectBroken) {
      return (s.faceCamBroken, kKycWarn, Icons.error_outline);
    }
    // Selama merekam stream frame mati (bug plugin) → hint statis jujur.
    if (_recording) {
      return (s.faceCamRecHint, Colors.white, Icons.videocam_outlined);
    }
    return switch (_faceCount) {
      0 => (s.faceCamNoFace, Colors.white, Icons.face_outlined),
      1 => (s.faceCamStartRec, kKycOk, Icons.check_circle_outline),
      _ => (s.faceCamMulti, kKycWarn, Icons.group_outlined),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = _readS(context);
    final ctrl = _ctrl;
    final (hint, color, icon) = _hint(s);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _permDenied
            ? Stack(
                children: [
                  KycCameraPermissionView(s: s),
                  Positioned(top: 8, left: 8, child: _closeBtn()),
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
                  if (_recording)
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _RecTimer(
                          elapsedMs: _rec.elapsedMilliseconds,
                          maxMs: widget.maxMs,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 130,
                    child: Center(
                      child: KycHintPill(text: hint, color: color, icon: icon),
                    ),
                  ),
                  Positioned(top: 4, left: 4, child: _closeBtn()),
                  Positioned(
                    bottom: 28,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _RecordButton(
                        enabled: _faceOk && !_stopping && !_checking,
                        recording: _recording,
                        busy: _stopping || _checking,
                        onTap: _recording ? _stopRecording : _startRecording,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _closeBtn() => IconButton(
    icon: const Icon(Icons.close, color: Colors.white, size: 24),
    onPressed: _cancel,
  );

  S _readS(BuildContext context) =>
      ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
}

/// Tombol rekam: lingkaran putih berisi bulatan merah; saat merekam berubah
/// jadi kotak merah (stop). Persis pola kamera bawaan HP.
class _RecordButton extends StatelessWidget {
  final bool enabled;
  final bool recording;
  final bool busy;
  final VoidCallback onTap;

  const _RecordButton({
    required this.enabled,
    required this.recording,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled && !busy ? onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: enabled ? Colors.white : Colors.white38,
          width: 4,
        ),
      ),
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: recording ? 28 : 58,
                height: recording ? 28 : 58,
                decoration: BoxDecoration(
                  color: enabled ? Colors.redAccent : Colors.white24,
                  borderRadius: BorderRadius.circular(recording ? 6 : 29),
                ),
              ),
            ),
    ),
  );
}

/// Badge durasi rekam: "0:07 / 0:30" (angka — tidak perlu diterjemahkan).
class _RecTimer extends StatelessWidget {
  final int elapsedMs;
  final int maxMs;
  const _RecTimer({required this.elapsedMs, required this.maxMs});

  static String _fmt(int ms) {
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final sec = total % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${_fmt(elapsedMs)} / ${_fmt(maxMs)}',
            style: AppText.caption.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
