import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';
import 'story_camera_capture_screen.dart';

/// Picker foto story — GRID:
/// - Kotak PERTAMA = kamera (tap → buka layar jepret fullscreen)
/// - Kotak lainnya = foto recent HP (gambar saja, TANPA video)
/// - Tap foto → langsung ke composer story
///
/// Return [File] foto yang dipilih/dijepret, atau null kalau batal.
class StoryCameraPickerScreen extends StatefulWidget {
  const StoryCameraPickerScreen({super.key});

  @override
  State<StoryCameraPickerScreen> createState() =>
      _StoryCameraPickerScreenState();
}

class _StoryCameraPickerScreenState extends State<StoryCameraPickerScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  final List<AssetEntity> _photos = [];
  final Map<String, Uint8List?> _thumbs = {};
  final Set<String> _thumbKeys = {};
  bool _loading = true;
  bool _noPermission = false;
  // Akses SEBAGIAN (Android 14+ "Select photos"): grid hanya berisi foto
  // pilihan user — tampilkan tile "Tambah foto" untuk perluas pilihan.
  bool _limited = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 60;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadGallery();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
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
      // hasAccess (bukan isAuth): hormati "Select photos" (akses sebagian)
      // — user tetap lihat foto pilihannya di grid, bukan layar kosong.
      if (!ps.hasAccess) {
        if (mounted) {
          setState(() {
            _noPermission = true;
            _loading = false;
            _loadingMore = false;
          });
        }
        return;
      }
      final limitedNow = ps == PermissionState.limited;
      if (mounted) setState(() => _limited = limitedNow);
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadingMore = false;
            _hasMore = false;
          });
        }
        return;
      }
      final assets =
          await albums.first.getAssetListPaged(page: _page, size: _pageSize);
      if (assets.length < _pageSize) _hasMore = false;
      if (mounted) {
        setState(() {
          _photos.addAll(assets);
          _page++;
          _loading = false;
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
      debugPrint('[StoryGrid] gallery error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _openCamera() async {
    final f = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StoryCameraCaptureScreen(),
      ),
    );
    if (f != null && mounted) Navigator.pop(context, f);
  }

  Future<void> _pickPhoto(AssetEntity asset) async {
    try {
      final f = await asset.file;
      if (f != null && mounted) Navigator.pop(context, f);
    } catch (e) {
      debugPrint('[StoryGrid] pick error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          s.storyAddTooltip,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _noPermission
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined,
                        color: Colors.white38, size: 48),
                    onPressed: () {
                      setState(() {
                        _noPermission = false;
                        _loading = true;
                      });
                      PhotoManager.openSetting();
                      _loadGallery();
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _openCamera,
                    child: Text(context.read<LocaleProvider>().s.storyCamera),
                  ),
                ],
              ),
            )
          : _loading && _photos.isEmpty
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
                  itemCount: _photos.length + 1 + (_limited ? 1 : 0),
                  itemBuilder: (_, i) {
                    // Kotak PERTAMA = kamera.
                    if (i == 0) return _cameraTile();
                    final j = i - 1;
                    // Akses sebagian → kotak KEDUA = tambah foto pilihan.
                    if (_limited && j == 0) return _addMoreTile();
                    final a = _photos[_limited ? j - 1 : j];
                    final thumb = _thumbs[a.id];
                    return GestureDetector(
                      onTap: () => _pickPhoto(a),
                      child: Container(
                        color: Colors.white10,
                        child: thumb != null
                            ? Image.memory(thumb,
                                fit: BoxFit.cover, gaplessPlayback: true)
                            : const SizedBox.shrink(),
                      ),
                    );
                  },
                ),
    );
  }

  /// Kotak tambah foto — akses sebagian: buka pemilih sistem lagi untuk
  /// perluas foto yang bisa dilihat aplikasi, lalu muat ulang grid.
  Widget _addMoreTile() {
    final s = context.read<LocaleProvider>().s;
    return GestureDetector(
      onTap: () async {
        await PhotoManager.requestPermissionExtend();
        if (!mounted) return;
        setState(() {
          _photos.clear();
          _thumbKeys.clear();
          _thumbs.clear();
          _page = 0;
          _hasMore = true;
          _loadingMore = false;
        });
        _loadGallery();
      },
      child: Container(
        color: Colors.white10,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_photo_alternate_outlined,
                  color: Colors.white70, size: 30),
              const SizedBox(height: 4),
              Text(
                s.storyAddMorePhotos,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kotak kamera — tap → layar jepret fullscreen.
  Widget _cameraTile() {
    return GestureDetector(
      onTap: _openCamera,
      child: Container(
        color: Colors.white10,
        child: const Center(
          child: Icon(Icons.camera_alt_outlined,
              color: Colors.white70, size: 32),
        ),
      ),
    );
  }
}
