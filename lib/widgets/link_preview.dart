import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
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
    this.compact = false,
    this.onDismiss,
    this.fitContent = false,
    this.trailing,
  });

  /// `true` → kartu RINGKAS (ala WhatsApp saat MENGETIK): foto kecil kotak di
  /// kiri, judul + deskripsi + domain di kanan, tombol X (bila [onDismiss]
  /// ada) untuk menyembunyikan preview tanpa menghapus teks di kolom ketik.
  /// `false` (default) → kartu BESAR untuk bubble pesan terkirim (gambar
  /// penuh di atas, judul di bawah).
  final bool compact;
  final VoidCallback? onDismiss;

  /// Kartu di bubble pesan TERKIRIM: lebar mengikuti rasio ASLI foto ala
  /// WhatsApp (potret → kartu lebih sempit). `false` (default) = lebar penuh
  /// seperti bubble biasa (dipakai bila pesan juga memuat teks lain).
  final bool fitContent;

  /// Jam/centang yang dirender DI DALAM kartu (kanan bawah, ala WhatsApp).
  /// Dengan begitu kartu jadi SATU-SATUNYA penentu lebar bubble → kartu rata
  /// kanan tanpa celah aneh di sisi kanan.
  final Widget? trailing;

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
  // Rasio ASLI gambar preview (w/h) — dasar lebar kartu adaptif ala WhatsApp.
  // Diisi SINKRON dari cache disk bila ada, atau via `onAspect` LinkPreviewImage.
  double? _aspect;

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
      _aspect = cached.image.isNotEmpty
          ? LinkPreviewImage.peekAspect(cached.image)
          : null;
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
        _aspect = (d != null && d.image.isNotEmpty)
            ? LinkPreviewImage.peekAspect(d.image)
            : null;
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
            border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
          ),
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 16, color: AppTheme.textSecondary),
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
        decoration: BoxDecoration(
          color: AppTheme.bgInput,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
            SizedBox(width: 8),
            Text(lpv.linkPreviewLoading, style: AppText.chatCaption),
          ],
        ),
      );
    }
    final d = _data;
    if (d == null || d.title.isEmpty) return const SizedBox.shrink();
    if (widget.compact) return _buildCompact(d);
    // Lebar kartu ADAPTIF ala WhatsApp: tinggi gambar dibatasi ~30% tinggi
    // layar, lalu lebar mengikuti rasio ASLI gambar → foto potret jadi kartu
    // lebih sempit ("menyesuaikan konten"), bukan melebar ~80% seperti teks.
    return LayoutBuilder(
      builder: (_, c) {
        final double capH = (MediaQuery.sizeOf(context).height * 0.30).clamp(
          180.0,
          320.0,
        );
        final double cardW = widget.fitContent
            ? linkPreviewCardWidth(c.maxWidth, _aspect, capH)
            : c.maxWidth;
        // `SizedBox(width: cardW)` = pola ContactBubble: lebar bubble mengikuti
        // kartu → jam di BAWAH kartu tetap rata kanan TANPA celah di kanan.
        return SizedBox(
          width: cardW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () async {
                  final uri = Uri.tryParse(d.url);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                // Kartu ala WhatsApp: tanpa garis aksen kiri, gambar di atas,
                // deskripsi s.d. 4 baris, baris domain berikon tautan.
                child: Container(
                  width: cardW,
                  margin: EdgeInsets.only(
                    bottom: widget.trailing == null ? 6 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.bgInput,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    // min: kartu tak "mengembang" penuh bila parent memberi tight
                    // height (mis. body Scaffold / kolom composer) — tinggi ikut isi.
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (d.image.isNotEmpty)
                        // Cache DISK (LP-E): unduh sekali → MediaDiskCache → frame
                        // berikut instan. `onAspect` → lebar kartu ikut rasio gambar.
                        LinkPreviewImage(
                          url: d.image,
                          onAspect: (a) {
                            if (mounted && a != _aspect) {
                              setState(() => _aspect = a);
                            }
                          },
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
              ),
              // Jam/centang DI BAWAH kartu (rata kanan) — pola sama dengan
              // ContactBubble & FileBubble (docs/UI_CONSISTENCY.md).
              if (widget.trailing != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 3, 4, 1),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: widget.trailing,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Kartu RINGKAS ala WhatsApp (composer): foto kotak kecil di kiri, judul +
  /// deskripsi + domain di kanan, tombol X opsional. Tap → buka link.
  Widget _buildCompact(LinkPreviewData d) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(d.url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.bgInput,
          borderRadius: BorderRadius.circular(10),
        ),
        child: LayoutBuilder(
          builder: (_, c) {
            // Foto kotak ala WhatsApp: ~25% lebar kartu (hasil ukur referensi),
            // bukan ikon mungil. Dibatasi agar tetap wajar di tablet.
            final double thumb = (c.maxWidth * 0.25).clamp(64.0, 100.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: d.image.isNotEmpty
                      ? LinkPreviewIcon(
                          url: d.image,
                          size: thumb,
                          fit: BoxFit.cover,
                          radius: 8,
                        )
                      : Container(
                          width: thumb,
                          height: thumb,
                          color: AppTheme.bgCard,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.link_rounded,
                            size: 20,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
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
                        const SizedBox(height: 2),
                        Text(
                          d.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.chatCaption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
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
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.onDismiss != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            );
          },
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
