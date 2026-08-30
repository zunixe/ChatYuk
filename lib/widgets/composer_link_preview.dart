import 'dart:async';
import 'package:flutter/material.dart';
import '../services/link_preview_service.dart';
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
    final url = LinkPreviewService.instance.extractUrl(text);
    if (url == null || url.length < 8 || !url.contains('.')) {
      if (_url != null) setState(() => _url = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
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
