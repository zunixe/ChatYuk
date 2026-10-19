import 'dart:async';
import 'package:flutter/material.dart';
import '../core/media/link_preview_service.dart';
import 'link_preview.dart';

class ComposerLinkPreview extends StatefulWidget {
  final TextEditingController controller;
  const ComposerLinkPreview({super.key, required this.controller});

  @override
  State<ComposerLinkPreview> createState() => _ComposerLinkPreviewState();
}

class _ComposerLinkPreviewState extends State<ComposerLinkPreview> {
  String? _url;
  String? _dismissedUrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _onChanged();
  }

  @override
  void didUpdateWidget(covariant ComposerLinkPreview old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final text = widget.controller.text;
    // PERF: `extractUrl` (regex) TIDAK dijalankan tiap keystroke/hapus. Untuk
    // teks panjang, regex O(n) tiap `onChanged` = O(n²) saat ngetik/hapus
    // banyak → "ngelag beberapa huruf terakhir saat hapus". Sekarang regex
    // (dan setState) hanya jalan setelah user berhenti mengetik 400ms.
    // Cek cepat & murah: apakah ada 'http' sama sekali (indexOf O(n) tapi
    // tanpa alokasi regex; cukup sbg gerbang). Copy-paste juga sering TANPA
    // skema ("youtube.com/shorts/…") → gerbang kedua: teks tanpa spasi tapi
    // memuat titik (domain). Validasi sungguhan tetap di `extractUrl`.
    final noSpace = !text.trim().contains(' ');
    final probablyUrl =
        _url != null ||
        text.contains('http') ||
        (noSpace && text.contains('.'));
    if (!probablyUrl) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final url = LinkPreviewService.instance.extractUrl(text);
      if (url == null || url.length < 8 || !url.contains('.')) {
        if (_url != null) setState(() => _url = null);
        return;
      }
      if (url != _url) setState(() => _url = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    // User menekan X pada preview link ini → jangan tampilkan lagi (teks di
    // kolom ketik tetap utuh). Preview muncul lagi bila URL-nya berubah.
    if (url == null || url == _dismissedUrl) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      // Kartu RINGKAS ala WhatsApp saat mengetik: foto kecil di kiri + judul
      // di kanan + X utk sembunyikan.
      child: LinkPreview(
        text: url,
        compact: true,
        onDismiss: () => setState(() => _dismissedUrl = url),
      ),
    );
  }
}
