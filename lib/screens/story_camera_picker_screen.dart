import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';

/// Picker foto story ala Instagram — GALERI DULU:
/// - Grid 3 kolom foto + video recent (tile pertama = kamera)
/// - Badge durasi di tile video
/// - Tap tile kamera → mode capture dalam halaman yang sama
/// - Tap foto → kembali bawa [File] ke composer
/// - Tap video → toast "segera hadir" (pipeline video story belum ada)
///
/// Return [File] foto atau null kalau batal. Kamera di-init LAZY
/// (saat tile kamera diklik) supaya buka galeri instan tanpa prompt kamera.
class StoryCameraPickerScreen extends StatefulWidget {
  const StoryCameraPickerScreen({super.key});

  @override
  State<StoryCameraPickerScreen> createState() =>
      _StoryCameraPickerScreenState();
}

class _StoryCameraPickerScreenState extends State<StoryCameraPickerScreen>
    with WidgetsBindingObserver {
  /// false = grid galeri, true = mode kamera.
  bool _showCamera = false;

  List<CameraDescription> _cameras = [];
  CameraController? _ctrl;
  bool _initializingCam = false;
  bool _capturing = false;
  int _camIndex = 0;
  FlashMode _flash = FlashMode.off;

  /// Galeri foto+video recent (paginasi).
  final List<AssetEntity> _gallery = [];
  final Set<String> _thumbKeys = {};
  final Map<String, Uint8List?> _thumbs = {};
  final ScrollController _scrollCtrl = ScrollController();
  int _page = 0;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _noPermission = false;
  static const int _pageSize = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _loadGallery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed && _showCamera) {
      _initCamera();
    }
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 600) {
      _loadGallery();
    }
  }

  Future<void> _loadGallery() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth) {
        if (mounted) {
          setState(() {
            _noPermission = true;
            _loadingMore = false;
          });
        }
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (mounted) setState(() => _loadingMore = false);
        return;
      }
      final assets =
          await albums.first.getAssetListPaged(page: _page, size: _pageSize);
      if (assets.length < _pageSize) _hasMore = false;
      if (mounted) {
        setState(() {
          _gallery.addAll(assets);
          _page++;
          _loadingMore = false;
        });
      }
      // Thumbnail paralel per batch kecil.
      for (final a in assets) {
        final key = a.id;
        if (_thumbKeys.contains(key)) continue;
        _thumbKeys.add(key);
        a.thumbnailDataWithSize(const ThumbnailSize(300, 300)).then((b) {
          if (mounted) setState(() => _thumbs[key] = b);
        });
      }
    } catch (e) {
      debugPrint('[StoryCam] gallery error: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openCamera() async {
    setState(() => _showCamera = true);
    if (_cameras.isEmpty) {
      try {
        _cameras = await availableCameras();
      } catch (_) {}
    }
    if (_cameras.isEmpty) {
      // Tanpa kamera — kembali ke grid.
      if (mounted) setState(() => _showCamera = false);
      return;
    }
    _camIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (_camIndex < 0) _camIndex = 0;
    await _initCamera();
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;
    if (mounted) setState(() => _initializingCam = true);
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
      await ctrl.initialize();
      await ctrl.setFlashMode(_flash);
    } catch (e) {
      debugPrint('[StoryCam] init error: $e');
    }
    if (mounted) setState(() => _initializingCam = false);
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    _camIndex = (_camIndex + 1) % _cameras.length;
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

  Future<void> _pickAsset(AssetEntity asset) async {
    if (asset.type == AssetType.video) {
      if (!mounted) return;
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.storyVideoSoon)),
      );
      return;
    }
    try {
      final f = await asset.file;
      if (f != null && mounted) Navigator.pop(context, f);
    } catch (_) {}
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _closeCamera() async {
    await _ctrl?.dispose();
    _ctrl = null;
    if (mounted) setState(() => _showCamera = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showCamera) return _buildCamera();
    final s = MediaQuery.of(context).size;
    final tile = (s.width - 2) / 3; // 3 kolom, gap 1px
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Bar atas: tutup ──
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            // ── Grid: tile kamera + foto/video recent ──
            Expanded(
              child: _noPermission
                  ? const Center(
                      child: Icon(Icons.photo_library_outlined,
                          color: Colors.white38, size: 48),
                    )
                  : _gallery.isEmpty && !_loadingMore
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : GridView.builder(
                          controller: _scrollCtrl,
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 1,
                            crossAxisSpacing: 1,
                          ),
                          itemCount: _gallery.length + 1,
                          itemBuilder: (_, i) {
                            // Tile pertama = kamera.
                            if (i == 0) return _cameraTile(tile);
                            final a = _gallery[i - 1];
                            final thumb = _thumbs[a.id];
                            final isVideo = a.type == AssetType.video;
                            return GestureDetector(
                              onTap: () => _pickAsset(a),
                              child: Container(
                                color: Colors.white10,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (thumb != null)
                                      Image.memory(thumb,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true),
                                    if (isVideo)
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            _fmtDuration(a.videoDuration),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (isVideo)
                                      const Positioned(
                                        left: 4,
                                        top: 4,
                                        child: Icon(
                                          Icons.videocam,
                                          color: Colors.white70,
                                          size: 16,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tile kamera (item pertama grid).
  Widget _cameraTile(double size) {
    return GestureDetector(
      onTap: _openCamera,
      child: Container(
        color: const Color(0xFF1C1C1E),
        child: const Center(
          child: Icon(Icons.photo_camera_outlined,
              color: Colors.white, size: 32),
        ),
      ),
    );
  }

  /// Mode capture dalam halaman yang sama.
  Widget _buildCamera() {
    final s = MediaQuery.of(context).size;
    final previewH = s.width * 16 / 9; // portrait 9:16
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Bar atas: kembali ke grid + flash ──
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 24),
                  onPressed: _closeCamera,
                ),
                const Spacer(),
                if (_flash == FlashMode.torch)
                  IconButton(
                    icon: const Icon(Icons.flash_on,
                        color: Colors.amber, size: 22),
                    onPressed: _toggleFlash,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.flash_off,
                        color: Colors.white54, size: 22),
                    onPressed: _toggleFlash,
                  ),
                const SizedBox(width: 4),
              ],
            ),
            // ── Preview kamera ──
            Expanded(
              child: _initializingCam
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _buildPreview(previewH),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(double previewH) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: CameraPreview(ctrl),
        ),
        // ── Kontrol bawah: flip + shutter ──
        Positioned(
          bottom: 18,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flip kamera
              GestureDetector(
                onTap: _flipCamera,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38),
                  ),
                  child: const Icon(Icons.flip_camera_ios,
                      color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 28),
              // Shutter
              GestureDetector(
                onTap: _shoot,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
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
              // Penyeimbang flip (ruang kosong simetris)
              const SizedBox(width: 44, height: 44),
            ],
          ),
        ),
      ],
    );
  }
}
