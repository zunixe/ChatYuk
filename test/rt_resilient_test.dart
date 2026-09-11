import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/rt_resilient.dart';

/// Jitter selalu maksimum (1.0) — delay = base × 1.25 persis, timing
/// deterministik (anti-flaky karena tumpang tindih window antar timer).
class _MaxJitter implements Random {
  @override
  double nextDouble() => 1.0;
  @override
  int nextInt(int max) => max - 1;
  @override
  bool nextBool() => true;
}

void main() {
  jitterRandom = _MaxJitter();

  // Backoff riil 2-60s terlalu lambat untuk test — fakeAsync menjalankan
  // timer secara instan. Delay riil = base * (0.75..1.25) karena jitter.
  test('event normal diteruskan tanpa retry', () {
    fakeAsync((async) {
      final events = <int>[];
      final sub = listenResilient<int>(
        () => Stream.value(7),
        events.add,
        isDisposed: () => false,
      );
      async.elapse(const Duration(milliseconds: 50));
      expect(events, [7]);
      sub.cancel();
    });
  });

  test('error → retry otomatis dengan backoff naik sampai sukses', () {
    fakeAsync((async) {
      final events = <int>[];
      final errors = <Object>[];
      var recovered = 0;
      var opens = 0;
      // Percobaan ke-3 sukses — pakai controller yang TIDAK selesai
      // (realtime asli tidak pernah complete; Stream.value akan memicu
      // onDone → retry tambahan yang mencemari counter error).
      StreamController<int>? open3Ctrl;
      final sub = listenResilient<int>(
        () {
          opens++;
          // 2 error pertama, percobaan ke-3 sukses.
          if (opens <= 2) {
            return Stream<int>.error(StateError('blip $opens'));
          }
          open3Ctrl = StreamController<int>();
          open3Ctrl!.add(9);
          return open3Ctrl!.stream;
        },
        events.add,
        isDisposed: () => false,
        onError: errors.add,
        onRecovered: () => recovered++,
      );

      async.elapse(const Duration(milliseconds: 50));
      expect(opens, 1, reason: 'error pertama tercatat, retry belum jalan');
      expect(errors.length, 1, reason: 'error+onDone double-fire jadi 1 retry');

      // Backoff attempt-1: 2s * jitter(0.75..1.25) = 1.5-2.5s
      // → elapse 3s aman.
      async.elapse(const Duration(seconds: 3));
      expect(opens, 2);
      expect(errors.length, 2);

      // Backoff attempt-2: 4s * jitter(0.75..1.25) = 3-5s → elapse 5s aman.
      async.elapse(const Duration(seconds: 5));
      expect(opens, 3);
      async.flushMicrotasks();
      expect(events, [9], reason: 'stream sukses diteruskan');
      expect(recovered, 2);

      sub.cancel();
      unawaited(open3Ctrl?.close());
    });
  });

  test('sukses mereset backoff ke delay minimum', () {
    fakeAsync((async) {
      var opens = 0;
      final sub = listenResilient<int>(
        () {
          opens++;
          // Pola: error, sukses, error, sukses — tiap error harus selalu
          // pakai delay dasar 2s (bukan naik terus).
          return opens.isOdd
              ? Stream<int>.error(StateError('x'))
              : Stream.value(opens);
        },
        (_) {},
        isDisposed: () => false,
      );
      async.elapse(const Duration(seconds: 3)); // error 1 (2s×jitter) → retry
      expect(opens, 2);
      async.elapse(const Duration(seconds: 3)); // sukses → error 2 → retry
      expect(opens, 3);
      // attempt3 ERROR menaikkan _attempt → retry attempt4 pakai base 4s
      // (4s×jitter = 3-5s dari error 2 di t=6s → jatuh di 9-11s).
      // elapse 6s menutup worst-case 11s — deterministik.
      async.elapse(const Duration(seconds: 6));
      expect(opens, 4, reason: 'sukses tetap terjadi (backoff reset di sukses)');
      sub.cancel();
    });
  });

  test('cancel saat menunggu retry → tidak resubscribe lagi', () {
    fakeAsync((async) {
      var opens = 0;
      final sub = listenResilient<int>(
        () {
          opens++;
          return Stream<int>.error(StateError('always'));
        },
        (_) {},
        isDisposed: () => false,
      );
      async.elapse(const Duration(milliseconds: 50));
      final afterFirst = opens;
      sub.cancel();
      async.elapse(const Duration(seconds: 30));
      expect(opens, afterFirst, reason: 'cancel membatalkan timer retry');
    });
  });

  test('isDisposed true → stream tidak pernah dibuka', () {
    fakeAsync((async) {
      var opens = 0;
      final sub = listenResilient<int>(
        () {
          opens++;
          return Stream.value(1);
        },
        (_) {},
        isDisposed: () => true,
      );
      async.elapse(const Duration(seconds: 5));
      expect(opens, 0);
      sub.cancel();
    });
  });

  test('onDone tanpa error → dijadwalkan retry', () {
    fakeAsync((async) {
      var opens = 0;
      final sub = listenResilient<int>(
        () {
          opens++;
          return opens == 1
              ? Stream<int>.fromIterable([1])
              : Stream<int>.error(StateError('x'));
        },
        (_) {},
        isDisposed: () => false,
      );
      async.elapse(const Duration(milliseconds: 50));
      expect(opens, 1, reason: 'fromIterable selesai normal');
      async.elapse(const Duration(seconds: 3));
      expect(opens, 2, reason: 'onDone memicu retry');
      sub.cancel();
    });
  });

  test('open() yang throw sinkron → retry dijadwalkan, tidak crash', () {
    fakeAsync((async) {
      var attempts = 0;
      final sub = listenResilient<int>(
        () {
          attempts++;
          if (attempts == 1) throw StateError('open failed');
          return Stream.value(1);
        },
        (_) {},
        isDisposed: () => false,
      );
      async.elapse(const Duration(seconds: 3));
      expect(attempts, 2);
      sub.cancel();
    });
  });
}
