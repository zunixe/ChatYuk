import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/ui/online_pill_mode.dart';

/// Kapsul halaman Online bergantian TIAP JAM antara Timeline & Global Room.
void main() {
  group('onlinePillModeFor', () {
    test('jam genap → Timeline', () {
      for (final h in [0, 2, 8, 10, 22]) {
        expect(
          onlinePillModeFor(DateTime(2026, 9, 29, h, 30)),
          OnlinePillMode.timeline,
          reason: 'jam $h harusnya timeline',
        );
      }
    });

    test('jam ganjil → Global Room', () {
      for (final h in [1, 3, 9, 15, 23]) {
        expect(
          onlinePillModeFor(DateTime(2026, 9, 29, h, 15)),
          OnlinePillMode.globalRoom,
          reason: 'jam $h harusnya global room',
        );
      }
    });

    test('bergantian tiap jam (jam 21→22→23)', () {
      final a = onlinePillModeFor(DateTime(2026, 9, 29, 21));
      final b = onlinePillModeFor(DateTime(2026, 9, 29, 22));
      final c = onlinePillModeFor(DateTime(2026, 9, 29, 23));
      expect(a, OnlinePillMode.globalRoom);
      expect(b, OnlinePillMode.timeline);
      expect(c, OnlinePillMode.globalRoom);
      expect(a != b && b != c, isTrue);
    });
  });

  group('untilNextHour', () {
    test('menuju jam berikutnya', () {
      final d = untilNextHour(DateTime(2026, 9, 29, 10, 59, 30));
      expect(d.inSeconds, 30);
    });

    test('tepat di menit :00 → 1 jam penuh', () {
      final d = untilNextHour(DateTime(2026, 9, 29, 10, 0, 0));
      expect(d.inSeconds, 3600);
    });

    test('selalu > 0 (tidak ada timer 0-durasi)', () {
      // mendekati pergantian jam (mis. 59:59.9)
      final d = untilNextHour(DateTime(2026, 9, 29, 10, 59, 59, 900));
      expect(d.inMilliseconds, greaterThan(0));
      // tengah malam pun aman
      final m = untilNextHour(DateTime(2026, 9, 29, 23, 59, 59));
      expect(m.inSeconds, 1);
    });
  });
}
