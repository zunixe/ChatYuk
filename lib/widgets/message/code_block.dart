import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';

// Segmen hasil belah teks: teks biasa atau blok kode (pagar ```).
class MsgSegment {
  final bool isCode;
  final String lang;
  final String content;
  const MsgSegment(this.isCode, this.lang, this.content);
}

// Belah teks per pagar ``` — pagar tak tertutup tetap dianggap kode.
List<MsgSegment> splitCodeSegments(String t) {
  final parts = t.split('```');
  if (parts.length < 2) return [ MsgSegment(false, '', t) ];
  final segs = <MsgSegment>[];
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    if (i.isEven) {
      if (p.isNotEmpty) segs.add(MsgSegment(false, '', p));
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
      segs.add(MsgSegment(true, lang, code.trimRight()));
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
