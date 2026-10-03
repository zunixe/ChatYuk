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
    // tanpa alokasi regex; cukup sbg gerbang).
    final probablyUrl = text.contains('http') || _url != null;
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
    if (url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: LinkPreview(text: url),
    );
  }
}
