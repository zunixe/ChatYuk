import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/strings_admin.dart';

/// Mengunci aturan bilingual + tipografi AGENTS.md.
void main() {
  group('strings kritis bilingual', () {
    final id = S(isId: true);
    final en = S(isId: false);

    test('tidak ada string kritis yang kosong (id & en)', () {
      final getters = <String>[
        id.navOnline,
        id.navChats,
        id.navTimeline,
        id.navProfile,
        id.btnSave,
        id.btnCancel,
        id.btnLogin,
        id.btnRetry,
        id.btnClose,
        id.errGeneric,
        id.loading,
        id.msgServerError,
        id.noPrivateChats,
        id.emptyTimeline,
      ];
      final gettersEn = <String>[
        en.navOnline,
        en.navChats,
        en.navTimeline,
        en.navProfile,
        en.btnSave,
        en.btnCancel,
        en.btnLogin,
        en.btnRetry,
        en.btnClose,
        en.errGeneric,
        en.loading,
        en.msgServerError,
        en.noPrivateChats,
        en.emptyTimeline,
      ];
      for (final v in [...getters, ...gettersEn]) {
        expect(v.trim(), isNotEmpty);
      }
    });

    test('getter guard admin tersedia dua bahasa', () {
      final id = S(isId: true);
      final en = S(isId: false);
      for (final v in [
        id.aiGuardGlobal,
        id.aiGuardOn,
        id.aiGuardOff,
        en.aiGuardGlobal,
        en.aiGuardOn,
        en.aiGuardOff,
      ]) {
        expect(v.trim(), isNotEmpty);
      }
    });

    test('semua getter String di strings.dart punya isi di kedua cabang', () {
      final raw = File('lib/config/strings.dart').readAsStringSync();
      final src = raw.replaceAll(RegExp(r'\s+'), ' ');
      final single = RegExp(
          r"String get \w+ .*?isId \? '((?:[^'\\]|\\.)*)' : '((?:[^'\\]|\\.)*)'");
      final double = RegExp(
          r'String get \w+ .*?isId \? "((?:[^"\\]|\\.)*)" : "((?:[^"\\]|\\.)*)"');
      var count = 0;
      for (final m in [...single.allMatches(src), ...double.allMatches(src)]) {
        count++;
        expect(m.group(1)!.trim(), isNotEmpty,
            reason: 'cabang id kosong: ${m.group(0)}');
        expect(m.group(2)!.trim(), isNotEmpty,
            reason: 'cabang en kosong: ${m.group(0)}');
      }
      final total = RegExp(r'String get \w+').allMatches(raw).length;
      expect(count, greaterThan(100),
          reason: 'pattern scan gagal menangkap getter (cek regex)');
      expect(count, greaterThanOrEqualTo((total * 0.9).floor()),
          reason:
              'terdeteksi $count dari $total getter — cek format getter baru');
    });
  });

  group('tanpa hardcode Indonesia di UI', () {
    final idMarkers = RegExp(
        r'\b(yang|dengan|untuk|belum|sudah|dari|kamu|kami|kita|pesan|silakan|tulis|kirim|batal|hapus|tutup|lanjut)\b');

    List<File> uiFiles() {
      final out = <File>[];
      for (final dir in ['lib/screens', 'lib/widgets', 'lib/providers']) {
        final d = Directory(dir);
        if (!d.existsSync()) continue;
        out.addAll(d
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')));
      }
      return out;
    }

    bool isGlyphOnly(String lit) {
      if (lit.trim().isEmpty) return true;
      if (!lit.contains(RegExp(r'[A-Za-z]'))) return true;
      return false;
    }

    test('tidak ada Text/SelectableText/RichText hardcode Indonesia', () {
      final hits = <String>[];
      final patterns = [
        RegExp(r"""Text\(\s*'([^']+)'"""),
        RegExp(r'''Text\(\s*"([^"]+)"'''),
        RegExp(r"""SelectableText\(\s*'([^']+)'"""),
        RegExp(r'''SelectableText\(\s*"([^"]+)"'''),
      ];
      for (final f in uiFiles()) {
        final src = f.readAsStringSync();
        for (final re in patterns) {
          for (final m in re.allMatches(src)) {
            final lit = m.group(1)!;
            if (isGlyphOnly(lit)) continue;
            if (idMarkers.hasMatch(lit.toLowerCase())) {
              hits.add('${f.path}: $lit');
            }
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'hardcode Indonesia di UI:\n${hits.join('\n')}');
    });

    test('tidak ada tooltip hardcode Indonesia', () {
      final hits = <String>[];
      final patterns = [
        RegExp(r"""tooltip:\s*'([^']+)'"""),
        RegExp(r'''tooltip:\s*"([^"]+)"'''),
      ];
      for (final f in uiFiles()) {
        final src = f.readAsStringSync();
        for (final re in patterns) {
          for (final m in re.allMatches(src)) {
            final lit = m.group(1)!;
            if (isGlyphOnly(lit)) continue;
            if (idMarkers.hasMatch(lit.toLowerCase())) {
              hits.add('${f.path}: $lit');
            }
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'tooltip hardcode Indonesia:\n${hits.join('\n')}');
    });
  });

  group('tipografi terkunci (AGENTS.md)', () {
    List<File> libFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // Normalisasi separator path (Windows: `lib\config\...`) supaya
    // pengecualian lib/config bekerja lintas OS.
    bool inLibConfig(File f) =>
        f.path.replaceAll(r'\', '/').contains('lib/config/');

    test('tidak ada fontSize numerik di luar lib/config', () {
      final hits = <String>[];
      final re = RegExp(r'fontSize:\s*[0-9]');
      for (final f in libFiles()) {
        if (inLibConfig(f)) continue;
        final src = f.readAsStringSync();
        for (final m in re.allMatches(src)) {
          hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty,
          reason: 'fontSize numerik di luar theme:\n${hits.join('\n')}');
    });

    test('tidak ada copyWith(fontSize:', () {
      final hits = <String>[];
      for (final f in libFiles()) {
        if (f.readAsStringSync().contains('copyWith(fontSize')) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty,
          reason: 'copyWith(fontSize: di:\n${hits.join('\n')}');
    });

    test('tidak ada height: 1.x di luar lib/config', () {
      final hits = <String>[];
      final re = RegExp(r'height:\s*1\.');
      for (final f in libFiles()) {
        if (inLibConfig(f)) continue;
        final src = f.readAsStringSync();
        for (final m in re.allMatches(src)) {
          hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty,
          reason: 'height manual di luar theme:\n${hits.join('\n')}');
    });
  });
}
