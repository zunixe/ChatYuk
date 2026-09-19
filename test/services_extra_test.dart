import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/link_preview_service.dart';
import 'package:chatyuk/services/perf_probe.dart';

void main() {
  group('LinkPreviewService.extractUrl', () {
    final svc = LinkPreviewService.instance;

    test('ambil URL http pertama', () {
      expect(svc.extractUrl('lihat https://contoh.com/a'),
          'https://contoh.com/a');
      expect(svc.extractUrl('http://x.io'), 'http://x.io');
    });

    test('case-insensitive (HTTP uppercase)', () {
      expect(svc.extractUrl('Lihat HTTPS://Contoh.com/X'),
          'HTTPS://Contoh.com/X');
    });

    test('berhenti di spasi', () {
      expect(svc.extractUrl('buka https://a.com lalu lanjut'),
          'https://a.com');
    });

    test('tanpa URL → null', () {
      expect(svc.extractUrl('tidak ada link di sini'), isNull);
      expect(svc.extractUrl(''), isNull);
      expect(svc.extractUrl('ftp://bukan-http.com'), isNull);
    });

    test('URL di tengah teks + tanda baca menempel', () {
      final u = svc.extractUrl('cek (https://contoh.com/x) ya');
      expect(u, contains('https://contoh.com/x'));
    });
  });

  group('PerfProbe (mode off di test)', () {
    test('measuring false tanpa dart-define', () {
      expect(PerfProbe.measuring, isFalse);
    });

    test('timed meneruskan hasil fungsi apa adanya', () async {
      final r = await PerfProbe.timed('t', () async => 42);
      expect(r, 42);
    });

    test('timed meneruskan error', () async {
      expect(
        () => PerfProbe.timed('t', () async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
    });

    test('counter default 0 saat probe off', () {
      PerfProbe.buildCount('x');
      PerfProbe.notifyCount('x');
      expect(PerfProbe.buildsOf('x'), 0);
      expect(PerfProbe.notifiesOf('x'), 0);
    });

    test('tabStart/tabEnd tidak melempar saat off', () {
      expect(() {
        PerfProbe.tabStart(0);
        PerfProbe.tabEnd(0);
        PerfProbe.tabEnd(1); // tanpa start
      }, returnsNormally);
    });
  });
}
