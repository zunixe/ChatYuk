import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../services/link_preview_service.dart';

class LinkPreview extends StatefulWidget {
  final String text;
  const LinkPreview({super.key, required this.text});

  @override
  State<LinkPreview> createState() => _LinkPreviewState();
}

class _LinkPreviewState extends State<LinkPreview> {
  LinkPreviewData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = LinkPreviewService.instance.extractUrl(widget.text);
    if (url == null) {
      setState(() => _loading = false);
      return;
    }
    final d = await LinkPreviewService.instance.fetch(url);
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final lpv = context.watch<LocaleProvider>().s;
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.bgInput, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: AppTheme.primary, width: 3))),
        child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)), SizedBox(width: 8), Text(lpv.linkPreviewLoading, style: AppText.caption)]),
      );
    }
    final d = _data;
    if (d == null || d.title.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(d.url);
        if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: AppTheme.bgInput, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: AppTheme.primary, width: 3))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.image.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                child: Image.network(d.image, width: double.infinity, height: 140, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                  if (d.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(d.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
                  ],
                  const SizedBox(height: 4),
                  Text(d.siteName.isNotEmpty ? d.siteName : Uri.tryParse(d.url)?.host ?? d.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.micro.copyWith(color: AppTheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
