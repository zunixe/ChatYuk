import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../utils/mention.dart';

/// Bangun span teks dengan highlight mention + link URL dalam SATU pass.
///
/// - [mentions] berisi uid+nama yang benar-benar disebut → nama disorot
///   (warna primary + bold). Tanpa metadata ini `@all` di global room
///   otomatis tampil sebagai teks biasa (tidak disorot).
/// - [highlightAll] true (private room / grup) → token `@all`/`@everyone`
///   ikut disorot. Di global room selalu false.
List<TextSpan> mentionAwareSpans(
  String text,
  TextStyle base, {
  List<Mention> mentions = const [],
  bool highlightAll = false,
}) {
  if (text.isEmpty) return [TextSpan(text: text, style: base)];

  final lower = text.toLowerCase();
  final marks = <_Mark>[];

  bool isBoundaryAt(int i) {
    if (i <= 0 || i >= text.length) return true;
    final c = text[i];
    final code = c.codeUnitAt(0);
    final alnum =
        (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        c == '_';
    return !alnum;
  }

  bool free(int s, int e) {
    for (final m in marks) {
      if (s < m.end && e > m.start) return false;
    }
    return true;
  }

  // Mention bernama (terpanjang lebih dulu — "Budi Santoso" > "Budi").
  final sorted = [...mentions]
    ..sort((a, b) => b.name.length.compareTo(a.name.length));
  for (final m in sorted) {
    if (m.name.isEmpty) continue;
    final token = '@${m.name}'.toLowerCase();
    var idx = 0;
    while (idx < lower.length) {
      final found = lower.indexOf(token, idx);
      if (found < 0) break;
      final end = found + token.length;
      if (isBoundaryAt(found - 1) && isBoundaryAt(end) && free(found, end)) {
        marks.add(_Mark(found, end, _MarkKind.mention));
        break;
      }
      idx = end;
    }
  }

  // Token massal (hanya bila diizinkan konteks).
  if (highlightAll) {
    for (final t in mentionAllTokens) {
      final i = lower.indexOf(t);
      if (i < 0) continue;
      final end = i + t.length;
      if (isBoundaryAt(i - 1) && isBoundaryAt(end) && free(i, end)) {
        marks.add(_Mark(i, end, _MarkKind.mention));
      }
    }
  }

  // URL.
  for (final m in RegExp(r'https?:\/\/[^\s]+').allMatches(text)) {
    if (free(m.start, m.end)) {
      marks.add(_Mark(m.start, m.end, _MarkKind.url));
    }
  }

  if (marks.isEmpty) return [TextSpan(text: text, style: base)];
  marks.sort((a, b) => a.start.compareTo(b.start));

  final mentionStyle = base.copyWith(
    color: AppTheme.primary,
    fontWeight: FontWeight.w600,
  );
  final urlStyle = base.copyWith(
    color: AppTheme.primary,
    decoration: TextDecoration.underline,
  );

  final spans = <TextSpan>[];
  var cursor = 0;
  for (final mark in marks) {
    if (mark.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, mark.start), style: base),
      );
    }
    final seg = text.substring(mark.start, mark.end);
    if (mark.kind == _MarkKind.url) {
      final url = seg;
      spans.add(
        TextSpan(
          text: seg,
          style: urlStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
              }
            },
        ),
      );
    } else {
      spans.add(TextSpan(text: seg, style: mentionStyle));
    }
    cursor = mark.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: base));
  }
  return spans;
}

enum _MarkKind { mention, url }

class _Mark {
  final int start;
  final int end;
  final _MarkKind kind;
  const _Mark(this.start, this.end, this.kind);
}

/// Teks dengan highlight mention + link dalam satu pass.
class MentionAwareText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final List<Mention> mentions;
  final bool highlightAll;
  const MentionAwareText(
    this.text, {
    super.key,
    this.style,
    this.mentions = const [],
    this.highlightAll = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle();
    final spans = mentionAwareSpans(
      text,
      base,
      mentions: mentions,
      highlightAll: highlightAll,
    );
    if (spans.length == 1 && spans.first.recognizer == null) {
      return Text(text, style: base);
    }
    return RichText(
      text: TextSpan(children: spans, style: base),
    );
  }
}
