import 'package:flutter/material.dart';

/// Highlight teks hasil search chat (ala WhatsApp): bagian yang cocok
/// diberi latar kuning. Style & recognizer (link/mention) span asal
/// dipertahankan — hanya background yang ditimpa.
List<TextSpan> applySearchHighlight(List<TextSpan> spans, String query) {
  if (query.isEmpty) return spans;
  final ql = query.toLowerCase();
  final out = <TextSpan>[];
  void add(TextSpan s) {
    final t = s.text;
    if (t == null || t.isEmpty) {
      if (s.children != null) {
        for (final c in s.children!) {
          if (c is TextSpan) add(c);
        }
      } else {
        out.add(s);
      }
      return;
    }
    final tl = t.toLowerCase();
    var start = 0;
    var matched = false;
    while (true) {
      final i = tl.indexOf(ql, start);
      if (i < 0) break;
      matched = true;
      if (i > start) {
        out.add(
          TextSpan(
            text: t.substring(start, i),
            style: s.style,
            recognizer: s.recognizer,
          ),
        );
      }
      out.add(
        TextSpan(
          text: t.substring(i, i + query.length),
          style: (s.style ?? const TextStyle()).copyWith(
            backgroundColor: const Color(0xFFFFEB3B).withValues(alpha: 0.75),
          ),
          recognizer: s.recognizer,
        ),
      );
      start = i + query.length;
    }
    if (!matched) {
      out.add(s);
    } else if (start < t.length) {
      out.add(
        TextSpan(
          text: t.substring(start),
          style: s.style,
          recognizer: s.recognizer,
        ),
      );
    }
    if (s.children != null) {
      for (final c in s.children!) {
        if (c is TextSpan) add(c);
      }
    }
  }

  for (final s in spans) {
    add(s);
  }
  return out;
}
