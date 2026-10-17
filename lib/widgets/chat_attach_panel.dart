import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../config/theme.dart';

/// Item menu lampiran ala WhatsApp: ikon kecil berwarna (tanpa lingkaran)
/// + label di bawah. Lebar & tinggi ditentukan grid [ChatAttachPanel].
class ChatAttachChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const ChatAttachChip({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel lampiran ala WhatsApp: menempel di bawah layar (full lebar, sudut
/// atas bulat), berisi grid ikon 4 kolom + strip foto terbaru dari galeri.
/// Geser ke ATAS → panel membesar jadi galeri; geser ke BAWAH → mengecil,
/// lalu tertutup ([onClose]).
class ChatAttachPanel extends StatefulWidget {
  final List<Widget> children;
  final VoidCallback? onClose;
  /// Foto galeri diketuk (bytes asli). null = tanpa strip galeri.
  final ValueChanged<Uint8List>? onPickGalleryPhoto;
  /// Label tombol izin galeri (string bilingual dari pemanggil).
  final String allowGalleryLabel;
  const ChatAttachPanel({
    super.key,
    required this.children,
    this.onClose,
    this.onPickGalleryPhoto,
    this.allowGalleryLabel = '',
  });

  @override
  State<ChatAttachPanel> createState() => _ChatAttachPanelState();
}

class _ChatAttachPanelState extends State<ChatAttachPanel> {
  static const double _handleH = 22;
  static const double _tileH = 74;
  static const int _cols = 4;

  bool _expanded = false;
  double? _dragH;

  void _onDragEnd(DragEndDetails d, double cur, double collapsed, double max) {
    final v = d.primaryVelocity ?? 0;
    var close = false;
    if (v < -300) {
      _expanded = true;
    } else if (v > 300) {
      if (_expanded) {
        _expanded = false;
      } else {
        close = true;
      }
    } else if (cur > (collapsed + max) / 2) {
      _expanded = true;
    } else if (cur < collapsed * 0.7) {
      close = true;
    } else {
      _expanded = false;
    }
    setState(() => _dragH = null);
    if (close) widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.viewPadding.bottom;
    final hasGallery = widget.onPickGalleryPhoto != null;
    final rows = (widget.children.length / _cols).ceil();
    final thumb = mq.size.width / _cols;
    final collapsed =
        _handleH + rows * _tileH + 8 + (hasGallery ? thumb : 0) + bottom;
    final maxH = hasGallery
        ? math.max(collapsed, mq.size.height * 0.68)
        : collapsed;
    final h = (_dragH ?? (_expanded ? maxH : collapsed)).clamp(0.0, maxH);
    final contentH = math.max(h, collapsed);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => setState(
        () => _dragH = (h - d.delta.dy).clamp(collapsed * 0.3, maxH),
      ),
      onVerticalDragEnd: (d) => _onDragEnd(d, h, collapsed, maxH),
      child: AnimatedContainer(
        duration: _dragH == null
            ? const Duration(milliseconds: 220)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        height: h,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: contentH,
          child: SizedBox(
            height: contentH,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Column(
                children: [
                  SizedBox(
                    height: _handleH,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.textSecondary.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: LayoutBuilder(
                      builder: (_, c) {
                        final w = c.maxWidth / _cols;
                        return Wrap(
                          children: [
                            for (final ch in widget.children)
                              SizedBox(width: w, height: _tileH, child: ch),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (hasGallery)
                    Expanded(
                      child: _RecentGallery(
                        scrollable: _expanded && _dragH == null,
                        onPick: widget.onPickGalleryPhoto!,
                        allowLabel: widget.allowGalleryLabel,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grid foto terbaru galeri (maks 60, bounded). Izin TIDAK diminta otomatis
/// — hanya cek status; bila belum ada akses tampil tombol izin.
class _RecentGallery extends StatefulWidget {
  final bool scrollable;
  final ValueChanged<Uint8List> onPick;
  final String allowLabel;
  const _RecentGallery({
    required this.scrollable,
    required this.onPick,
    required this.allowLabel,
  });

  @override
  State<_RecentGallery> createState() => _RecentGalleryState();
}

class _RecentGalleryState extends State<_RecentGallery> {
  static const int _limit = 60;
  List<AssetEntity> _assets = const [];
  bool _noAccess = false;
  final Map<String, Future<Uint8List?>> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _load(request: false);
  }

  Future<void> _load({required bool request}) async {
    try {
      final ps = request
          ? await PhotoManager.requestPermissionExtend()
          : await PhotoManager.getPermissionState(
              requestOption: const PermissionRequestOption(),
            );
      if (!ps.hasAccess) {
        if (mounted) setState(() => _noAccess = true);
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: FilterOptionGroup()
          ..addOrderOption(
            const OrderOption(type: OrderOptionType.updateDate, asc: false),
          ),
      );
      if (paths.isEmpty) return;
      final list = await paths.first.getAssetListPaged(page: 0, size: _limit);
      if (mounted) {
        setState(() {
          _noAccess = false;
          _assets = list;
        });
      }
    } catch (_) {
      // Plugin tak tersedia (test) / error galeri → strip kosong.
    }
  }

  Future<Uint8List?> _thumb(AssetEntity a) => _thumbs.putIfAbsent(
    a.id,
    () => a.thumbnailDataWithSize(const ThumbnailSize.square(240)),
  );

  Future<void> _pick(AssetEntity a) async {
    final bytes = await a.originBytes;
    if (bytes != null && mounted) widget.onPick(bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_noAccess) {
      return Align(
        alignment: Alignment.topCenter,
        child: TextButton.icon(
          onPressed: () => _load(request: true),
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: Text(widget.allowLabel),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: widget.scrollable
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) {
        final a = _assets[i];
        return GestureDetector(
          onTap: () => _pick(a),
          child: FutureBuilder<Uint8List?>(
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
        );
      },
    );
  }
}
