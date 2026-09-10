import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/rt_resilient.dart';

void main() {
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
      final sub = listenResilient<int>(
        () {
          opens++;
          // 2 error pertama, percobaan ke-3 sukses.
          return opens <= 2
              ? Stream<int>.error(StateError('blip $opens'))
              : Stream.value(9);
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
      // Kalau backoff tidak reset, delay berikutnya 4s+jitter (3s min) dan
      // opens masih 3. Delay reset = 2s×0.75 = 1.5s paling cepat.
      async.elapse(const Duration(seconds: 3));
      expect(opens, 4, reason: 'backoff harus reset setelah sukses');
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
