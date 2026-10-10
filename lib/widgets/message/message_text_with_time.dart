import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils.dart';
import '../../utils/mention.dart';
import '../mention_spans.dart';
import 'code_block.dart';
import 'search_highlight.dart';

// Satu blok isi bubble berpoin: teks biasa, jeda paragraf, atau satu poin
// (marker + indent + gutter) untuk hanging indent.
class _PointBlock {
  final List<TextSpan>? spans;
  final String? marker;
  final double indent;
  final double gutter;
  const _PointBlock.gap()
      : spans = null,
        marker = null,
        indent = 0,
        gutter = 0;
  const _PointBlock.text(this.spans)
      : marker = null,
        indent = 0,
        gutter = 0;
  const _PointBlock.point(
    this.marker,
    this.spans, {
    required this.indent,
    required this.gutter,
  });
  _PointBlock withExtra(List<TextSpan> extra) {
    if (spans == null) return this;
    if (marker == null) return _PointBlock.text([...spans!, ...extra]);
    return _PointBlock.point(
      marker,
      [...spans!, ...extra],
      indent: indent,
      gutter: gutter,
    );
  }
}


// Teks + waktu gaya WhatsApp: jam (+ centang) SELALU di bawah teks,
// kanan-bawah, mepet nyaris nempel tanpa jeda baris — untuk pesan 1 baris
// maupun multi-baris. Bubble hemat (tidak boros tinggi).
/// PERF (Fase 3.1): memo hasil pengukuran teks bubble multi-baris.
///
/// `MessageTextWithTime.build` menjalankan beberapa `TextPainter..layout()` +
/// `computeLineMetrics()` SINKRON untuk menentukan lebar bubble & posisi jam.
/// Ini jalan tiap bubble di-rebuild �?" dan bubble di-rebuild cukup sering
/// (setState parent: ngetik, pilih, reaction, dsb). Karena hasilnya hanya
/// bergantung pada (teks, gaya, lebar tersedia, jam, trailing), cache-kan
/// supaya rebuild berikutnya O(1).
///
/// Bounded FIFO 300 entri �?" cukup untuk viewport aktif + sedikit cache;
/// tidak tumbuh tanpa batas di percakapan panjang.
final _textMeasureMemo = <String, ({double contentW, double timeBottom})>{};
const _textMeasureMemoMax = 300;

class MessageTextWithTime extends StatelessWidget {
  final String text;
  final String timeStr;
  final TextStyle textStyle;
  final TextStyle timeStyle;
  final bool alignRight;
  final Widget? trailing;
  final List<Mention> mentions;
  final bool highlightMentionAll;
  // Kata kunci search chat — cocoknya di-highlight kuning (kosong = mati).
  final String searchQuery;
  const MessageTextWithTime({
    super.key,
    required this.text,
    required this.timeStr,
    required this.textStyle,
    required this.timeStyle,
    required this.alignRight,
    this.trailing,
    this.mentions = const [],
    this.highlightMentionAll = false,
    this.searchQuery = '',
  });

  // Poin "1." / "(a)" / "a." di awal baris → baris lanjutan menjorok
  // sejajar huruf pertama (hanging indent ala dokumen rapi).
  static final _pointRe =
      RegExp(r'^(\d{1,2}[.)]|\([a-eA-E]\)|[a-eA-E][.])\s+');
  static final _pointNumRe = RegExp(r'^\d{1,2}[.)]\s');
  static final _markerCache = <String, double>{};

  double _markerW(String marker) {
    final key = '$marker|${textStyle.fontSize ?? 14}';
    return _markerCache.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(text: '$marker ', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width + 2;
    });
  }

  bool _hasPoints(String t) {
    for (final line in t.split('\n')) {
      if (_pointRe.hasMatch(line.trimLeft())) return true;
    }
    return false;
  }

  /// Isi poin: marker, indent kiri, gutter selebar marker (teks lanjutan
  /// sejajar huruf pertama). spans null = jeda antar paragraf.
  Widget _pointBody(
    BuildContext context,
    String t,
    double available,
    double timeRowW,
    Widget timeRowWidget,
    TextPainter timeTp,
  ) {
    final dir = Directionality.of(context);
    final lines = t.split('\n');
    final hasNum =
        lines.any((l) => _pointNumRe.hasMatch(l.trimLeft()));
    final blocks = <_PointBlock>[];
    final prose = <String>[];
    void flushProse() {
      if (prose.isEmpty) return;
      final joined = prose.join('\n');
      prose.clear();
      if (joined.trim().isEmpty) {
        blocks.add(const _PointBlock.gap());
      } else {
        blocks.add(_PointBlock.text(_linkifySpans(joined, textStyle)));
      }
    }

    for (final raw in lines) {
      final line = raw.trimLeft();
      final m = _pointRe.firstMatch(line);
      if (m == null) {
        prose.add(raw);
        continue;
      }
      flushProse();
      final marker = m[1]!;
      final rest = line.substring(m[0]!.length);
      final isNum = RegExp(r'^\d').hasMatch(marker);
      blocks.add(
        _PointBlock.point(
          marker,
          _linkifySpans(rest, textStyle),
          indent: isNum ? 0.0 : (hasNum ? _markerW('00.') : 0.0),
          gutter: _markerW(marker),
        ),
      );
    }
    flushProse();

    // Reserve jam (NBSP) di blok teks terakhir — sama seperti jalur biasa.
    final reserveTp = TextPainter(
      text: TextSpan(text: ' ', style: timeStyle),
      textDirection: dir,
    )..layout();
    final reserveW = reserveTp.width > 0 ? reserveTp.width : 3.0;
    final nSpaces =
        ((timeTp.width + 8 + (trailing != null ? 16.0 : 0)) / reserveW)
                .ceil() +
            2;
    final reserve = TextSpan(
      text: String.fromCharCode(0x00A0) * nSpaces,
      style: timeStyle,
    );
    for (var i = blocks.length - 1; i >= 0; i--) {
      if (blocks[i].spans != null) {
        blocks[i] = blocks[i].withExtra([reserve]);
        break;
      }
    }

    double longest = 0;
    for (final b in blocks) {
      final spans = b.spans;
      if (spans == null) continue;
      final probe = TextPainter(
        text: TextSpan(
          style: textStyle,
          children: b.marker == null
              ? spans
              : [TextSpan(text: '${b.marker} ', style: textStyle), ...spans],
        ),
        textDirection: dir,
      )..layout(maxWidth: available);
      for (final lm in probe.computeLineMetrics()) {
        if (lm.width > longest) longest = lm.width;
      }
    }
    final contentW = math.min(available, math.max(longest, timeRowW));
    double timeDescent = 0;
    try {
      final tm = timeTp.computeLineMetrics();
      if (tm.isNotEmpty) timeDescent = tm.first.descent;
    } catch (_) {}
    double lastDescent = 0;
    for (var i = blocks.length - 1; i >= 0; i--) {
      final spans = blocks[i].spans;
      if (spans == null) continue;
      try {
        final fin = TextPainter(
          text: TextSpan(style: textStyle, children: spans),
          textDirection: dir,
        )..layout(maxWidth: contentW);
        final ls = fin.computeLineMetrics();
        if (ls.isNotEmpty) lastDescent = ls.last.descent;
      } catch (_) {}
      break;
    }
    final timeBottom = math.max(0.0, lastDescent - timeDescent - 2);
    return SizedBox(
      width: contentW > 0 ? contentW : null,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in blocks)
                if (b.spans == null)
                  const SizedBox(height: 6)
                else if (b.marker == null)
                  RichText(
                    text: TextSpan(style: textStyle, children: b.spans),
                  )
                else
                  Padding(
                    padding: EdgeInsets.only(left: b.indent),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: b.gutter,
                          child: Text(b.marker!, style: textStyle),
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: textStyle,
                              children: b.spans,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
          Positioned(
            right: 0,
            bottom: timeBottom,
            child: timeRowWidget,
          ),
        ],
      ),
    );
  }

  List<TextSpan> _linkifySpans(String t, TextStyle base) {
    final spans = mentionAwareSpans(
      t,
      base,
      mentions: mentions,
      highlightAll: highlightMentionAll,
    );
    if (searchQuery.isEmpty) return spans;
    return applySearchHighlight(spans, searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    // Spasi/newline di ujung tidak terlihat tapi menggeser jam — rapikan
    // dulu (ala WhatsApp) supaya jam selalu mepet akhir teks terlihat.
    // formatChatLists: poin "1. 2." / "(a) (b)" sebaris dipecah jadi
    // paragraf + tab — berlaku untuk pesan LAMA juga (server hanya
    // merapikan balasan baru). Idempoten, blok kode dilewati.
    final ft = formatChatLists(text);
    final t = ft.trimRight().isEmpty ? ft : ft.trimRight();
    // Pesan berisi pagar kode ``` → render segmen teks + CodeBlock, waktu
    // di baris bawah seperti bubble multi-baris.
    if (t.contains('```')) {
      final segs = splitCodeSegments(t);
      if (segs.any((e) => e.isCode)) {
        return Column(
          crossAxisAlignment: alignRight
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final seg in segs)
              if (seg.isCode)
                CodeBlock(code: seg.content, language: seg.lang)
              else if (seg.content.trim().isNotEmpty)
                RichText(
                  text: TextSpan(
                    style: textStyle,
                    children: _linkifySpans(seg.content, textStyle),
                  ),
                ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(timeStr, style: timeStyle),
                if (trailing != null) ...[
                  const SizedBox(width: 3),
                  trailing!,
                ],
              ],
            ),
          ],
        );
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width * 0.8;
        // Ukur 1 baris: muat sebaris dengan jam?
        final tp = TextPainter(
          text: TextSpan(text: t, style: textStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final timeTp = TextPainter(
          text: TextSpan(text: timeStr, style: timeStyle),
          textDirection: Directionality.of(context),
        )..layout();
        // Jangan lebih sempit dari baris timestamp (+ centang) sendiri.
        final timeRowW = timeTp.width + 8 + (trailing != null ? 16.0 : 0);
        final timeRowWidget = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(timeStr, style: timeStyle),
            if (trailing != null) ...[
              const SizedBox(width: 3),
              trailing!,
            ],
          ],
        );
        final singleLine =
            !t.contains('\n') && tp.width + timeRowW + 2 <= available;
        if (singleLine) {
          // 1 baris muat: [teks][spasi 6px][jam], jam turun 3px biar
          // agak di bawah teks (tidak sejajar) — sama untuk pengirim
          // maupun penerima, hemat seperti WA. Tanpa Flexible supaya
          // teks pendek tidak Terperas rusak.
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RichText(
                text: TextSpan(
                  style: textStyle,
                  children: _linkifySpans(t, textStyle),
                ),
              ),
              const SizedBox(width: 6),
              Transform.translate(
                offset: const Offset(0, 3),
                child: timeRowWidget,
              ),
            ],
          );
        }
        // Poin berpoin ("1."/"(a)") → baris lanjutan menjorok sejajar
        // huruf pertama (hanging indent). Pesan tanpa poin pakai jalur
        // biasa di bawah (tidak tersentuh).
        if (_hasPoints(t)) {
          return _pointBody(
            context,
            t,
            available,
            timeRowW,
            timeRowWidget,
            timeTp,
          );
        }
        // Multi-baris: jam overlay sudut kanan-bawah. Reserve selebar baris
        // jam tapi setinggi font jam: muat → nempel di baris terakhir sejajar
        // baseline; tidak muat → jadi baris pendek sendiri setinggi jam
        // (bukan setinggi teks) — hemat seperti WA.
        double timeDescent = 0;
        try {
          final tm = timeTp.computeLineMetrics();
          if (tm.isNotEmpty) timeDescent = tm.first.descent;
        } catch (_) {}
        final linkSpans = _linkifySpans(t, textStyle);
        final reserveTp = TextPainter(
          text: TextSpan(text: ' ', style: timeStyle),
          textDirection: Directionality.of(context),
        )..layout();
        final reserveW = reserveTp.width > 0 ? reserveTp.width : 3.0;
        final nSpaces =
            ((timeTp.width + 8 + (trailing != null ? 16.0 : 0)) / reserveW)
                    .ceil() +
                2;
        final children = <TextSpan>[
          ...linkSpans,
          TextSpan(
            text: String.fromCharCode(0x00A0) * nSpaces,
            style: timeStyle,
          ),
        ];
        TextPainter probeTp() => TextPainter(
              text: TextSpan(style: textStyle, children: children),
              textDirection: Directionality.of(context),
            );
        // Probe termasuk reserve: lebar bubble ngepas ke isi (bukan selebar
        // 80% layar) sekaligus cukup untuk reserve sebaris bila muat.
        //
        // PERF (Fase 3.1): hasil (contentW, timeBottom) di-memo �?" rebuild
        // bubble yang sama (teks/gaya/lebar/jam/trailing tidak berubah) tidak
        // lagi mengukur ulang. Ini memangkas kerja sinkron di frame.
        final memoKey = '$available|$timeRowW|$t\u0000$timeStr'
            '\u0000${textStyle.hashCode}|${trailing != null}';
        final memo = _textMeasureMemo[memoKey];
        if (memo != null) {
          // sentuh ulang agar tidak ter-FIFO evict (semacam LRU).
          _textMeasureMemo.remove(memoKey);
          _textMeasureMemo[memoKey] = memo;
        }
        final double contentW;
        final double timeBottom;
        if (memo != null) {
          contentW = memo.contentW;
          timeBottom = memo.timeBottom;
        } else {
          final probe = probeTp()..layout(maxWidth: available);
          double longest = 0;
          for (final lm in probe.computeLineMetrics()) {
            if (lm.width > longest) longest = lm.width;
          }
          final cw = math.min(available, math.max(longest, timeRowW));
          // Metrik baris terakhir layout final → jam 2px di bawah baseline
          // teks (tidak sejajar) — sama untuk pengirim maupun penerima.
          final fin = probeTp()..layout(maxWidth: cw);
          final lastLine = fin.computeLineMetrics().last;
          final tb = math.max(0.0, lastLine.descent - timeDescent - 2);
          contentW = cw;
          timeBottom = tb;
          if (!_textMeasureMemo.containsKey(memoKey) &&
              _textMeasureMemo.length >= _textMeasureMemoMax) {
            _textMeasureMemo.remove(_textMeasureMemo.keys.first);
          }
          _textMeasureMemo[memoKey] = (contentW: cw, timeBottom: tb);
        }
        return SizedBox(
          width: contentW > 0 ? contentW : null,
          child: Stack(
            children: [
              RichText(
                text: TextSpan(style: textStyle, children: children),
              ),
              Positioned(
                right: 0,
                bottom: timeBottom,
                child: timeRowWidget,
              ),
            ],
          ),
        );
      },
    );
  }
}
