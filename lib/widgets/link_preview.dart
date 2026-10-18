import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../core/media/link_preview_service.dart';
import '../providers/riverpod/locale_provider.dart';
import 'link_preview_image.dart';

class LinkPreview extends ConsumerStatefulWidget {
  final String text;

  /// Auto-fetch preview saat bubble di-mount.
  ///
  /// `true`  → perilaku lama (fetch otomatis). Dipakai HANYA untuk bubble
  ///           dekat viewport (pesan terbaru) — lihat `autoLinkPreview` di
  ///           pemanggil (`private_chat_core`, `admin_chat_view_build`,
  ///           `room_message_chat`).
  /// `false` → JANGAN fetch saat mount. Tampilkan preview bila sudah ada di
  ///           cache (sinkron, tanpa network); kalau belum, tampilkan
  ///           placeholder "ketuk untuk memuat" (pola sama seperti foto
  ///           deferred / `isImageDeferred`). Fetch baru saat user mengetuk.
  ///
  /// Alasan: chat padat URL (khas balasan AI) memicu puluhan HTTP GET +
  /// parse HTML saat dibuka. Gating viewport memangkas itu ke nol untuk pesan
  /// yang tidak terlihat.
  final bool enabled;
  const LinkPreview({
    super.key,
    required this.text,
    this.enabled = true,
  });

  @override
  ConsumerState<LinkPreview> createState() => _LinkPreviewState();
}

class _LinkPreviewState extends ConsumerState<LinkPreview> {
  LinkPreviewData? _data;
  bool _loading = true;
  // Sudah dicek kandidat URL? Kalau bukan kandidat (gambar/aset) atau tak ada
  // URL → widget tak menampilkan apa pun (height 0).
  bool _hasUrl = false;
  // true setelah user mengetuk placeholder "ketuk untuk memuat".
  bool _userRequested = false;

  @override
  void initState() {
    super.initState();
    final url = LinkPreviewService.instance.extractUrl(widget.text);
    if (url == null) {
      _hasUrl = false;
      _loading = false;
      return;
    }
    _hasUrl = true;
    // LP-A: cache SINKRON dulu — bila sudah ada (RAM/disk sesi ini), tampil
    // LANGSUNG tanpa spinner & tanpa network, terlepas dari `enabled`.
    final cached = LinkPreviewService.instance.peek(url);
    if (cached != null) {
      _data = cached;
      _loading = false;
      return;
    }
    // Belum ada di cache: hanya fetch otomatis bila diizinkan (dekat
    // viewport). Kalau tidak → tunggu ketukan user.
    if (widget.enabled) {
      _fetch(url);
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant LinkPreview old) {
    super.didUpdateWidget(old);
    // Bubble yang sama berubah dari non-aktif → aktif (mis. masuk viewport /
    // `enabled` di-flip oleh parent) dan belum punya data → fetch sekarang.
    if (widget.enabled &&
        !old.enabled &&
        !_userRequested &&
        _hasUrl &&
        _data == null) {
      final url = LinkPreviewService.instance.extractUrl(widget.text);
      if (url != null) _fetch(url);
    }
  }

  Future<void> _fetch(String url) async {
    if (mounted) setState(() => _loading = true);
    final d = await LinkPreviewService.instance.fetch(url);
    if (mounted) {
      setState(() {
        _data = d;
        _loading = false;
      });
    }
  }

  void _onTapLoad() {
    if (_userRequested) return;
    _userRequested = true;
    final url = LinkPreviewService.instance.extractUrl(widget.text);
    if (url == null) {
      setState(() => _loading = false);
      return;
    }
    _fetch(url);
  }

  @override
  Widget build(BuildContext context) {
    final lpv = ref.watch(localeProvider).s;
    // Tidak ada URL / bukan kandidat preview → tak tampil apa pun.
    if (!_hasUrl) return const SizedBox.shrink();
    // Belum ada data & belum dimuat (menunggu ketukan) → placeholder ringan
    // "ketuk untuk memuat" (pola sama seperti foto deferred). Tak memicu
    // network sampai diketuk.
    if (!_loading && _data == null && !_userRequested) {
      return GestureDetector(
        onTap: _onTapLoad,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.bgInput,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(color: AppTheme.primary, width: 3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 16,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lpv.linkPreviewTapToLoad,
                  style: AppText.chatCaption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.bgInput, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: AppTheme.primary, width: 3))),
        child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)), SizedBox(width: 8), Text(lpv.linkPreviewLoading, style: AppText.chatCaption)]),
      );
    }
    final d = _data;
    if (d == null || d.title.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(d.url);
        if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      // Kartu ala WhatsApp (2026-10-18): tanpa garis aksen kiri, gambar
      // tinggi mengikuti lebar kartu, deskripsi s.d. 4 baris, baris domain
      // berikon tautan.
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: AppTheme.bgInput,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.image.isNotEmpty)
              // Cache DISK (LP-E): unduh sekali → simpan MediaDiskCache →
              // frame berikut instan & persist lintas sesi.
              LayoutBuilder(
                builder: (_, c) => LinkPreviewImage(
                  url: d.image,
                  height: c.maxWidth.isFinite
                      ? (c.maxWidth * 0.75).clamp(140.0, 260.0)
                      : 180,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.chatBodyStrong,
                  ),
                  if (d.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      d.description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.chatCaption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.link_rounded,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          Uri.tryParse(d.url)?.host ?? d.siteName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.chatTime.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Ikon situs (favicon) di ujung kanan, ala WhatsApp.
                      LinkPreviewIcon(url: _iconUrl(d)),
                    ],
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

/// Ikon situs untuk kartu: dari metadata, atau `/favicon.ico` domain link
/// (data lama / hasil server cadangan belum membawa ikon).
String _iconUrl(LinkPreviewData d) {
  if (d.icon.isNotEmpty) return d.icon;
  final u = Uri.tryParse(d.url);
  if (u == null || u.host.isEmpty) return '';
  return '${u.scheme.isEmpty ? 'https' : u.scheme}://${u.host}/favicon.ico';
}
