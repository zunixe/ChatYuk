import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Layar jepret kamera fullscreen — dibuka dari kotak kamera di grid picker.
/// Preview live (depan/belakang), flash, shutter. Return [File] foto hasil
/// jepretan, atau null kalau batal.
class StoryCameraCaptureScreen extends StatefulWidget {
  const StoryCameraCaptureScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    debugPrint('[StoryCam] setup start');
    try {
      final st = await Permission.camera.request();
      debugPrint('[StoryCam] camera permission: $st');
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
      debugPrint('[StoryCam] permission request error: $e');
    }
    try {
      _cameras = await availableCameras();
    } catch (e) {
      debugPrint('[StoryCam] availableCameras error: $e');
    }
    if (_cameras.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _camIndex = _cameras
        .indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (_camIndex < 0) _camIndex = 0;
    await _initCamera();
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;
    final desc = _cameras[_camIndex];
    final ctrl = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _ctrl?.dispose();
    _ctrl = ctrl;
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
      await ctrl.setFlashMode(_flash);
    } catch (e) {
      debugPrint('[StoryCam] init error: $e');
      await ctrl.dispose();
      if (identical(_ctrl, ctrl)) {
        _ctrl = null;
        if (mounted) Navigator.pop(context);
      }
      return;
    }
    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    _camIndex = (_camIndex + 1) % _cameras.length;
    setState(() => _initializing = true);
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    _flash = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _ctrl?.setFlashMode(_flash);
    if (mounted) setState(() {});
  }

  Future<void> _shoot() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final x = await ctrl.takePicture();
      if (!mounted) return;
      Navigator.pop(context, File(x.path));
    } catch (e) {
      debugPrint('[StoryCam] shoot error: $e');
      if (mounted) setState(() => _capturing = false);
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
                              const SizedBox(width: 28),
                              GestureDetector(
                                onTap: _shoot,
                                child: Container(
                                  width: 74,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 4),
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
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
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
