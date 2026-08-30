import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';

class LinkifyText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const LinkifyText(this.text, {super.key, this.style});

  static final _urlRegex = RegExp(r'https?:\/\/[^\s]+');

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    int last = 0;
    for (final m in _urlRegex.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      }
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: (style ?? const TextStyle()).copyWith(color: AppTheme.primary, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () async {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    if (spans.isEmpty) return Text(text, style: style);
    return RichText(text: TextSpan(children: spans, style: style));
  }
}
