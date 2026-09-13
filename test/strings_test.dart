import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';

/// Mengunci aturan bilingual AGENTS.md: string kritis tidak boleh kosong
/// di kedua bahasa, dan tidak boleh ada teks Indonesia hardcode di UI.
void main() {
  group('strings kritis bilingual', () {
    // [getterId, getterEn] — diakses langsung supaya compile-checked:
    // rename getter = test gagal compile = ketahuan seketika.
    final pairs = <List<String Function(S)>>[
      [(s) => s.navOnline, (s) => s.navOnline],
      [(s) => s.navChats, (s) => s.navChats],
      [(s) => s.navTimeline, (s) => s.navTimeline],
      [(s) => s.navProfile, (s) => s.navProfile],
      [(s) => s.btnSave, (s) => s.btnSave],
      [(s) => s.btnCancel, (s) => s.btnCancel],
      [(s) => s.btnLogin, (s) => s.btnLogin],
      [(s) => s.btnRetry, (s) => s.btnRetry],
      [(s) => s.errGeneric, (s) => s.errGeneric],
      [(s) => s.loading, (s) => s.loading],
      [(s) => s.msgServerError, (s) => s.msgServerError],
      [(s) => s.noPrivateChats, (s) => s.noPrivateChats],
      [(s) => s.emptyTimeline, (s) => s.emptyTimeline],
    ];

    test('tidak ada string kritis yang kosong (id & en)', () {
      final id = S(isId: true);
      final en = S(isId: false);
      for (final entry in pairs) {
        expect(entry[0](id).trim(), isNotEmpty);
        expect(entry[1](en).trim(), isNotEmpty);
      }
    });

    test('semua getter String di strings.dart punya isi di kedua cabang', () {
      // Pindai sumber: pola `String get xxx => isId ? '...' : '...';`
      // dengan salah satu cabang string kosong = pelanggaran.
      final src = File('lib/config/strings.dart').readAsStringSync();
      final re = RegExp(
          r"String get \w+ => isId \? '((?:[^'\\]|\\.)*)' : '((?:[^'\\]|\\.)*)';");
      var count = 0;
      String head(Match m) {
        final s = m.group(0)!;
        return s.length > 60 ? '${s.substring(0, 60)}…' : s;
      }

      for (final m in re.allMatches(src)) {
        count++;
        expect(m.group(1)!.trim(), isNotEmpty,
            reason: 'cabang id kosong: ${head(m)}');
        expect(m.group(2)!.trim(), isNotEmpty,
            reason: 'cabang en kosong: ${head(m)}');
      }
      expect(count, greaterThan(100),
          reason: 'pattern scan gagal menangkap getter (cek regex)');
    });
  });

  group('tanpa hardcode Indonesia di UI', () {
    // Kata penanda bahasa Indonesia yang hampir pasti bukan proper noun.
    final idMarkers = RegExp(
        r'\b(yang|dengan|untuk|belum|sudah|dari|kamu|kami|kita|pesan|silakan|tulis|kirim|batal|hapus|tutup|lanjut)\b');

    List<File> uiFiles() {
      final out = <File>[];
      for (final dir in ['lib/screens', 'lib/widgets']) {
        final d = Directory(dir);
        if (!d.existsSync()) continue;
        out.addAll(d
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')));
      }
      return out;
    }

    test('tidak ada Text(...) hardcode Indonesia', () {
      final hits = <String>[];
      final re = RegExp(r"""Text\(\s*'([^']+)'""");
      for (final f in uiFiles()) {
        final src = f.readAsStringSync();
        for (final m in re.allMatches(src)) {
          final lit = m.group(1)!;
          // Lewati emoji/glyph murni & interpolasi tunggal.
          if (lit.runes.every((r) =>
              r > 0x2500 ||
              r == 0x20 ||
              (r >= 0x30 && r <= 0x39) ||
              r == 0x25)) {
            continue;
          }
          if (idMarkers.hasMatch(lit.toLowerCase())) {
            hits.add('${f.path}: $lit');
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'hardcode Indonesia di UI:\n${hits.join('\n')}');
    });
  });
}
