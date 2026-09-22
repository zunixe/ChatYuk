import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/perf/perf_probe.dart';

/// Fase 4 — PerfProbe: statistik murni + kontrak pass-through.
/// CATATAN: `measuring` adalah const compile-time = false di test, jadi
/// `buildCount`/`record`/`report` no-op. Yang diuji: matematika _avg/_pct
/// dan bahwa `timed`/`measure` tetap menjalankan & mengembalikan fn().
void main() {
  group('avgOf', () {
    test('kosong → 0', () => expect(PerfProbe.avgOf([]), 0));
    test('satu elemen → nilai itu', () => expect(PerfProbe.avgOf([10]), 10));
    test('rata-rata benar', () {
      expect(PerfProbe.avgOf([10, 20, 30]), 20);
      expect(PerfProbe.avgOf([0, 100]), 50);
    });
  });

  group('pctOf (input sudah terurut)', () {
    test('kosong → 0', () => expect(PerfProbe.pctOf([], 50), 0));
    test('satu elemen → nilai itu', () => expect(PerfProbe.pctOf([7], 90), 7));

    test('p50 dari [0..100] = 50', () {
      final sorted = [for (var i = 0; i <= 100; i++) i];
      expect(PerfProbe.pctOf(sorted, 50), closeTo(50, 0.001));
    });

    test('p0 = elemen pertama, p100 = elemen terakhir', () {
      final sorted = [10, 20, 30, 40];
      expect(PerfProbe.pctOf(sorted, 0), 10);
      expect(PerfProbe.pctOf(sorted, 100), 40);
    });

    test('interpolasi: p50 dari [0,10] = 5', () {
      expect(PerfProbe.pctOf([0, 10], 50), closeTo(5, 0.001));
    });

    test('p90 <= max', () {
      final sorted = [for (var i = 1; i <= 10; i++) i * 10];
      expect(PerfProbe.pctOf(sorted, 90), lessThanOrEqualTo(100));
    });
  });

  group('timed / measure pass-through (saat not measuring)', () {
    test('timed mengembalikan nilai fn & menunggu selesai', () async {
      var ran = false;
      final out = await PerfProbe.timed('test.key', () async {
        ran = true;
        return 42;
      });
      expect(ran, isTrue);
      expect(out, 42);
    });

    test('timed meneruskan hasil Future yang lambat', () async {
      final out = await PerfProbe.timed('test.slow', () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return 'ok';
      });
      expect(out, 'ok');
    });

    test('measure mengembalikan nilai fn sinkron', () {
      expect(PerfProbe.measure('test.sync', () => 7 * 6), 42);
    });

    test('timed tidak menelan exception', () async {
      expect(
        () => PerfProbe.timed('test.err', () async => throw StateError('x')),
        throwsStateError,
      );
    });
  });

  group('counter no-op saat measuring=false', () {
    test('buildCount/notifyCount tidak mengubah hitungan', () {
      final before = PerfProbe.buildsOf('x');
      PerfProbe.buildCount('x');
      PerfProbe.notifyCount('x');
      expect(PerfProbe.buildsOf('x'), before);
      expect(PerfProbe.notifiesOf('x'), 0);
    });

    test('record/reset/report tidak crash saat non-measuring', () {
      expect(
        () {
          PerfProbe.record('k', const Duration(milliseconds: 1));
          PerfProbe.reset();
          PerfProbe.report('label');
        },
        returnsNormally,
      );
    });
  });
}
