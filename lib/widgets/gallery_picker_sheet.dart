import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/photo_quality_pref.dart';

/// Hasil pemilih galeri: foto terpilih (urut pilih) + status HD, atau
/// [useSystemPicker] bila user memilih tombol folder (pemilih sistem).
class GalleryPickResult {
  final List<AssetEntity> assets;
  final bool hd;
  final bool useSystemPicker;
  const GalleryPickResult({
    this.assets = const [],
    this.hd = false,
    this.useSystemPicker = false,
  });

  /// Bytes asli foto terpilih (urut pilih). Foto yang gagal dibaca dilewati.
  Future<List<Uint8List>> readBytes() async {
    final out = <Uint8List>[];
    for (final a in assets) {
      final b = await a.originBytes;
      if (b != null && b.isNotEmpty) out.add(b);
    }
    return out;
  }
}

/// Pemilih galeri ala WhatsApp: sheet dari bawah (bisa ditarik penuh),
/// header X · album ▾ · HD, grid 4 kolom dengan nomor urut pilihan,
/// tombol kirim (jumlah) & tombol folder (pemilih sistem).
class GalleryPickerSheet extends StatefulWidget {
  final S s;
  final int maxSelect;
  const GalleryPickerSheet({super.key, required this.s, this.maxSelect = 10});

  static Future<GalleryPickResult?> show(
    BuildContext context, {
    required S s,
    int maxSelect = 10,
  }) {
    return showModalBottomSheet<GalleryPickResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GalleryPickerSheet(s: s, maxSelect: maxSelect),
    );
  }

  @override
  State<GalleryPickerSheet> createState() => _GalleryPickerSheetState();
}

class _GalleryPickerSheetState extends State<GalleryPickerSheet> {
  static const int _page = 80;

  List<AssetPathEntity> _albums = const [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  final List<AssetEntity> _picked = [];
  // Cache thumbnail bounded = hanya aset album aktif (dibuang saat ganti
  // album / sheet ditutup).
  final Map<String, Future<Uint8List?>> _thumbs = {};
  bool _hd = false;
  bool _loading = true;
  bool _noAccess = false;
  bool _hasMore = true;
  bool _loadingMore = false;
  int _nextPage = 0;

  S get s => widget.s;

  @override
  void initState() {
    super.initState();
    PhotoQualityPref.defaultHd.then((v) {
      if (mounted) setState(() => _hd = v);
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        if (mounted) {
          setState(() {
            _noAccess = true;
            _loading = false;
          });
        }
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: FilterOptionGroup()
          ..addOrderOption(
            const OrderOption(type: OrderOptionType.updateDate, asc: false),
          ),
      );
      if (!mounted) return;
      _albums = albums;
      await _selectAlbum(albums.isEmpty ? null : albums.first);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectAlbum(AssetPathEntity? a) async {
    setState(() {
      _album = a;
      _assets.clear();
      _thumbs.clear();
      _nextPage = 0;
      _hasMore = a != null;
      _loading = true;
    });
    await _loadMore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    final a = _album;
    if (a == null || !_hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final list = await a.getAssetListPaged(page: _nextPage, size: _page);
      if (!mounted || a != _album) return;
      setState(() {
        _assets.addAll(list);
        _nextPage++;
        _hasMore = list.length == _page;
      });
    } catch (_) {
      _hasMore = false;
    } finally {
      _loadingMore = false;
    }
  }

  Future<Uint8List?> _thumb(AssetEntity a) => _thumbs.putIfAbsent(
    a.id,
    () => a.thumbnailDataWithSize(const ThumbnailSize.square(240)),
  );

  void _toggle(AssetEntity a) {
    setState(() {
      final i = _picked.indexWhere((p) => p.id == a.id);
      if (i >= 0) {
        _picked.removeAt(i);
      } else if (_picked.length < widget.maxSelect) {
        _picked.add(a);
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(s.gallerySelectMax(widget.maxSelect))),
        );
      }
    });
    // Mode pilih-tunggal (foto sekali lihat): begitu 1 foto diketuk langsung
    // ditutup & dikembalikan — tanpa perlu menekan tombol kirim.
    if (widget.maxSelect == 1 && _picked.length == 1) _send();
  }

  void _send() => Navigator.of(context).pop(
    GalleryPickResult(assets: List.of(_picked), hd: _hd),
  );

  void _system() => Navigator.of(context).pop(
    GalleryPickResult(hd: _hd, useSystemPicker: true),
  );

  String _albumName(AssetPathEntity a) =>
      a.isAll ? s.galleryRecents : a.name;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 1,
      expand: false,
      snap: true,
      snapSizes: const [0.62],
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            CustomScrollView(
              controller: scroll,
              slivers: [
                SliverToBoxAdapter(child: _header()),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  )
                else if (_noAccess)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _noAccessView(),
                  )
                else
                  SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                    delegate: SliverChildBuilderDelegate((_, i) {
                      if (i >= _assets.length - 20) _loadMore();
                      return _tile(_assets[i]);
                    }, childCount: _assets.length),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: _picked.isEmpty ? _folderButton() : _sendButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppTheme.textSecondary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 6),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.close, color: AppTheme.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Center(
                  child: PopupMenuButton<AssetPathEntity>(
                    enabled: _albums.length > 1,
                    onSelected: _selectAlbum,
                    itemBuilder: (_) => [
                      for (final a in _albums)
                        PopupMenuItem(value: a, child: Text(_albumName(a))),
                    ],
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _album == null
                                ? s.galleryRecents
                                : _albumName(_album!),
                            overflow: TextOverflow.ellipsis,
                            style: AppText.title.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: AppTheme.textPrimary),
                      ],
                    ),
                  ),
                ),
              ),
              _hdButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hdButton() {
    final on = _hd;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _hd = !_hd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: on ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: on ? AppTheme.primary : AppTheme.textPrimary,
            width: 1.6,
          ),
        ),
        child: Text(
          'HD',
          style: AppText.label.copyWith(
            color: on ? Colors.white : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _tile(AssetEntity a) {
    final idx = _picked.indexWhere((p) => p.id == a.id);
    final sel = idx >= 0;
    return GestureDetector(
      onTap: () => _toggle(a),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: _thumb(a),
            builder: (_, snap) {
              final b = snap.data;
              if (b == null) return ColoredBox(color: AppTheme.bgInput);
              return Image.memory(
                b,
                fit: BoxFit.cover,
                cacheWidth: 240,
                gaplessPlayback: true,
              );
            },
          ),
          if (sel)
            ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sel ? AppTheme.primary : Colors.black26,
                border: Border.all(color: Colors.white, width: 1.6),
              ),
              child: sel
                  ? Text(
                      '${idx + 1}',
                      style: AppText.micro.copyWith(color: Colors.white),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendButton() {
    return GestureDetector(
      onTap: _send,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_picked.length}',
                style: AppText.micro.copyWith(color: AppTheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderButton() {
    return Material(
      color: AppTheme.bgInput,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _system,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(Icons.folder_open_rounded, color: AppTheme.textPrimary),
        ),
      ),
    );
  }

  Widget _noAccessView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 40, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            s.galleryNoAccess,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: PhotoManager.openSetting,
            child: Text(s.galleryOpenSettings),
          ),
        ],
      ),
    );
  }
}
