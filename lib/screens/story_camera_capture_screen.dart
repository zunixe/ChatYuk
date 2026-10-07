import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils.dart';
import '../providers/riverpod/locale_provider.dart';

/// Hasil jepret/rekam kamera story. `isVideo` dibuat EKSPLISIT (bukan tebak
/// ekstensi file — kamera Xiaomi bisa menyimpan ekstensi tak terduga
/// sehingga video diperlakukan sebagai foto).
class StoryCaptureResult {
  final File file;
  final bool isVideo;
  /// Durasi sumber (ms) — untuk video dari galeri yang perlu dipotong.
  /// 0 = tidak diketahui (komposer menghitung sendiri).
  final int durationMs;
  const StoryCaptureResult(this.file, this.isVideo, {this.durationMs = 0});
}

/// Layar jepret kamera fullscreen — dibuka dari kotak kamera di grid picker.
/// Preview live (depan/belakang), flash, shutter. Return [StoryCaptureResult]
/// (foto atau video), atau null kalau batal.
class StoryCameraCaptureScreen extends StatefulWidget {
  /// Batas durasi rekam (detik). Story = 15 (batas server story); chat = 60.
  final int maxRecordSecs;
  /// Diisi true bila kamera GAGAL init (mis. MIUI menutup pipeline kamera
  /// pihak-ketiga) — supaya pemanggil bisa fallback ke kamera sistem.
  static bool lastInitFailed = false;
  const StoryCameraCaptureScreen({super.key, this.maxRecordSecs = 15});

  @override
  State<StoryCameraCaptureScreen> createState() =>
      _StoryCameraCaptureScreenState();
}

class _StoryCameraCaptureScreenState extends State<StoryCameraCaptureScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _ctrl;
  bool _initializing = true;
  bool _capturing = false;
  int _camIndex = 0;
  FlashMode _flash = FlashMode.off;

  // Rekam video pendek (maks 15 dtk). Mode dipilih eksplisit via tombol
  // kamera/video — tahan shutter saja terbukti tidak ketemu user.
  bool _videoMode = false;
  bool _recording = false;
  bool _startingRecord = false;
  // User melepas jari SEBELUM start selesai (race) → begitu start selesai
  // langsung stop. Tanpa ini: rekam jalan terus, stop tak pernah dipanggil
  // (gejala "muter-muter" tak berujung).
  bool _stopRequested = false;
  // Controller saat ini sudah menyiapkan audio (mode video) — hindari
  // re-init yang bikin delay.
  bool _audioReady = false;
  int _recordSecs = 0;
  Timer? _recordTimer;

  /// Batas durasi rekam — dari widget (story 15 dtk, chat 60 dtk).
  int get kMaxRecordSecs => widget.maxRecordSecs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      _ctrl = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _setup() async {
    StoryCameraCaptureScreen.lastInitFailed = false;
    dlog('[StoryCam] setup start');
    try {
      final st = await Permission.camera.request();
      dlog('[StoryCam] camera permission: $st');
      if (st.isPermanentlyDenied || st.isRestricted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Izin kamera ditolak — aktifkan di Setelan aplikasi'),
            ),
          );
          Navigator.pop(context);
        }
        return;
      }
      if (!st.isGranted && !st.isLimited) {
        if (mounted) Navigator.pop(context);
        return;
      }
    } catch (e) {
      dlog('[StoryCam] permission request error: $e');
    }
    // `availableCameras()` bisa MENGGANTUNG di sebagian perangkat MIUI
    // (camera service lambat/terkunci) → layar kamera jadi hitam selamanya.
    // Timeout + retry supaya tidak nyangkut; gagal total → fallback ke
    // kamera sistem (image_picker) di layar pemanggil.
    _cameras = await _availableCamerasSafe();
    if (_cameras.isEmpty) {
      StoryCameraCaptureScreen.lastInitFailed = true;
      if (mounted) Navigator.pop(context);
      return;
    }
    _camIndex = _cameras
        .indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (_camIndex < 0) _camIndex = 0;
    await _initCamera();
  }

  /// `availableCameras()` dengan timeout + beberapa retry (MIUI kadang
  /// menggantung/balik kosong pada panggilan awal karena camera service
  /// masih sibuk). Total ~3 percobaan. Kosong = gagal.
  Future<List<CameraDescription>> _availableCamerasSafe() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final cams = await availableCameras().timeout(
          const Duration(seconds: 4),
        );
        if (cams.isNotEmpty) return cams;
      } catch (e) {
        dlog('[StoryCam] availableCameras attempt$attempt error: $e');
      }
      // Beri jeda singkat agar camera service sempat melepas lock.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return const <CameraDescription>[];
  }

  Future<void> _initCamera({bool audio = false}) async {
    if (_cameras.isEmpty) return;
    final desc = _cameras[_camIndex];
    final ctrl = CameraController(
      desc,
      ResolutionPreset.high,
      // Audio ON sejak mode video dipilih → tekan shutter langsung rekam
      // (tanpa re-init detik-detik yang bikin race long-press).
      enableAudio: audio,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _ctrl?.dispose();
    _ctrl = ctrl;
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
      await ctrl.setFlashMode(_flash);
    } catch (e) {
      dlog('[StoryCam] init error: $e');
      await ctrl.dispose();
      if (identical(_ctrl, ctrl)) {
        _ctrl = null;
        StoryCameraCaptureScreen.lastInitFailed = true;
        if (mounted) Navigator.pop(context);
      }
      return;
    }
    if (mounted) setState(() => _initializing = false);
  }

  /// Pindah mode foto ⇄ video. Mode video menyiapkan audio di controller
  /// supaya tekan-shutter langsung merekam (tanpa race long-press).
  Future<void> _toggleVideoMode() async {
    if (_recording || _capturing) return;
    final next = !_videoMode;
    setState(() {
      _videoMode = next;
      _initializing = true;
    });
    var audio = false;
    if (next) {
      try {
        final mic = await Permission.microphone.request();
        audio = mic.isGranted || mic.isLimited;
        if (!audio && mounted) {
          final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.storyMicNeeded)),
          );
        }
      } catch (_) {}
    }
    await _initCamera(audio: audio);
    _audioReady = audio;
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording) return;
    _camIndex = (_camIndex + 1) % _cameras.length;
    setState(() => _initializing = true);
    await _initCamera(audio: _audioReady);
  }

  Future<void> _toggleFlash() async {
    _flash = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _ctrl?.setFlashMode(_flash);
    if (mounted) setState(() {});
  }

  /// Tahan shutter = otomatis masuk mode video lalu rekam (tanpa perlu
  /// pindah mode manual). Lepas = stop (lihat onLongPressEnd).
  Future<void> _holdToRecord() async {
    if (_recording || _startingRecord) return;
    if (!_videoMode) {
      // Siapkan audio + mode video dulu, baru mulai rekam.
      await _toggleVideoMode();
    }
    await _startRecord();
  }

  /// Ketuk = jepret (foto) / mulai-stop (video).
  Future<void> _shutter() async {
    if (_startingRecord) return;
    if (_videoMode || _recording) {
      if (_recording) {
        await _stopRecord();
      } else {
        await _startRecord();
      }
      return;
    }
    await _shoot();
  }

  Future<void> _shoot() async {
    final ctrl = _ctrl;
    // Jangan potret saat masih merekam (foto & video tak boleh bareng).
    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        _capturing ||
        _recording ||
        _startingRecord) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final x = await ctrl.takePicture();
      if (!mounted) return;
      Navigator.pop(context, StoryCaptureResult(File(x.path), false));
    } catch (e) {
      dlog('[StoryCam] shoot error: $e');
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _toastRecordFail() {
    if (!mounted) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.storyRecordFail)),
    );
  }

  /// Mulai rekam (tahan shutter): minta mic, re-init controller audio,
  /// auto-stop di batas 15 dtk. SEMUA kegagalan tampil snackbar + kamera
  /// foto dipulihkan (jangan diam / jangan matikan kamera).
  Future<void> _startRecord() async {
    var ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing || _recording) {
      return;
    }
    _startingRecord = true;
    _stopRequested = false;
    // Izin mic hanya saat transisi ke audio (jalur long-press mode foto).
    if (!_audioReady) {
      try {
        final mic = await Permission.microphone.request();
        if (!mic.isGranted && !mic.isLimited) {
          if (mounted) {
            final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.storyMicNeeded)),
            );
          }
          _startingRecord = false;
          return;
        }
      } catch (e) {
        dlog('[StoryCam] mic permission error: $e');
        _toastRecordFail();
        _startingRecord = false;
        return;
      }
      // Audio hanya bisa aktif saat konstruksi controller → buat ulang
      // SEKALI. Jalur normal (mode video dipilih dulu) sudah audio.
      setState(() => _initializing = true);
      await _initCamera(audio: true);
      _audioReady = true;
      ctrl = _ctrl;
      if (ctrl == null || !ctrl.value.isInitialized) {
        _toastRecordFail();
        _startingRecord = false;
        return;
      }
    }
    try {
      await ctrl.startVideoRecording();
    } catch (e) {
      dlog('[StoryCam] start record error: $e');
      _toastRecordFail();
      _startingRecord = false;
      return;
    }
    if (!mounted) {
      _startingRecord = false;
      return;
    }
    setState(() {
      _recording = true;
      _recordSecs = 0;
      _startingRecord = false;
    });
    // Jari sudah dilepas saat masih init → langsung stop (jangan nyangkut).
    if (_stopRequested) {
      _stopRequested = false;
      await _stopRecord();
      return;
    }
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordSecs++);
      if (_recordSecs >= kMaxRecordSecs) _stopRecord();
    });
  }

  Future<void> _stopRecord() async {
    // Lepas saat start masih berjalan → tandai; start yang akan stop.
    if (_startingRecord) {
      _stopRequested = true;
      return;
    }
    final ctrl = _ctrl;
    if (!_recording || ctrl == null) return;
    _recordTimer?.cancel();
    setState(() => _recording = false);
    try {
      final x = await ctrl.stopVideoRecording();
      if (!mounted) return;
      Navigator.pop(context, StoryCaptureResult(File(x.path), true));
    } catch (e) {
      dlog('[StoryCam] stop record error: $e');
      _toastRecordFail();
      // Kembalikan controller foto agar kamera tetap bisa dipakai.
      await _initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _flash == FlashMode.torch
                        ? Icons.flash_on
                        : Icons.flash_off,
                    color: _flash == FlashMode.torch
                        ? Colors.amber
                        : Colors.white54,
                    size: 22,
                  ),
                  onPressed: _toggleFlash,
                ),
                const SizedBox(width: 4),
              ],
            ),
            Expanded(
              child: _initializing ||
                      ctrl == null ||
                      !ctrl.value.isInitialized
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: CameraPreview(ctrl),
                          ),
                          if (_recording)
                            Positioned(
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  '● 0:${_recordSecs.toString().padLeft(2, '0')} '
                                  '/ ${kMaxRecordSecs ~/ 60}:'
                                  '${(kMaxRecordSecs % 60).toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                        Positioned(
                          bottom: 18,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _flipCamera,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                    border:
                                        Border.all(color: Colors.white38),
                                  ),
                                  child: const Icon(Icons.flip_camera_ios,
                                      color: Colors.white, size: 22),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Pilih mode foto / video (ikon saja).
                              GestureDetector(
                                onTap: _toggleVideoMode,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _videoMode
                                        ? Colors.red.withValues(alpha: 0.85)
                                        : Colors.black54,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: _videoMode
                                            ? Colors.red
                                            : Colors.white38),
                                  ),
                                  child: Icon(
                                    _videoMode
                                        ? Icons.videocam_rounded
                                        : Icons.photo_camera_outlined,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              GestureDetector(
                                // Ketuk = jepret (foto) / mulai-stop (video).
                                onTap: _shutter,
                                // TAHAN = langsung rekam video (otomatis
                                // masuk mode video), LEPAS = stop.
                                onLongPressStart: (_) => _holdToRecord(),
                                onLongPressEnd: (_) => _stopRecord(),
                                child: Container(
                                  width: 74,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: _recording
                                            ? Colors.red
                                            : Colors.white,
                                        width: 4),
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
                                            color: _recording
                                                ? Colors.red
                                                : Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 28),
                              const SizedBox(width: 44, height: 44),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
