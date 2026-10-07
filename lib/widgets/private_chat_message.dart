import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils.dart';
import '../utils/mention.dart';
import 'mention_spans.dart';
import 'chat_video_bubble.dart';
import 'media_caption_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../config/gifts.dart';
import '../models/message_model.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../core/cache/photo_cache.dart';
import '../core/chat/chat_location.dart';
import '../core/media/native_image.dart';import '../widgets/location_bubble.dart';
import '../core/screen_secure_service.dart';
import '../services/storage_photo_service.dart';
import 'app_gesture.dart';
import 'reply_quote.dart';
import 'voice_bubble.dart';
import 'link_preview.dart';
import '../core/media/link_preview_service.dart';
import '../core/media/image_cache_hygiene.dart';
import '../core/media/chat_photo_helper.dart';
import '../config/theme.dart';

// cacheKey untuk PhotoCache = cacheKey yang dipakai chat_service
// ('private_$chatId' untuk private chat). Dipakai private chat & admin monitor.
String cacheKeyFor(String chatId) => 'private_$chatId';

/// Ikon jenis pesan untuk penanda "dihapus" di monitor admin — supaya admin
/// tahu pesan apa yang dihapus (teks/gambar/video/suara/lokasi/panggilan).
/// Murni & testable.
IconData adminDeletedTypeIcon(String type) {
  switch (type) {
    case 'image':
    case 'view_once':
    case 'view_once_expired':
      return Icons.image_outlined;
    case 'video':
    case 'video_once':
    case 'video_once_expired':
      return Icons.videocam_outlined;
    case 'voice':
      return Icons.mic_outlined;
    case 'location':
      return Icons.location_on_outlined;
    case 'call':
      return Icons.call_outlined;
    default:
      return Icons.chat_bubble_outline;
  }
}

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

// Hasil decode: bytes + dimensi asli agar tampilan proporsional.
class DecodedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const DecodedImage(this.bytes, this.width, this.height);
}

// Cache decode agar scroll-back tidak resize (glitch). Key = hash imageData,
// bounded 40 (LRU) cegah OOM. 40 (dulu 80) supaya RAM di HP 4-6GB lebih lega
// (tiap entri foto menyimpan bytes asli; video poster terpisah di disk cache).
final decodedImageCache = <int, DecodedImage>{};
// PERF: 40 → 16. Tiap entri = bytes foto asli (bisa ~2-3MB). 40 entri bisa
// menahan ~80-120MB → GC storm seiring pemakaian. 16 cukup untuk bubble yang
// tampil sekaligus saat scroll; foto lain dibaca ulang dari cache disk/chat.
const _decodedCacheMax = 12;
// Daftarkan pembersih ke hygiene logout (satu titik, lihat
// core/media/image_cache_hygiene.dart) — bytes foto user lama tidak boleh
// tinggal di RAM setelah ganti akun. Lazy: dipanggil saat cache pertama diisi.
bool _hygieneRegistered = false;
void _putDecodedCache(int key, DecodedImage img) {
  if (!_hygieneRegistered) {
    _hygieneRegistered = true;
    ImageCacheHygiene.registerAppCache(decodedImageCache.clear);
  }
  if (decodedImageCache.length >= _decodedCacheMax) {
    decodedImageCache.remove(decodedImageCache.keys.first);
  }
  decodedImageCache[key] = img;
}

// Daftarkan hasil decode milik [base64] agar path storage yang isinya SAMA
// langsung hit cache — pengirim tidak perlu download ulang fotonya sendiri
// saat versi server tiba via stream (anti kedip kotak → foto). Dipanggil
// setelah upload berhasil, sebelum pesan server masuk. Murni (map) & testable.
void warmPhotoCacheForPath(String path, String base64) {
  if (path.isEmpty || base64.isEmpty) return;
  final cached = decodedImageCache[base64.hashCode];
  if (cached != null) _putDecodedCache(path.hashCode, cached);
}

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

// Segmen hasil belah teks: teks biasa atau blok kode (pagar ```).
class _MsgSegment {
  final bool isCode;
  final String lang;
  final String content;
  const _MsgSegment(this.isCode, this.lang, this.content);
}

// Belah teks per pagar ``` — pagar tak tertutup tetap dianggap kode.
List<_MsgSegment> _splitCodeSegments(String t) {
  final parts = t.split('```');
  if (parts.length < 2) return [ _MsgSegment(false, '', t) ];
  final segs = <_MsgSegment>[];
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    if (i.isEven) {
      if (p.isNotEmpty) segs.add(_MsgSegment(false, '', p));
    } else {
      var lang = '';
      var code = p;
      final nl = p.indexOf('\n');
      if (nl >= 0) {
        final first = p.substring(0, nl).trim();
        if (first.isNotEmpty &&
            !first.contains(' ') &&
            first.length <= 12) {
          lang = first;
          code = p.substring(nl + 1);
        }
      } else if (!p.contains(' ') && p.length <= 12) {
        lang = p.trim();
        code = '';
      }
      segs.add(_MsgSegment(true, lang, code.trimRight()));
    }
  }
  return segs;
}

// Highlight ringan tanpa dependency: comment warna beda (abu-hijau
// italic), keyword biru, string oranye, angka hijau muda. Tokenizer
// sadar-string supaya '#' di dalam string Python tidak dianggap comment.
const _codeBase = Color(0xFFE8E8E8);
const _codeComment = Color(0xFF8A9A8B);
const _codeKeyword = Color(0xFF7EC8FF);
const _codeString = Color(0xFFFFC57E);
const _codeNumber = Color(0xFFB5CEA8);

// Keyword umum (python + c-like) — cukup untuk highlight, bukan parser.
const _codeKeywords = {
  'def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'break',
  'continue', 'pass', 'raise', 'try', 'except', 'finally', 'with', 'as',
  'import', 'from', 'lambda', 'and', 'or', 'not', 'in', 'is', 'None',
  'True', 'False', 'self', 'async', 'await', 'yield', 'assert', 'del',
  'global', 'nonlocal', 'function', 'var', 'let', 'const', 'new', 'switch',
  'case', 'default', 'do', 'struct', 'enum', 'typedef', 'namespace',
  'using', 'public', 'private', 'protected', 'static', 'final', 'void',
  'int', 'float', 'double', 'char', 'bool', 'long', 'short', 'virtual',
  'override', 'extends', 'implements', 'interface', 'package', 'throws',
  'print',
};

bool _isWordChar(String ch) =>
    RegExp(r'[A-Za-z0-9_]').hasMatch(ch);

List<TextSpan> _highlightCodeSpans(String code, String lang) {
  final l = lang.toLowerCase();
  final hashComment =
      l.isEmpty || l == 'python' || l == 'py' || l == 'rb' || l == 'sh' ||
      l == 'bash' || l == 'yaml' || l == 'yml' || l == 'toml';
  final dashComment = l == 'sql';
  final spans = <TextSpan>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isEmpty) return;
    spans.add(TextSpan(text: buf.toString()));
    buf.clear();
  }

  var i = 0;
  final n = code.length;
  while (i < n) {
    final ch = code[i];
    final two = i + 1 < n ? code.substring(i, i + 2) : '';
    // Comment blok /* */ (c-like).
    if (!hashComment && !dashComment && two == '/*') {
      final end = code.indexOf('*/', i + 2);
      final stop = end < 0 ? n : end + 2;
      flush();
      spans.add(
        TextSpan(
          text: code.substring(i, stop),
          style: const TextStyle(color: _codeComment, fontStyle: FontStyle.italic),
        ),
      );
      i = stop;
      continue;
    }
    // Comment satu baris: // (c-like), # (python dkk), -- (sql).
    final isLineComment =
        (!hashComment && !dashComment && two == '//') ||
        (hashComment && ch == '#') ||
        (dashComment && two == '--');
    if (isLineComment) {
      var end = code.indexOf('\n', i);
      if (end < 0) end = n;
      flush();
      spans.add(
        TextSpan(
          text: code.substring(i, end),
          style: const TextStyle(color: _codeComment, fontStyle: FontStyle.italic),
        ),
      );
      i = end;
      continue;
    }
    // Comment html <!-- -->.
    if ((l == 'html' || l == 'xml') && code.startsWith('<!--', i)) {
      final end = code.indexOf('-->', i + 4);
      final stop = end < 0 ? n : end + 3;
      flush();
      spans.add(
        TextSpan(
          text: code.substring(i, stop),
          style: const TextStyle(color: _codeComment, fontStyle: FontStyle.italic),
        ),
      );
      i = stop;
      continue;
    }
    // String '...' "..." `...` + triple-quote python.
    if (ch == "'" || ch == '"' || ch == '`') {
      final triple =
          (ch == "'" || ch == '"') && code.startsWith(ch * 3, i);
      final quote = triple ? ch * 3 : ch;
      var j = i + quote.length;
      var closed = false;
      while (j < n) {
        if (!triple && code[j] == '\n') break;
        if (code[j] == '\\' && j + 1 < n) {
          j += 2;
          continue;
        }
        if (code.startsWith(quote, j)) {
          j += quote.length;
          closed = true;
          break;
        }
        j++;
      }
      flush();
      spans.add(
        TextSpan(
          text: code.substring(i, closed ? j : j),
          style: const TextStyle(color: _codeString),
        ),
      );
      i = j;
      continue;
    }
    // Angka.
    if (RegExp(r'[0-9]').hasMatch(ch) &&
        (i == 0 || !_isWordChar(code[i - 1]))) {
      var j = i;
      while (j < n && RegExp(r'[0-9a-fA-FxXoObB._]').hasMatch(code[j])) {
        j++;
      }
      flush();
      spans.add(
        TextSpan(
          text: code.substring(i, j),
          style: const TextStyle(color: _codeNumber),
        ),
      );
      i = j;
      continue;
    }
    // Kata: keyword atau teks biasa.
    if (RegExp(r'[A-Za-z_]').hasMatch(ch)) {
      var j = i;
      while (j < n && _isWordChar(code[j])) {
        j++;
      }
      final word = code.substring(i, j);
      flush();
      if (_codeKeywords.contains(word)) {
        spans.add(
          TextSpan(
            text: word,
            style: const TextStyle(color: _codeKeyword),
          ),
        );
      } else {
        spans.add(TextSpan(text: word));
      }
      i = j;
      continue;
    }
    buf.write(ch);
    i++;
  }
  flush();
  return spans;
}

// Blok kode di bubble chat: header (label bahasa + tombol copy kanan
// atas) + isi monospace highlight yang bisa diseleksi. Isi scroll
// horizontal (geser kanan) supaya baris panjang tidak wrap memenuhi
// bubble ke bawah — indentasi kode tetap rapi seperti aslinya.
class CodeBlock extends StatelessWidget {
  final String code;
  final String language;
  const CodeBlock({super.key, required this.code, required this.language});

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final normalized = code.replaceAll('\t', '  ');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2430),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, top: 6),
                  child: Text(
                    language.isEmpty ? 'code' : language,
                    style: AppText.chatCaption.copyWith(
                      color: const Color(0x99FFFFFF),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                height: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.copy,
                    size: 16,
                    color: Color(0xB3FFFFFF),
                  ),
                  tooltip: s.codeCopy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(content: Text(s.codeCopied)),
                      );
                  },
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: Color(0x1FFFFFFF)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText.rich(
                TextSpan(
                  style: AppText.chatCode.copyWith(color: _codeBase),
                  children: _highlightCodeSpans(normalized, language),
                ),
              ),
            ),
          ),
        ],
      ),
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
      final segs = _splitCodeSegments(t);
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

class MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final String chatKey;
  final bool isMe;
  final bool isRead;
  final bool isPending;
  final bool isQueued;
  // Image kosong karena di luar window auto-load (pesan lama) → tampilkan
  // icon refresh; klik memanggil onRetryImage(messageId).
  final bool isImageDeferred;
  final Future<void> Function(String messageId)? onRetryImage;
  // Admin monitor: view-once yang sudah expired tetap bisa dilihat admin.
  final bool isAdminView;
  // Room chat pakai tabel 'messages' untuk clear view-once.
  final bool isRoom;
  // Long-press untuk buka menu (Balas / Edit / Hapus) seperti WhatsApp.
  // LayerLink dipakai agar action bar (icon) bisa di-anchor tepat di atas
  // bubble dan ikut mengikuti posisi bubble saat list di-scroll.
  final void Function(LongPressStartDetails, MessageModel, LayerLink)?
  onLongPressMenu;
  // Link anchor milik bubble ini (dibuat & dikelola oleh screen agar stabil
  // antar rebuild ListView — lihat _msgLinks di private_chat_screen).
  final LayerLink link;
  /// PRIVASI: id pesan (chat/room) yang terhapus — quote reply yang
  /// menunjuk salah satunya dirender "Pesan dihapus", bukan isinya.
  final Set<String> deletedIds;
  /// Geser bubble ke KANAN → langsung balas pesan ini (ala WhatsApp).
  /// Kosong = fitur swipe dimatikan (mis. monitor admin read-only).
  final VoidCallback? onSwipeReply;
  final bool selected;
  final Map<String, int>? reactions;
  final bool starred;
  final VoidCallback? onTapSelect;
  final VoidCallback? onTapBadge;
  /// Highlight `@all` — hanya private room/grup. Global room & private 1:1
  /// selalu false (token `@all` tampil sebagai teks biasa).
  final bool highlightMentionAll;
  // Kata kunci search chat — diteruskan ke teks bubble (kosong = mati).
  final String searchQuery;
  /// Admin monitor: tampilkan centang di KEDUA sisi (kiri & kanan), bukan
  /// hanya milik pengirim. Tujuannya admin melihat status baca kedua orang.
  final bool showChecksBothSides;
  const MessageBubble({
    super.key,
    required this.msg,
    required this.chatKey,
    required this.isMe,
    required this.isRead,
    this.isPending = false,
    this.isQueued = false,
    this.isImageDeferred = false,
    this.onRetryImage,
    this.isAdminView = false,
    this.showChecksBothSides = false,
    this.isRoom = false,
    this.onLongPressMenu,
    this.onSwipeReply,
    required this.link,
    this.deletedIds = const {},
    this.selected = false,
    this.reactions,
    this.starred = false,
    this.onTapSelect,
    this.onTapBadge,
    this.highlightMentionAll = false,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final timeStr = formatBubbleTime(msg.timestamp);
    // Pesan yang dihapus (soft delete).
    // - Chat biasa: cukup teks redup "Pesan ini telah dihapus".
    // - Monitor admin: TETAP tampilkan ISI ASLI (teks/foto/video) + banner
    //   "Dihapus oleh pengirim" — supaya admin bisa memverifikasi laporan
    //   tanpa kehilangan bukti. RPC admin memang mengirim konten asli.
    if (msg.isDeleted && !isAdminView) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Text(
              s.messageDeleted,
              style: AppText.chatBodySmall.copyWith(
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    return CompositedTransformTarget(
      link: link,
      // AppGestureDetector: tahan 320ms (bukan 500ms) → toolbar seleksi/
      // reaksi muncul lebih cepat; tap tetap instan.
      child: AppGestureDetector(
        onLongPressStart: (d) => onLongPressMenu?.call(d, msg, link),
        onTap: onTapSelect,
        behavior: HitTestBehavior.opaque,
        child: SwipeToReply(
          enabled: onSwipeReply != null && onTapSelect == null,
          onReply: onSwipeReply,
          child: Padding(
          padding: EdgeInsets.only(bottom: reactions != null && reactions!.isNotEmpty ? 12 : 8),
          child: Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    // Bubble solid (tidak transparan) — tint primary di-blend ke bgCard.
                    // Bubble lawan (other) pakai bgCard (putih di light mode) + shadow
                    // halus supaya tetap kontras di atas wallpaper chat apa pun.
                    // Terpilih: tint primary 0.20 di atas warna dasar — senada
                    // kartu terpilih di list Pesan + toolbar seleksi.
                    color: Color.alphaBlend(
                      AppTheme.primary.withValues(
                        alpha: selected ? 0.20 : 0.0,
                      ),
                      msg.type == 'coin'
                          ? Color(0xFFFFF3C4)
                          : (isMe
                                ? Color.alphaBlend(
                                    AppTheme.primary.withValues(alpha: 0.25),
                                    AppTheme.bgCard,
                                  )
                                : AppTheme.bgCard),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 6,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                    border: selected
                        ? Border.all(color: AppTheme.primary, width: 2)
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(10),
                      topRight: const Radius.circular(10),
                      bottomLeft: Radius.circular(isMe ? 10 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 10),
                    ),
                  ),
                  child: Column(
                    // Konten (teks + jam) center vertikal dalam bubble saat
                    // bubble lebih tinggi dari konten (mis. caption pendek di
                    // bawah foto). Horizontal tetap kiri/kanan seperti semula.
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (msg.isForwarded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.forward,
                                size: 14,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                s.msgForwardedLabel,
                                style: AppText.caption.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (starred)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Icon(
                            Icons.star,
                            size: 14,
                            color: const Color(0xFFFFB300),
                          ),
                        ),
                      if (msg.repliedToText != null &&
                          msg.repliedToText!.isNotEmpty)
                        ReplyQuote.fromMessage(
                          context: context,
                          repliedToText: msg.repliedToText,
                          repliedToId: msg.repliedToId,
                          repliedToSenderName: msg.repliedToSenderName,
                          isMe: isMe,
                          deletedIds: deletedIds,
                        )!,
                      // Monitor admin: pesan yang dihapus pengirim tetap
                      // menampilkan ISI ASLI, ditandai banner jelas supaya
                      // admin tahu itu sudah dihapus.
                      if (msg.isDeleted && isAdminView)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.danger.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 12,
                                  color: AppTheme.danger,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  s.adminDeletedMarker,
                                  style: AppText.micro.copyWith(
                                    color: AppTheme.danger,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (msg.type == 'voice' && msg.imageData.isNotEmpty)
                        VoiceBubble(
                          path: msg.imageData,
                          durationMs: msg.durationMs ?? 0,
                          isMe: isMe,
                          timeStr: timeStr,
                          isPending: isPending,
                          isQueued: isQueued,
                          isRead: isRead,
                        )
                      else if (msg.type == 'video_once_expired' &&
                          !isMe &&
                          !isAdminView)
                        // Video kadaluarsa sisi PENERIMA: kartu terkunci
                        // "Video sudah kadaluarsa". Jam OVERLAY di DALAM card
                        // (kanan 6 bawah 6) — SAMA seperti foto kadaluarsa
                        // (ViewOnce), bukan di bawah. Tidak ada badge durasi
                        // di card terkunci jadi tidak bertumpuk.
                        SizedBox(
                          width: ChatVideoBubble.bubbleWidth,
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ChatVideoBubble(
                              videoData: msg.imageData,
                              durationMs: msg.durationMs ?? 0,
                              // Terkunci untuk PENERIMA. Pengirim tetap boleh
                              // melihat videonya sendiri (pola sama foto).
                              // Admin monitor: tidak pernah terkunci.
                              locked: !isMe,
                              isOnce: true,
                              messageId: msg.id,
                              isMe: isMe,
                              isAdminView: isAdminView,
                              timeStr: timeStr,
                              showChecks: isMe || showChecksBothSides,
                              isPending: isPending,
                              isQueued: isQueued,
                              isRead: isRead,
                            ),
                            if (msg.text.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 4, 8, 0),
                                child: MentionAwareText(
                                  msg.text,
                                  style: AppText.chatBody.copyWith(
                                    color: AppTheme.textPrimary,
                                  ),
                                  mentions: msg.mentions,
                                ),
                              ),
                          ],
                          ),
                        )
                      else if (((msg.type == 'video' ||
                                  msg.type == 'video_once') &&
                              msg.imageData.isNotEmpty) ||
                          // Kadaluarsa sisi PENGIRIM/admin: videonya masih
                          // bisa diputar (data tidak dihapus) → jam di BAWAH
                          // seperti video biasa, bukan overlay.
                          msg.type == 'video_once_expired')
                        // Jam di BAWAH video dalam bubble (kanan) — TIDAK
                        // overlay supaya tidak bertumpuk dengan badge durasi
                        // di dalam video. Sama untuk pengirim & penerima.
                        // Lebar dikunci selebar video (ala LocationBubble).
                        SizedBox(
                          width: ChatVideoBubble.bubbleWidth,
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ChatVideoBubble(
                              videoData: msg.imageData,
                              durationMs: msg.durationMs ?? 0,
                              // Sekali lihat: sudah ditonton → terkunci.
                              locked: false,
                              isOnce: msg.type == 'video_once' ||
                                  msg.type == 'video_once_expired',
                              messageId: msg.id,
                              isMe: isMe,
                              isAdminView: isAdminView,
                            ),
                            // Caption + jam SEBARIS ala chat teks (nempel, hemat
                            // tinggi): caption pendek → jam nempel di ujung
                            // baris; caption panjang → jam di akhir baris
                            // terakhir. Tanpa caption → jam di bawah (rapat).
                            if (msg.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 4,
                                ),
                                child: MediaCaptionTime(
                                  text: msg.text,
                                  timeStr: timeStr,
                                  textStyle: AppText.chatBody.copyWith(
                                    color: AppTheme.textPrimary,
                                  ),
                                  timeStyle: AppText.chatTime.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  showChecks: isMe || showChecksBothSides,
                                  isPending: isPending,
                                  isQueued: isQueued,
                                  isRead: isRead,
                                  leftInset: 8,
                                ),
                              )
                            else
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 2, 0, 0),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        timeStr,
                                        style: AppText.chatTime.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      if (isMe || showChecksBothSides) ...[
                                        const SizedBox(width: 3),
                                        Icon(
                                          (isPending || isQueued)
                                              ? Icons.done
                                              : Icons.done_all,
                                          size: 12,
                                          color: (!isQueued &&
                                                  !isPending &&
                                                  isRead)
                                              ? AppTheme.primary
                                              : AppTheme.textSecondary,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                          ),
                        )
                      else if (msg.type == 'image' && msg.imageData.isNotEmpty)
                        _PhotoBubble(
                          msg: msg,
                          chatKey: chatKey,
                          timeStr: timeStr,
                          isMe: isMe,
                          isRead: isRead,
                          isPending: isPending,
                          isQueued: isQueued,
                          showChecksBothSides: showChecksBothSides,
                          highlightMentionAll: highlightMentionAll,
                        )
                      else if (msg.type == 'image' &&
                          msg.imageData.isEmpty &&
                          isImageDeferred)
                        DeferredImage(
                          onTap: () async => onRetryImage?.call(msg.id),
                        )
                      else if (msg.type == 'location' &&
                          parseLocation(msg.text) != null)
                        LocationBubble(
                          location: parseLocation(msg.text)!,
                          timeStr: timeStr,
                          showChecks: isMe || showChecksBothSides,
                          isPending: isPending,
                          isQueued: isQueued,
                          isRead: isRead,
                        )
                      else if (msg.type == 'view_once' ||
                          msg.type == 'view_once_expired')
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                ViewOnceImage(
                                  imageData: msg.imageData,
                                  chatKey: chatKey,
                                  isMe: isMe,
                                  messageId: msg.id,
                                  viewSecs: msg.durationMs,
                                  isExpired: msg.type == 'view_once_expired',
                                  isAdminView: isAdminView,
                                  isRoom: isRoom,
                                ),
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          timeStr,
                                          style: AppText.chatTime.copyWith(
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (isMe || showChecksBothSides) ...[
                                          const SizedBox(width: 3),
                                          Tooltip(
                                            message: isQueued
                                                ? s.msgWaitingConnection
                                                : '',
                                            child: Icon(
                                              (isPending || isQueued)
                                                  ? Icons.done
                                                  : Icons.done_all,
                                              size: 12,
                                              color: (isRead &&
                                                      !isPending &&
                                                      !isQueued)
                                                  ? const Color(0xFF7EC8FF)
                                                  : Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Caption foto sekali-lihat (dulu tersimpan di DB
                            // tapi TIDAK dirender → teks seolah hilang).
                            if (msg.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: MentionAwareText(
                                  msg.text,
                                  style: AppText.chatBody.copyWith(
                                    color: AppTheme.textPrimary,
                                  ),
                                  mentions: msg.mentions,
                                ),
                              ),
                          ],
                        )
                      else if (msg.type == 'coin')
                        Builder(
                          builder: (context) {
                            final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
                            final amount = int.tryParse(msg.text) ?? 0;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '🪙',
                                  style: TextStyle(fontSize: AppGlyph.sm),
                                ),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isMe
                                        ? s.coinBubbleSent(amount)
                                        : s.coinBubbleReceived(amount),
                                    style: AppText.chatBody.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB8860B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: AppText.chatTime.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else if (msg.type == 'gift')
                        Builder(
                          builder: (context) {
                            final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
                            final g = giftById(msg.text);
                            final emoji = g?.emoji ?? '🎁';
                            final name = g == null
                                ? ''
                                : (s.isId ? g.nameId : g.nameEn);
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  emoji,
                                  style: TextStyle(fontSize: AppGlyph.md),
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    isMe
                                        ? s.giftBubbleSent(name)
                                        : s.giftBubbleReceived(name),
                                    style: AppText.chatBody.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB8860B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: AppText.chatTime.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else if (msg.type == 'call')
                        Builder(
                          builder: (context) {
                            final isVideoCall = msg.text.contains('📹');
                            // Hapus emoji awal (📹/📞) dari teks karena ikon sudah
                            // ditampilkan terpisah — hindari ikon ganda. Pakai
                            // replace literal (bukan regex) supaya surrogate emoji
                            // tidak rusak jadi karakter '?'.
                            final displayText = msg.text
                                .replaceFirst('📹', '')
                                .replaceFirst('📞', '')
                                .trimLeft();
                            // Warna ikon mengikuti hasil panggilan (teks status
                            // disimpan berbahasa Inggris — stabil antar locale):
                            // hijau = panggilan terhubung, merah = gagal/tak dijawab.
                            const successMarkers = ['Call ended'];
                            const failMarkers = [
                              'Missed call',
                              'Call declined',
                              'Call canceled',
                              'Busy',
                              'Call failed',
                            ];
                            final callIconColor =
                                successMarkers.any(displayText.contains)
                                ? Colors.greenAccent
                                : failMarkers.any(displayText.contains)
                                ? Colors.redAccent
                                : AppTheme.textSecondary;
                            return RichText(
                              text: TextSpan(
                                style: AppText.chatBody.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                                children: [
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Icon(
                                      isVideoCall ? Icons.videocam : Icons.call,
                                      size: 16,
                                      color: callIconColor,
                                    ),
                                  ),
                                  const WidgetSpan(child: SizedBox(width: 6)),
                                  TextSpan(text: displayText),
                                  const TextSpan(text: '  '),
                                  WidgetSpan(
                                    alignment:
                                        PlaceholderAlignment.belowBaseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: Text(
                                      timeStr,
                                      style: AppText.chatTime.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      else
                        MessageTextWithTime(
                          text: msg.text,
                          timeStr: msg.edited
                              ? '$timeStr ${s.msgEdited}'
                              : timeStr,
                          textStyle: AppText.chatBody,
                          timeStyle: AppText.chatTime.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                          alignRight: isMe,
                          mentions: msg.mentions,
                          highlightMentionAll: highlightMentionAll,
                          searchQuery: searchQuery,
                          trailing: isMe
                              ? Tooltip(
                                  message:
                                      isQueued ? s.msgWaitingConnection : '',
                                  child: Icon(
                                    (isPending || isQueued)
                                        ? Icons.done
                                        : Icons.done_all,
                                    size: 12,
                                    color: (!isQueued &&
                                            !isPending &&
                                            isRead)
                                        ? AppTheme.primary
                                        : AppTheme.textSecondary,
                                  ),
                                )
                              : null,
                        ),
                    ],
                  ),
                    ),
                      if (reactions != null && reactions!.isNotEmpty)
                      Positioned(
                        bottom: -10,
                        left: isMe ? null : 8,
                        right: isMe ? 8 : null,
                        child: _InlineReactionBadge(
                          counts: reactions!,
                          onTap: onTapBadge,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _InlineReactionBadge extends StatelessWidget {
  final Map<String, int> counts;
  final VoidCallback? onTap;
  const _InlineReactionBadge({required this.counts, this.onTap});
  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries.take(3).map((e) => e.key).join();
    final total = entries.fold<int>(0, (p, e) => p + e.value);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(shown, style: TextStyle(fontSize: AppGlyph.xs)),
          if (total > 1) ...[
            const SizedBox(width: 3),
            Text(
              '$total',
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// Geser bubble ke KANAN untuk balas (ala WhatsApp).
/// - `enabled=false` → widget ini transparan (child dikembalikan apa adanya).
/// - Tarik 0–72 px: bubble ikut bergeser, ikon reply muncul & menguat.
/// - Lepas ≥48 px → `onReply()` (composer masuk mode balas + fokus).
/// - Lepas < 48 px → kembali ke posisi semula (spring balik).
/// Menggunakan `onHorizontalDrag*` (bukan `Dismissible`) supaya bubble
/// tidak ikut terhapus/tergeser permanen dan bisa dipakai bersama
/// long-press + tap biasa.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback? onReply;
  const SwipeToReply({
    required this.child,
    required this.enabled,
    this.onReply,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  /// Jarak geser maksimum — cukup terasa tapi tidak menutupi bubble.
  static const double _maxDrag = 72;
  /// Ambang lepas untuk memicu balas.
  static const double _trigger = 48;

  double _drag = 0;

  void _onUpdate(DragUpdateDetails d) {
    // Hanya ke kanan; ke kiri diabaikan (tidak ada aksi).
    final next = (_drag + d.delta.dx).clamp(0.0, _maxDrag);
    if (next != _drag) setState(() => _drag = next);
  }

  void _onEnd(DragEndDetails d) {
    final shouldReply = _drag >= _trigger;
    // Ambang 48 px tercapai → picu balas; selain itu kembali ke 0.
    setState(() => _drag = 0);
    if (shouldReply) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final t = (_drag / _maxDrag).clamp(0.0, 1.0);
    return GestureDetector(
      // Horizontal drag dipakai HANYA untuk swipe-reply; scroll vertikal
      // list tetap menang karena gesture arena memisahkan arah.
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => setState(() => _drag = 0),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Ikon reply di kiri, muncul seiring tarikan.
          Positioned(
            left: 8,
            top: 0,
            bottom: 8,
            child: Center(
              child: Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: 0.7 + 0.3 * t,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.reply,
                      size: 16,
                      color: AppTheme.primary.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bubble bergeser mengikuti tarikan.
          Transform.translate(
            offset: Offset(_drag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// Image yang belum di-load (pesan lama di luar window 50) — placeholder
// dengan auto-load di latar (screen memanggil fetchImage otomatis);
// tap = retry manual. Spinner saat fetch berjalan (feedback nyata,
// dulu: klik "tidak berefek" karena fetch gagal diam-diam).
class DeferredImage extends StatefulWidget {
  final Future<void> Function()? onTap;
  const DeferredImage({super.key, this.onTap});

  @override
  State<DeferredImage> createState() => _DeferredImageState();
}

class _DeferredImageState extends State<DeferredImage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    return GestureDetector(
      onTap: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onTap?.call();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: Container(
        width: 200,
        height: 120,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppTheme.primary,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: AppTheme.textSecondary, size: 22),
                  SizedBox(height: 4),
                  Text(
                    s.msgPhotoTapToLoad,
                    style: AppText.chatCaption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class MessageImage extends StatefulWidget {
  final String imageData;
  final String chatKey;
  final String messageId;
  /// Lapor lebar render foto (200 atau `tinggi*aspect` bila tinggi dibatasi
  /// 280) agar caption+jam bisa rata kanan sejajar tepi foto.
  final ValueChanged<double>? onRenderedWidth;
  const MessageImage({
    super.key,
    required this.imageData,
    required this.chatKey,
    required this.messageId,
    this.onRenderedWidth,
  });

  @override
  State<MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<MessageImage> {
  DecodedImage? _decoded;
  // Foto BIASA (bukan view-once) tidak punya konsep expired — null berarti
  // "belum keload / gagal", bukan "kedaluwarsa". Selama download tampil
  // spinner; gagal tampil "ketuk untuk memuat", bukan tulisan expired.
  bool _loading = true;
  // Ukuran placeholder loading — langsung dicadangkan sesuai aspek foto
  // (header JPEG/PNG dibaca sinkron) supaya TIDAK mulai dari kotak 200×200
  // lalu loncat bentuk (nge-blink). Sama persis dengan ukuran gambar final.
  double _phW = 200;
  double _phH = 200;
  // Generasi decode: cegah hasil basi menimpa yang baru bila imageData
  // berubah cepat (path → thumbnail) sementara decode lama belum selesai.
  int _gen = 0;
  // Fade-in hanya untuk konten yang BARU dimuat elemen ini (dari placeholder
  // / pergantian gambar). Scroll-back (cache hit di initState) langsung
  // tampil tanpa animasi ulang — daftar foto tetap persistence.
  bool _fadeNext = false;
  // Zoom inline di dalam bubble — gambar tetap kecil di chat, tapi bisa
  // di-pinch 2 jari / ketuk 2x per kotak (mis. baca teks diagram).
  final TransformationController _trans = TransformationController();
  double _scale = 1.0;
  Offset _doubleTapPos = Offset.zero;
  // Lebar terakhir yang dilaporkan ke parent (hindari callback berulang).
  double _reportedWidth = -1;

  @override
  void initState() {
    super.initState();
    final key = widget.imageData.hashCode;
    _decoded = decodedImageCache[key];
    if (_decoded == null) {
      _loading = true;
      _fadeNext = true;
      _reservePlaceholder(widget.imageData);
      _decode(key, ++_gen);
    } else {
      _loading = false;
      final s = photoViewSize(_decoded!.width, _decoded!.height);
      _phW = s.width;
      _phH = s.height;
    }
    // PREFETCH full-res ke mem cache PhotoCache — supaya saat foto di-TAP,
    // viewer langsung dapat versi full (tanpa "tahan dulu" disk-read+decrypt).
    // Fire-and-forget; membuka viewer tetap instan dgn thumbnail lebih dulu.
    if (widget.chatKey.isNotEmpty && widget.messageId.isNotEmpty) {
      unawaited(PhotoCache.instance.load(widget.chatKey, widget.messageId));
    }
  }

  @override
  void dispose() {
    _trans.dispose();
    super.dispose();
  }

  void _resetZoom() {
    if (_scale <= 1.01) return;
    _trans.value = Matrix4.identity();
    _scale = 1.0;
  }

  void _toggleZoom() {
    if (!mounted) return;
    if (_scale > 1.01) {
      _trans.value = Matrix4.identity();
      setState(() => _scale = 1.0);
    } else {
      const s = 2.5;
      _trans.value = Matrix4.diagonal3Values(s, s, 1)
        ..setTranslationRaw(
          -_doubleTapPos.dx * (s - 1),
          -_doubleTapPos.dy * (s - 1),
          0,
        );
      setState(() => _scale = s);
    }
  }

  @override
  void didUpdateWidget(MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // imageData berubah (fetch awal kosong → photo download selesai) → re-decode
    if (widget.imageData != oldWidget.imageData &&
        widget.imageData.isNotEmpty) {
      _resetZoom();
      // Cadangkan aspek baru segera (sinkron) bila base64; path → ukuran lama
      // dipertahankan (gapless) sampai download memberi aspek sebenarnya.
      _reservePlaceholder(widget.imageData);
      final key = widget.imageData.hashCode;
      final hit = decodedImageCache[key];
      if (hit != null) {
        _gen++;
        _fadeNext = true;
        if (mounted) {
          setState(() {
            _decoded = hit;
            _loading = false;
            final s = photoViewSize(hit.width, hit.height);
            _phW = s.width;
            _phH = s.height;
          });
        }
      } else {
        // JANGAN kosongkan _decoded — foto lama tetap tampil sampai yang baru
        // siap (persistence, anti kedip). Hanya tandai loading untuk spinner
        // bila memang belum ada gambar sama sekali (lihat build).
        _fadeNext = true;
        if (mounted) {
          setState(() {
            _loading = true;
          });
        }
        _decode(key, ++_gen);
      }
    }
  }

  // Cadangkan ukuran placeholder dari header gambar (sinkron, tanpa isolate).
  // Base64 → baca dimensi JPEG/PNG langsung; path storage / tak dikenal →
  // biarkan ukuran lama (gapless, jangan kembali ke kotak).
  //
  // PERF: decode HANYA prefix header (bukan SELURUH base64) — foto besar bisa
  // ratusan KB; decode penuh di UI thread saat bubble mount/rebuild (mis. ada
  // pesan baru saat user mengetik) = stall input ("ngetik berenti").
  void _reservePlaceholder(String data) {
    if (data.isEmpty || StoragePhotoService.instance.isPath(data)) return;
    try {
      var dims = parseImageDimensions(_decodeHeaderPrefix(data));
      // Header di luar prefix (EXIF besar) → fallback decode penuh (jarang).
      dims ??= parseImageDimensions(base64Decode(data));
      if (dims == null) return;
      final s = photoViewSize(dims.width, dims.height);
      _phW = s.width;
      _phH = s.height;
    } catch (_) {}
  }

  /// Decode prefix base64 (header gambar) agar tak men-decode seluruh foto.
  static Uint8List _decodeHeaderPrefix(String b64) {
    const maxChars = 16384; // ~12 KB bytes — cukup untuk JPEG SOF/PNG/WebP.
    if (b64.length <= maxChars) return base64Decode(b64);
    var chunk = b64.substring(0, maxChars);
    final rem = chunk.length % 4;
    if (rem != 0) chunk = chunk.substring(0, chunk.length - rem);
    return base64Decode(chunk);
  }

  Future<void> _decode(int key, int gen) async {
    var data = widget.imageData;
    // LAZY PENUH: imageData kosong tapi file lokal ada (foto lama yang tidak
    // ikut bulk-decrypt saat buka chat) → pulihkan thumb dari disk. Tanpa ini
    // foto lama tampil "ketuk untuk memuat" selamanya.
    if (data.isEmpty &&
        widget.chatKey.isNotEmpty &&
        widget.messageId.isNotEmpty) {
      try {
        final diskThumb = await PhotoCache.instance.loadThumb(
          widget.chatKey,
          widget.messageId,
        );
        if (diskThumb != null && diskThumb.isNotEmpty) data = diskThumb;
      } catch (_) {}
    }
    // PATH storage (belum base64) → download dulu. decodeImageB64 melempar
    // null untuk input non-base64, jadi jangan memanggilnya dengan path.
    if (data.isNotEmpty && StoragePhotoService.instance.isPath(data)) {
      // Prefetch background (list pesan) biasanya sudah menyimpan thumb di
      // disk → tampilkan instan tanpa menunggu download + drain. Versi full
      // menyusul via drain (aspek sama, swap gapless).
      try {
        final thumbB64 = await PhotoCache.instance.loadThumb(
          widget.chatKey,
          widget.messageId,
        );
        if (thumbB64 != null &&
            thumbB64.isNotEmpty &&
            mounted &&
            gen == _gen) {
          final thumbBytes = base64Decode(thumbB64);
          final thumbDims = parseImageDimensions(thumbBytes);
          if (thumbDims != null) {
            final td = DecodedImage(
              thumbBytes,
              thumbDims.width,
              thumbDims.height,
            );
            _putDecodedCache(key, td);
            _fadeNext = true;
            setState(() {
              _decoded = td;
              _loading = false;
              final s = photoViewSize(thumbDims.width, thumbDims.height);
              _phW = s.width;
              _phH = s.height;
            });
            return;
          }
        }
      } catch (_) {}
      data = await StoragePhotoService.instance.download(data) ?? '';
    }
    if (!mounted || gen != _gen) return;
    if (data.isEmpty) {
      setState(() {
        _loading = false;
      });
      return;
    }
    // Pakai ulang hasil decode bila isinya SAMA (pending base64 vs download
    // path hasil upload sendiri) — tanpa compute ulang, tanpa kedip.
    final contentHit = decodedImageCache[data.hashCode];
    if (contentHit != null && contentHit.width > 0 && contentHit.height > 0) {
      _putDecodedCache(key, contentHit);
      if (!mounted || gen != _gen) return;
      setState(() {
        _decoded = contentHit;
        _loading = false;
        final s = photoViewSize(contentHit.width, contentHit.height);
        _phW = s.width;
        _phH = s.height;
      });
      return;
    }
    // Aspek sudah bisa dicadangkan dari data yang baru diunduh (sebelum
    // decode penuh) — placeholder menyesuaikan sekali ke bentuk benar,
    // piksel menyusul fade-in tanpa lompatan lagi.
    try {
      var dims = parseImageDimensions(_decodeHeaderPrefix(data));
      dims ??= parseImageDimensions(base64Decode(data));
      if (dims != null && mounted && gen == _gen) {
        final s = photoViewSize(dims.width, dims.height);
        setState(() {
          _phW = s.width;
          _phH = s.height;
        });
      }
    } catch (_) {}
    final res = await NativeImage.decodeWithDims(data);
    if (!mounted || gen != _gen) return;
    if (res == null) {
      // Decode gagal — jangan cache null (dipaksa `!` dulu bikin crash).
      setState(() {
        _loading = false;
      });
      return;
    }
    final decoded = DecodedImage(res.bytes, res.width, res.height);
    if (decoded.width <= 0 || decoded.height <= 0) {
      setState(() {
        _loading = false;
      });
      return;
    }
    _putDecodedCache(data.hashCode, decoded);
    _putDecodedCache(key, decoded);
    if (!mounted || gen != _gen) return;
    setState(() {
      _decoded = decoded;
      _loading = false;
      final s = photoViewSize(decoded.width, decoded.height);
      _phW = s.width;
      _phH = s.height;
    });
  }

  void _retry() {
    final key = widget.imageData.hashCode;
    _fadeNext = true;
    setState(() {
      _loading = true;
    });
    _decode(key, ++_gen);
  }

  // Lapor lebar render ke parent (sekali / berubah) → caption+jam rata kanan
  // sejajar tepi foto. Dipakai gambar final DAN placeholder supaya caption
  // langsung selebar foto dari frame pertama (tidak ikut loncat).
  void _reportWidth(double w) {
    final cb = widget.onRenderedWidth;
    if (cb != null && (w - _reportedWidth).abs() > 0.5) {
      _reportedWidth = w;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cb(w);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final decoded = _decoded;
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      // Foto biasa: belum keload = spinner; gagal = "ketuk untuk memuat".
      // JANGAN pakai tulisan expired di sini — itu hanya untuk view-once.
      // Ukuran = cadangan aspek foto (bukan kotak 200×200) + lebar dilaporkan
      // ke parent supaya caption langsung pas dari frame pertama.
      _reportWidth(_phW);
      return GestureDetector(
        onTap: _loading ? null : _retry,
        child: Container(
          width: _phW,
          height: _phH,
          color: AppTheme.bgInput,
          alignment: Alignment.center,
          child: _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppTheme.primary,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh,
                      color: AppTheme.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.msgPhotoTapToLoad,
                      style: AppText.chatBodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
        ),
      );
    }
    final size = photoViewSize(decoded.width, decoded.height);
    final width = size.width;
    final height = size.height;
    // Lapor lebar render ke parent (sekali / berubah) → caption+jam rata kanan
    // sejajar tepi foto.
    _reportWidth(width);
    return GestureDetector(
      onTap: () => _openFullscreen(),
      onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InteractiveViewer(
          transformationController: _trans,
          clipBehavior: Clip.hardEdge,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          minScale: 1.0,
          maxScale: 6.0,
          // Pan satu jari hanya saat sudah zoom — kalau skala 1.0, drag
          // tetap untuk scroll chat (pola sama seperti post_photo_viewer).
          panEnabled: _scale > 1.01,
          scaleEnabled: true,
          onInteractionUpdate: (_) {
            _scale = _trans.value.getMaxScaleOnAxis();
          },
          onInteractionEnd: (_) => setState(
            () => _scale = _trans.value.getMaxScaleOnAxis(),
          ),
          child: _fadeNext
              // Fade-in tiap KONTEN baru. Scroll-back / cache hit di initState
              // (_fadeNext=false) langsung tampil — tidak animasi ulang.
              ? TweenAnimationBuilder<double>(
                  key: ValueKey(decoded),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 180),
                  onEnd: () => _fadeNext = false,
                  builder: (_, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  child: _bubbleImage(
                    context,
                    decoded,
                    width,
                    height,
                    s,
                  ),
                )
              : _bubbleImage(context, decoded, width, height, s),
        ),
      ),
    );
  }

  // Gambar bubble (dipakai langsung / sebagai child fade-in).
  Widget _bubbleImage(
    BuildContext context,
    DecodedImage decoded,
    double width,
    double height,
    S s,
  ) {
    return Image.memory(
      decoded.bytes,
      width: width,
      height: height,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      // Decode max 1080px (bukan full-res 12MP): bubble max 280px,
      // zoom inline 6x tetap tajam; hemat ~6x RAM bitmap.
      cacheWidth: 1080,
      errorBuilder: (_, _, _) => GestureDetector(
        onTap: _retry,
        child: Container(
          width: width,
          height: height,
          color: AppTheme.bgInput,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh,
                color: AppTheme.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                s.msgPhotoTapToLoad,
                style: AppText.chatBodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullscreen() {
    final decoded = _decoded;
    if (decoded == null || !mounted) return;
    // Route KHUSUS viewer (fade + scale 200ms) — BUKAN slide global. Slide
    // horizontal terasa "berat/menunggu" untuk foto; zoom-in ala WhatsApp/M3
    // jauh lebih halus & tidak ada jeda. Thumbnail sudah tampil instan
    // (bytes bubble ada di ImageCache), full-res menyusul tanpa delay buatan.
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: null,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, __, ___) => PhotoViewerScreen(
          bytes: decoded.bytes,
          fullLoader: () =>
              PhotoCache.instance.load(widget.chatKey, widget.messageId),
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

// ── View Once Image ──────────────────────────────────────────────────────────
enum ViewOnceState { idle, viewing, expired }

// Timer & state persist di luar widget lifecycle — ListView.builder recycle
// widget saat scroll, tapi timer harus terus jalan & state tidak boleh reset.
/// Durasi view-once efektif (detik): null/negatif = legacy 10 dtk,
/// 0 = sampai ditutup (mode 1x lihat), N = countdown N detik.
int resolveViewOnceSecs(int? raw) => raw == null || raw < 0 ? 10 : raw;

class ViewOnceTick {
  int left = 10;

  /// Total countdown detik untuk pesan ini (0 = tanpa timer, sampai ditutup).
  int totalSecs = 10;
  Timer? timer;
  final ValueNotifier<int> countdown = ValueNotifier<int>(10);
  ViewOnceState _state = ViewOnceState.idle;
  final ValueNotifier<ViewOnceState> stateNotifier =
      ValueNotifier<ViewOnceState>(ViewOnceState.idle);
  bool viewerOpen = false;
  DecodedImage? decoded;

  ViewOnceState get state => _state;
  set state(ViewOnceState s) {
    _state = s;
    stateNotifier.value = s;
  }

  void dispose() {
    timer?.cancel();
    countdown.dispose();
    stateNotifier.dispose();
  }
}

final viewOnceStates = <String, ViewOnceTick>{};

class ViewOnceImage extends StatefulWidget {
  final String imageData;
  final String chatKey;
  final bool isMe;
  final String? messageId;

  /// Durasi view-once detik dari pesan (durationMs): null = legacy 10 dtk,
  /// 0 = sampai ditutup (1x lihat).
  final int? viewSecs;
  final bool isExpired;
  // Admin monitor: lewati kartu "expired" — foto tetap bisa dilihat.
  final bool isAdminView;
  // Room chat pakai tabel 'messages', private pakai 'private_messages'.
  final bool isRoom;
  const ViewOnceImage({
    super.key,
    required this.imageData,
    required this.chatKey,
    required this.isMe,
    this.messageId,
    this.viewSecs,
    this.isExpired = false,
    this.isAdminView = false,
    this.isRoom = false,
  });

  @override
  State<ViewOnceImage> createState() => _ViewOnceImageState();
}

class _ViewOnceImageState extends State<ViewOnceImage> {
  late ViewOnceTick _tick;
  DecodedImage? _decoded;

  @override
  void initState() {
    super.initState();
    // Admin monitor: bypass global viewOnceStates — tidak perlu timer/expired.
    // Decode langsung dari imageData (yang sekarang selalu utuh di DB).
    if (widget.isAdminView) {
      if (widget.imageData.isNotEmpty) _decodeAdmin();
      return;
    }
    final id = widget.messageId ?? 'pending-${widget.imageData.hashCode}';
    _tick = viewOnceStates[id] ?? (viewOnceStates[id] = ViewOnceTick());
    if (widget.viewSecs != null) {
      _tick.totalSecs = resolveViewOnceSecs(widget.viewSecs);
    }
    if (widget.isExpired && _tick.state != ViewOnceState.viewing) {
      _tick.state = ViewOnceState.expired;
    }
    if (_tick.state == ViewOnceState.expired) return;
    _decoded = _tick.decoded;
    if (_decoded == null) _decode();
  }

  @override
  void didUpdateWidget(ViewOnceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAdminView) {
      if (widget.imageData.isNotEmpty &&
          widget.imageData != oldWidget.imageData) {
        _decodeAdmin();
      }
      return;
    }
    if (widget.isExpired && _tick.state != ViewOnceState.viewing) {
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      setState(() {});
      return;
    }
    if (_tick.state == ViewOnceState.expired) return;
    if (widget.imageData != oldWidget.imageData &&
        widget.imageData.isNotEmpty) {
      _decoded = _tick.decoded;
      if (_decoded == null) _decode();
    }
  }

  Future<void> _decodeAdmin() async {
    var data = widget.imageData;
    // imageData bisa berupa PATH storage (foto baru) → download dari bucket.
    if (data.isNotEmpty && StoragePhotoService.instance.isPath(data)) {
      data = await StoragePhotoService.instance.download(data) ?? '';
    }
    if (data.isEmpty) return;
    final res = await NativeImage.decodeWithDims(data);
    if (!mounted) return;
    setState(() {
      _decoded = res == null
          ? null
          : DecodedImage(res.bytes, res.width, res.height);
    });
  }

  @override
  void dispose() {
    // Jangan dispose _tick selagi aktif — timer harus terus jalan via
    // viewOnceStates (mis. viewer masih terbuka / countdown berjalan, dan
    // widget bisa di-rebuild sementara state tetap hidup).
    //
    // TAPI: kalau sudah EXPIRED, state tidak dibutuhkan lagi (media hilang,
    // kartu terkunci permanen). Sebelumnya entri ini dibiarkan di map selamanya
    // → `viewOnceStates` tumbuh tanpa batas (tiap view-once menahan Timer +
    // DecodedImage=byte gambar) → memori naik terus sepanjang sesi. Sekarang
    // entri expired dibersihkan saat widget-nya dibuang.
    final id = widget.messageId;
    // Mode admin tidak memakai `_tick` (lihat initState) — jangan sentuh.
    if (!widget.isAdminView && id != null && _tick.state == ViewOnceState.expired) {
      if (identical(viewOnceStates[id], _tick)) {
        viewOnceStates.remove(id);
      }
      _tick.dispose();
    }
    super.dispose();
  }

  Future<void> _decode() async {
    // View-once SUDAH expired (server tandai type='view_once_expired') —
    // WAJIB terkunci permanen, apapun isi imageData. Jangan decode/tampil.
    if (widget.isExpired) {
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      if (mounted) setState(() {});
      return;
    }
    // Sender/load: kalau imageData thumbnail kosong, ambil dari PhotoCache
    // (messageId) dulu — view-once yang pernah dilihat pengirim harus tetap tampil.
    var data = widget.imageData;
    if (data.isEmpty) {
      final id = widget.messageId;
      if (id != null && !id.startsWith('pending-')) {
        try {
          data = await PhotoCache.instance.load(widget.chatKey, id) ?? '';
        } catch (_) {}
      }
    }
    // Data tidak tersedia (server sudah hapus image view-once & cache kosong)
    // → tampilkan kartu terkunci, jangan spinner muter terus.
    if (data.isEmpty) {
      // Kalau BUKAN expired (pesan baru view_once), jangan langsung kunci.
      // Realtime bisa truncate base64 besar → image_data broadcast kosong.
      // Photo download async akan mengisi imageData via didUpdateWidget.
      if (!widget.isExpired) return;
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      if (!mounted) return;
      setState(() {});
      return;
    }
    // Data bisa berupa PATH storage → download dulu sebelum decode.
    if (data.isNotEmpty && StoragePhotoService.instance.isPath(data)) {
      data = await StoragePhotoService.instance.download(data) ?? '';
      if (data.isEmpty) return;
    }
    final res = await NativeImage.decodeWithDims(data);
    if (res == null || res.width <= 0 || res.height <= 0) {
      // Decode gagal — jangan set _tick.decoded ke null/rusak.
      return;
    }
    final decoded = DecodedImage(res.bytes, res.width, res.height);
    _tick.decoded = decoded;
    if (!mounted) return;
    setState(() => _decoded = decoded);
    // Kalau user sudah tap "Lihat" sebelum gambar siap → mulai timer sekarang
    if (_tick.state == ViewOnceState.viewing && _tick.timer == null) {
      _beginCountdown();
    }
  }

  void _startViewing() {
    if (_tick.state != ViewOnceState.idle) return;
    _tick.state = ViewOnceState.viewing;
    setState(() {});
    ScreenSecureService.enterViewOnce();
    // Mulai timer hanya kalau gambar sudah siap — kalau belum, nunggu _decode selesai
    if (_decoded != null) {
      _beginCountdown();
    }
  }

  void _beginCountdown() {
    if (_tick.timer != null) return;
    // Mode 1x (totalSecs 0): tanpa timer — kedaluwarsa saat viewer ditutup.
    if (_tick.totalSecs <= 0) return;
    _tick.left = _tick.totalSecs;
    _tick.countdown.value = _tick.totalSecs;
    _tick.timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _tick.left--;
      _tick.countdown.value = _tick.left;
      if (_tick.left <= 0) {
        t.cancel();
        _tick.timer = null;
        if (_tick.viewerOpen && mounted) Navigator.of(context).maybePop();
        _expireNow();
        return;
      }
      if (mounted) setState(() {});
    });
  }

  /// Kunci permanen + bersihkan server (dipakai timer habis & viewer 1x ditutup).
  void _expireNow() {
    if (!mounted) return;
    _tick.state = ViewOnceState.expired;
    ScreenSecureService.exitViewOnce();
    setState(() {});
    _clearFromServer();
  }

  void _openViewer() {
    if (_decoded == null || _tick.state != ViewOnceState.viewing || !mounted)
      return;
    _tick.viewerOpen = true;
    Navigator.of(context)
        .push(
          // Route viewer sama dengan foto biasa (fade+scale halus), bukan slide.
          PageRouteBuilder<void>(
            opaque: true,
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 160),
            pageBuilder: (_, __, ___) => PhotoViewerScreen(
              bytes: _decoded!.bytes,
              fullLoader: () {
                final id = widget.messageId;
                if (id == null || id.startsWith('pending-'))
                  return Future.value(null);
                return PhotoCache.instance.load(widget.chatKey, id);
              },
              countdown: _tick.totalSecs > 0 ? _tick.countdown : null,
            ),
            transitionsBuilder: (_, anim, __, child) {
              final curved = CurvedAnimation(
                parent: anim,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
                  child: child,
                ),
              );
            },
          ),
        )
        .whenComplete(() {
          _tick.viewerOpen = false;
          // Mode 1x: viewer ditutup = sudah dilihat → kunci permanen.
          if (_tick.totalSecs <= 0 &&
              _tick.state == ViewOnceState.viewing) {
            _expireNow();
          }
        });
  }

  Future<void> _clearFromServer() async {
    final id = widget.messageId;
    if (id == null || id.startsWith('pending-')) return;
    try {
      await ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier).clearViewOnceImage(
        id,
        isRoom: widget.isRoom,
      );
    } catch (_) {}
  }

  Widget _buildAdminView(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final decoded = _decoded;
    final w = decoded != null ? _viewWidth(decoded) : 200.0;
    final h = decoded != null ? _viewHeight(decoded) : 200.0;
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            decoded != null
                ? Image.memory(
                    decoded.bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    // Thumb bubble: decode max 720px + filter sedang.
                    // Full-res 12MP = ~48MB bitmap; 720px = ~2MB.
                    cacheWidth: 720,
                    filterQuality: FilterQuality.medium,
                  )
                : Container(
                    color: AppTheme.bgInput,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white70,
                      ),
                    ),
                  ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      s.msgViewOnce,
                      style: AppText.chatTime.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (decoded == null) return child;
    final zoomBytes = decoded.bytes;
    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(
                          zoomBytes,
                          fit: BoxFit.contain,
                          // Cap 1080px: layar HP tidak butuh full-res 12MP.
                          cacheWidth: 1080,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ).then((_) {
          // Keluarkan bitmap zoom dari ImageCache (pola PhotoViewerScreen).
          if (zoomBytes.isNotEmpty) {
            try {
              PaintingBinding.instance.imageCache.evict(
                MemoryImage(zoomBytes),
              );
            } catch (_) {}
          }
        });
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAdminView) return _buildAdminView(context);
    return ValueListenableBuilder<ViewOnceState>(
      valueListenable: _tick.stateNotifier,
      builder: (_, st, _) {
        final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;

        // Pengirim lihat foto asli + badge
        if (widget.isMe) {
          // View-once terkunci (data sudah tidak tersedia) → kartu terkunci, bukan spinner
          if (_tick.state == ViewOnceState.expired) {
            return ViewOnceLockedCard(
              title: s.viewOnceExpired,
              hint: s.viewOnceExpiredHint,
            );
          }
          final decoded = _decoded;
          final w = decoded != null ? _viewWidth(decoded) : 200.0;
          final h = decoded != null ? _viewHeight(decoded) : 200.0;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  decoded != null
                      ? Image.memory(
                          decoded.bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          cacheWidth: 720,
                          filterQuality: FilterQuality.medium,
                        )
                      : Container(
                          color: AppTheme.bgInput,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            s.msgViewOnce,
                            style: AppText.chatTime.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Penerima — idle: kartu modern "tekan untuk melihat"
        if (_tick.state == ViewOnceState.idle) {
          return GestureDetector(
            onTap: _startViewing,
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryDark, AppTheme.accent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    child: const Icon(
                      Icons.remove_red_eye_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.viewOnceTitle,
                    style: AppText.chatBodySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.viewOnceTap,
                    textAlign: TextAlign.center,
                    style: AppText.chatCaption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.btnView,
                      style: AppText.chatName.copyWith(
                        color: const Color(0xFF1E88E5),
                        letterSpacing: 0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Expired — kartu terkunci (tanpa image — hemat memori & tidak load foto)
        if (_tick.state == ViewOnceState.expired) {
          return ViewOnceLockedCard(
            title: s.viewOnceExpired,
            hint: s.viewOnceExpiredHint,
          );
        }

        // Viewing — tampilkan foto proporsional + countdown; tap untuk memperbesar
        final decoded = _decoded;
        final vw = decoded != null ? _viewWidth(decoded) : 200.0;
        final vh = decoded != null ? _viewHeight(decoded) : 200.0;
        return GestureDetector(
          onTap: _openViewer,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: vw,
              height: vh,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  decoded != null
                      ? Image.memory(
                          decoded.bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          cacheWidth: 720,
                          filterQuality: FilterQuality.medium,
                        )
                      : Container(
                          color: AppTheme.bgInput,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          ValueListenableBuilder<int>(
                            valueListenable: _tick.countdown,
                            builder: (_, v, _) => Text(
                              _tick.totalSecs <= 0 ? '1×' : '${v}s',
                              style: AppText.chatName.copyWith(
                                color: Colors.white,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Lebar/tinggi tampilan proporsional (maks 200×280) sesuai rasio asli.
  static double _viewWidth(DecodedImage d) {
    final aspect = d.width / d.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return width;
  }

  static double _viewHeight(DecodedImage d) {
    final aspect = d.width / d.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return height;
  }
}

// ── Photo Viewer Fullscreen ─────────────────────────────────────────────────
// Menampilkan foto fullscreen (hitam) dengan zoom + close. Bubble mengirim
// THUMBNAIL (bytes) supaya viewer langsung tampil, lalu fullLoader mengambil
// versi full-res dari PhotoCache dan menggantinya begitu siap.
// Untuk view-once, countdown diteruskan dari state pemilik sehingga timer
// terus berjalan.
class PhotoViewerScreen extends StatefulWidget {
  final Uint8List bytes;
  final Future<String?> Function()? fullLoader;
  final ValueNotifier<int>? countdown;
  const PhotoViewerScreen({
    super.key,
    required this.bytes,
    this.fullLoader,
    this.countdown,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  Uint8List? _fullBytes;
  final TransformationController _trans = TransformationController();
  double _scale = 1.0;
  Offset _doubleTapPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    // Muat full-res MULAI frame pertama (post-frame) — BUKAN delay tetap
    // 350ms yang dulu bikin "nunggu dulu baru buka". Thumbnail sudah tampil
    // instan (bytes bubble ada di ImageCache); decode full dilakukan di
    // isolate (compute) sehingga TIDAK memblok frame transisi. Jadi foto
    // tampil seketika, ketajaman penuh menyusul begitu siap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFull();
    });
  }

  @override
  void dispose() {
    // Keluarkan bitmap full-res viewer dari ImageCache — kalau tidak,
    // tiap buka-tutup foto menumpuk puluhan MB bitmap sampai èvict LRU.
    final b = _fullBytes;
    if (b != null && b.isNotEmpty) {
      try {
        PaintingBinding.instance.imageCache.evict(MemoryImage(b));
      } catch (_) {}
    }
    _fullBytes = null;
    _trans.dispose();
    super.dispose();
  }

  Future<void> _loadFull() async {
    final loader = widget.fullLoader;
    if (loader == null) return;
    // File full bisa BELUM selesai di-download saat viewer dibuka (foto room
    // berupa path storage → download on-demand). Sekali coba = gagal diam
    // → viewer nyangkut di thumb/spinner. Coba ulang terbatas dengan backoff
    // selama viewer masih terbuka.
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt * 2));
        if (!mounted || _fullBytes != null) return;
      }
      try {
        final t0 = DateTime.now();
        final b64 = await loader();
        final t1 = DateTime.now();
        if (b64 == null || b64.isEmpty || !mounted) continue;
        final bytes = await NativeImage.decodeBytes(b64);
        final t2 = DateTime.now();
        if (bytes == null || !mounted) return;
        dlog('[PHOTO-TIME] viewer full b64=${(b64.length / 1024).round()}KB '
            'loader=${t1.difference(t0).inMilliseconds}ms '
            'b64decode=${t2.difference(t1).inMilliseconds}ms '
            'attempt=$attempt');
        setState(() => _fullBytes = bytes);
        return;
      } catch (_) {}
    }
  }

  void _applyScale(double next, {Offset? focal}) {
    final clamped = next.clamp(1.0, 6.0);
    if ((clamped - _scale).abs() < 0.001) return;
    if (clamped <= 1.01) {
      _trans.value = Matrix4.identity();
    } else if (focal != null) {
      _trans.value = Matrix4.diagonal3Values(clamped, clamped, 1)
        ..setTranslationRaw(
          -focal.dx * (clamped - 1),
          -focal.dy * (clamped - 1),
          0,
        );
    } else {
      final size = MediaQuery.sizeOf(context);
      final cx = size.width / 2;
      final cy = size.height / 2;
      _trans.value = Matrix4.diagonal3Values(clamped, clamped, 1)
        ..setTranslationRaw(-cx * (clamped - 1), -cy * (clamped - 1), 0);
    }
    setState(() => _scale = clamped);
  }

  void _handleDoubleTap() {
    if (_scale > 1.01) {
      _applyScale(1.0);
    } else {
      _applyScale(3.0, focal: _doubleTapPos);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final bytes = _fullBytes ?? widget.bytes;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _trans,
                  clipBehavior: Clip.none,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 1.0,
                  maxScale: 6.0,
                  panEnabled: true,
                  scaleEnabled: true,
                  onInteractionUpdate: (_) {
                    _scale = _trans.value.getMaxScaleOnAxis();
                  },
                  onInteractionEnd: (_) => setState(
                    () => _scale = _trans.value.getMaxScaleOnAxis(),
                  ),
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      // FASE AWAL (belum ada full): bytes = thumbnail bubble
                      // yang SUDAH didecode di ImageCache dengan cacheWidth
                      // 1080. Pakai 1080 juga → ImageCache HIT → tampil INSTAN
                      // tanpa re-decode. Dulu viewer memaksa 1600 walau masih
                      // bytes bubble 1080 → cache MISS → decode ulang bitmap
                      // besar tepat saat transisi push = "serasa lambat".
                      // FASE FULL (setelah _loadFull): pakai 1600 untuk zoom.
                      cacheWidth: _fullBytes == null ? 1080 : 1600,
                    ),
                  ),
                ),
              ),
            ),
            if (_fullBytes == null && widget.fullLoader != null)
              const Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: s.btnClose,
              ),
            ),
            if (_scale <= 1.01)
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.viewerZoomHint,
                      style: AppText.caption.copyWith(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.zoom_in,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => _applyScale(_scale * 1.4),
                      tooltip: s.btnZoomIn,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.zoom_out,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => _applyScale(_scale / 1.4),
                      tooltip: s.btnZoomOut,
                    ),
                  ),
                  if (_scale > 1.01) ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.restart_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => _applyScale(1.0),
                        tooltip: s.btnZoomReset,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.countdown != null)
              Positioned(
                top: 12,
                right: 16,
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.countdown!,
                  builder: (_, secs, _) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${secs}s',
                          style: AppText.bodyStrong.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bubble FOTO private chat.
///
/// - Tanpa caption: jam di-overlay di sudut kanan-bawah gambar (seperti
///   sebelumnya).
/// - Ada caption: jam **tidak** overlay; caption di bawah + jam rata kanan
///   sejajar tepi kanan foto (lebar render foto dilaporkan oleh MessageImage)
///   — aturan jarak caption↔jam SAMA seperti bubble teks.
class _PhotoBubble extends StatefulWidget {
  final MessageModel msg;
  final String chatKey;
  final String timeStr;
  final bool isMe;
  final bool isRead;
  final bool isPending;
  final bool isQueued;
  final bool showChecksBothSides;
  final bool highlightMentionAll;

  const _PhotoBubble({
    required this.msg,
    required this.chatKey,
    required this.timeStr,
    required this.isMe,
    required this.isRead,
    required this.isPending,
    required this.isQueued,
    required this.showChecksBothSides,
    required this.highlightMentionAll,
  });

  @override
  State<_PhotoBubble> createState() => _PhotoBubbleState();
}

class _PhotoBubbleState extends State<_PhotoBubble> {
  // Lebar render foto (dilaporkan MessageImage); 200 = default sebelum tahu.
  double _imgW = 200;

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final isMe = widget.isMe;
    final showChecks = isMe || widget.showChecksBothSides;
    final hasCaption = msg.text.isNotEmpty;
    final hasLink =
        hasCaption && LinkPreviewService.instance.extractUrl(msg.text) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              MessageImage(
                imageData: msg.imageData,
                chatKey: widget.chatKey,
                messageId: msg.id,
                onRenderedWidth: (w) {
                  if (mounted && (w - _imgW).abs() > 0.5) {
                    setState(() => _imgW = w);
                  }
                },
              ),
              // Overlay jam HANYA bila tanpa caption (ada caption → jam di
              // bawah, rata kanan sejajar tepi foto).
              if (!hasCaption)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.timeStr,
                          style: AppText.chatTime.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        if (showChecks) ...[
                          const SizedBox(width: 3),
                          Icon(
                            (widget.isPending || widget.isQueued)
                                ? Icons.done
                                : Icons.done_all,
                            size: 12,
                            color: (widget.isRead &&
                                    !widget.isPending &&
                                    !widget.isQueued)
                                ? const Color(0xFF7EC8FF)
                                : Colors.white70,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasLink)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: _imgW,
              child: LinkPreview(text: msg.text),
            ),
          ),
        if (hasCaption)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: SizedBox(
              width: _imgW,
              child: MediaCaptionTime(
                text: msg.text,
                timeStr: widget.timeStr,
                textStyle: AppText.chatBody.copyWith(
                  color: AppTheme.textPrimary,
                ),
                timeStyle: AppText.chatTime.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
                showChecks: showChecks,
                isPending: widget.isPending,
                isQueued: widget.isQueued,
                isRead: widget.isRead,
                leftInset: 8,
              ),
            ),
          ),
      ],
    );
  }
}
