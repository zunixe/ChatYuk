import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../config/gifts.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../services/photo_cache.dart';
import '../services/screen_secure_service.dart';
import '../services/storage_photo_service.dart';
import 'voice_bubble.dart';
import 'link_preview.dart';
import 'linkify_text.dart';
import '../services/link_preview_service.dart';

// cacheKey untuk PhotoCache = cacheKey yang dipakai chat_service
// ('private_$chatId' untuk private chat). Dipakai private chat & admin monitor.
String cacheKeyFor(String chatId) => 'private_$chatId';

// Top-level function untuk compute() isolate — decode base64 + dimensi di background
DecodedImage? decodeImageB64(String base64) {
  try {
    final bytes = base64Decode(base64);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return DecodedImage(bytes, 0, 0);
    return DecodedImage(bytes, decoded.width, decoded.height);
  } catch (_) {
    return null;
  }
}

// Hasil decode: bytes + dimensi asli agar tampilan proporsional.
class DecodedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const DecodedImage(this.bytes, this.width, this.height);
}

// Top-level untuk compute() — base64 → bytes (fullscreen viewer).
Uint8List? b64ToBytes(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

// Cache decode agar scroll-back tidak resize (glitch). Key = hash imageData, bounded 80 (LRU) cegah OOM di 1M.
final decodedImageCache = <int, DecodedImage>{};
const _decodedCacheMax = 80;
void _putDecodedCache(int key, DecodedImage img) {
  if (decodedImageCache.length >= _decodedCacheMax) {
    decodedImageCache.remove(decodedImageCache.keys.first);
  }
  decodedImageCache[key] = img;
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
    final s = context.read<LocaleProvider>().s;
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
class MessageTextWithTime extends StatelessWidget {
  final String text;
  final String timeStr;
  final TextStyle textStyle;
  final TextStyle timeStyle;
  final bool alignRight;
  final Widget? trailing;
  const MessageTextWithTime({
    super.key,
    required this.text,
    required this.timeStr,
    required this.textStyle,
    required this.timeStyle,
    required this.alignRight,
    this.trailing,
  });

  List<TextSpan> _linkifySpans(String t, TextStyle base) {
    final spans = <TextSpan>[];
    int last = 0;
    for (final m in RegExp(r'https?:\/\/[^\s]+').allMatches(t)) {
      if (m.start > last) spans.add(TextSpan(text: t.substring(last, m.start), style: base));
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: base.copyWith(color: AppTheme.primary, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () async {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            // ignore: avoid_dynamic_calls
            try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
          }
        },
      ));
      last = m.end;
    }
    if (last < t.length) spans.add(TextSpan(text: t.substring(last), style: base));
    if (spans.isEmpty) spans.add(TextSpan(text: t, style: base));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    // Spasi/newline di ujung tidak terlihat tapi menggeser jam — rapikan
    // dulu (ala WhatsApp) supaya jam selalu mepet akhir teks terlihat.
    final t = text.trimRight().isEmpty ? text : text.trimRight();
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
        final probe = probeTp()..layout(maxWidth: available);
        double longest = 0;
        for (final lm in probe.computeLineMetrics()) {
          if (lm.width > longest) longest = lm.width;
        }
        final contentW = math.min(available, math.max(longest, timeRowW));
        // Metrik baris terakhir layout final → jam 2px di bawah baseline
        // teks (tidak sejajar) — sama untuk pengirim maupun penerima.
        final fin = probeTp()..layout(maxWidth: contentW);
        final lastLine = fin.computeLineMetrics().last;
        final timeBottom =
            math.max(0.0, lastLine.descent - timeDescent - 2);
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
  });

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    // Pesan yang dihapus (soft delete) → tampilkan teks redup, bukan isinya.
    if (msg.isDeleted) {
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
    final timeStr = formatBubbleTime(msg.timestamp);
    return CompositedTransformTarget(
      link: link,
      child: GestureDetector(
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
                    color: msg.type == 'coin'
                        ? Color(0xFFFFF3C4)
                        : (isMe
                              ? Color.alphaBlend(
                                  AppTheme.primary.withValues(alpha: 0.25),
                                  AppTheme.bgCard,
                                )
                              : AppTheme.bgCard),
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
                        Builder(builder: (ctx) {
                          final s = ctx.read<LocaleProvider>().s;
                          // PRIVASI: target reply terhapus → "Pesan dihapus".
                          final targetDeleted = msg.repliedToId != null &&
                              deletedIds.contains(msg.repliedToId);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : AppTheme.bgScreen.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(
                                  color: AppTheme.primary,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.repliedToSenderName ?? '',
                                  style: AppText.chatName,
                                ),
                                Text(
                                  targetDeleted
                                      ? s.messageDeleted
                                      : msg.repliedToText!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.chatBodySmall.copyWith(
                                    fontStyle: targetDeleted
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
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
                      else if (msg.type == 'image' && msg.imageData.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  MessageImage(
                                    imageData: msg.imageData,
                                    chatKey: chatKey,
                                    messageId: msg.id,
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
                                          if (isMe) ...[
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
                            ),
                            if (msg.text.isNotEmpty && LinkPreviewService.instance.extractUrl(msg.text) != null)
                              LinkPreview(text: msg.text),
                            if (msg.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: LinkifyText(
                                  msg.text,
                                  style: AppText.chatBody.copyWith(color: AppTheme.textPrimary),
                                ),
                              ),
                          ],
                        )
                      else if (msg.type == 'image' &&
                          msg.imageData.isEmpty &&
                          isImageDeferred)
                        DeferredImage(
                          onTap: () async => onRetryImage?.call(msg.id),
                        )
                      else if (msg.type == 'view_once' ||
                          msg.type == 'view_once_expired')
                        Stack(
                          children: [
                            ViewOnceImage(
                              imageData: msg.imageData,
                              chatKey: chatKey,
                              isMe: isMe,
                              messageId: msg.id,
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
                                    if (isMe) ...[
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
                        )
                      else if (msg.type == 'coin')
                        Builder(
                          builder: (context) {
                            final s = context.read<LocaleProvider>().s;
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
                            final s = context.read<LocaleProvider>().s;
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
    final s = context.read<LocaleProvider>().s;
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
  const MessageImage({
    super.key,
    required this.imageData,
    required this.chatKey,
    required this.messageId,
  });

  @override
  State<MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<MessageImage> {
  DecodedImage? _decoded;
  // Zoom inline di dalam bubble — gambar tetap kecil di chat, tapi bisa
  // di-pinch 2 jari / ketuk 2x per kotak (mis. baca teks diagram).
  final TransformationController _trans = TransformationController();
  double _scale = 1.0;
  Offset _doubleTapPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    final key = widget.imageData.hashCode;
    _decoded = decodedImageCache[key];
    if (_decoded == null) _decode(key);
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
      final key = widget.imageData.hashCode;
      _decoded = decodedImageCache[key];
      if (_decoded == null) _decode(key);
    }
  }

  Future<void> _decode(int key) async {
    var data = widget.imageData;
    dlog('[PHOTO-DBG] MessageImage ${widget.messageId} inLen=${data.length} isPath=${StoragePhotoService.instance.isPath(data)}');
    // PATH storage (belum base64) → download dulu. decodeImageB64 melempar
    // null untuk input non-base64, jadi jangan memanggilnya dengan path.
    if (data.isNotEmpty && StoragePhotoService.instance.isPath(data)) {
      data = await StoragePhotoService.instance.download(data) ?? '';
      dlog('[PHOTO-DBG] MessageImage ${widget.messageId} downloaded len=${data.length}');
    }
    if (data.isEmpty) return;
    final decoded = await compute(decodeImageB64, data);
    dlog('[PHOTO-DBG] MessageImage ${widget.messageId} decoded=${decoded != null && decoded.width > 0}');
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      // Decode gagal — jangan cache null (dipaksa `!` dulu bikin crash).
      return;
    }
    _putDecodedCache(key, decoded);
    if (!mounted) return;
    setState(() => _decoded = decoded);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    final decoded = _decoded;
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      // Gagal muat (mis. download path diagram tersendat) — tap untuk coba
      // lagi, bukan placeholder mati.
      return GestureDetector(
        onTap: () => _decode(widget.imageData.hashCode),
        child: Container(
          width: 200,
          height: 200,
          color: AppTheme.bgInput,
          alignment: Alignment.center,
          child: Text(
            s.msgPhotoExpired,
            style: AppText.chatBodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    final aspect = decoded.width / decoded.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
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
          child: Image.memory(
            decoded.bytes,
            width: width,
            height: height,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Container(
              width: 200,
              height: 200,
              color: AppTheme.bgInput,
              alignment: Alignment.center,
              child: Text(
                s.msgPhotoExpired,
                style: AppText.chatBodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen() {
    final decoded = _decoded;
    if (decoded == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          bytes: decoded.bytes,
          fullLoader: () =>
              PhotoCache.instance.load(widget.chatKey, widget.messageId),
        ),
      ),
    );
  }
}

// ── View Once Image ──────────────────────────────────────────────────────────
enum ViewOnceState { idle, viewing, expired }

// Timer & state persist di luar widget lifecycle — ListView.builder recycle
// widget saat scroll, tapi timer harus terus jalan & state tidak boleh reset.
class ViewOnceTick {
  int left = 10;
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
    final decoded = await compute(decodeImageB64, data);
    if (!mounted) return;
    setState(() => _decoded = decoded);
  }

  @override
  void dispose() {
    // Jangan dispose _tick — timer harus terus jalan via viewOnceStates
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
    final decoded = await compute(decodeImageB64, data);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      // Decode gagal — jangan set _tick.decoded ke null/rusak.
      return;
    }
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
    _tick.left = 10;
    _tick.countdown.value = 10;
    _tick.timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _tick.left--;
      _tick.countdown.value = _tick.left;
      if (_tick.left <= 0) {
        t.cancel();
        _tick.timer = null;
        _tick.state = ViewOnceState.expired;
        ScreenSecureService.exitViewOnce();
        if (_tick.viewerOpen && mounted) Navigator.of(context).maybePop();
        if (mounted) {
          setState(() {});
          _clearFromServer();
        }
        return;
      }
      if (mounted) setState(() {});
    });
  }

  void _openViewer() {
    if (_decoded == null || _tick.state != ViewOnceState.viewing || !mounted)
      return;
    _tick.viewerOpen = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PhotoViewerScreen(
              bytes: _decoded!.bytes,
              fullLoader: () {
                final id = widget.messageId;
                if (id == null || id.startsWith('pending-'))
                  return Future.value(null);
                return PhotoCache.instance.load(widget.chatKey, id);
              },
              countdown: _tick.countdown,
            ),
          ),
        )
        .whenComplete(() => _tick.viewerOpen = false);
  }

  Future<void> _clearFromServer() async {
    final id = widget.messageId;
    if (id == null || id.startsWith('pending-')) return;
    try {
      await context.read<ChatProvider>().clearViewOnceImage(
        id,
        isRoom: widget.isRoom,
      );
    } catch (_) {}
  }

  Widget _buildAdminView(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
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
                    filterQuality: FilterQuality.high,
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
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(decoded.bytes, fit: BoxFit.contain),
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
        );
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
        final s = context.read<LocaleProvider>().s;

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
                          filterQuality: FilterQuality.high,
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
                              '${v}s',
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
    _loadFull();
  }

  @override
  void dispose() {
    _trans.dispose();
    super.dispose();
  }

  Future<void> _loadFull() async {
    final loader = widget.fullLoader;
    if (loader == null) return;
    try {
      final b64 = await loader();
      if (b64 == null || b64.isEmpty || !mounted) return;
      final bytes = await compute(b64ToBytes, b64);
      if (bytes == null || !mounted) return;
      setState(() => _fullBytes = bytes);
    } catch (_) {}
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
    final s = context.read<LocaleProvider>().s;
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

// Kartu "foto sudah kadaluarsa" — dipakai pengirim & penerima (design sama).
class ViewOnceLockedCard extends StatelessWidget {
  final String title;
  final String hint;
  const ViewOnceLockedCard({
    super.key,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        height: 140,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF37474F), Color(0xFF263238)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_clock_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppText.chatName.copyWith(
                      color: Colors.white,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: AppText.chatTime.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
