import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/chat_filter.dart';

void main() {
  group('ChatFilter.fromKey', () {
    test('key valid dipetakan', () {
      expect(ChatFilter.fromKey('all'), ChatFilter.all);
      expect(ChatFilter.fromKey('unread'), ChatFilter.unread);
      expect(ChatFilter.fromKey('anon'), ChatFilter.anon);
      expect(ChatFilter.fromKey('registered'), ChatFilter.registered);
    });

    test('key tak dikenal / null → all (fallback aman)', () {
      expect(ChatFilter.fromKey('ngawur'), ChatFilter.all);
      expect(ChatFilter.fromKey(null), ChatFilter.all);
    });
  });

  group('ChatFilterLogic.matches', () {
    test('all selalu cocok', () {
      expect(ChatFilterLogic.matches(ChatFilter.all, unread: 0, otherRegistered: false), isTrue);
      expect(ChatFilterLogic.matches(ChatFilter.all, unread: 5, otherRegistered: true), isTrue);
    });

    test('unread hanya bila ada pesan belum dibaca', () {
      expect(ChatFilterLogic.matches(ChatFilter.unread, unread: 1, otherRegistered: true), isTrue);
      expect(ChatFilterLogic.matches(ChatFilter.unread, unread: 0, otherRegistered: true), isFalse);
    });

    test('anon = lawan belum terdaftar', () {
      expect(ChatFilterLogic.matches(ChatFilter.anon, unread: 0, otherRegistered: false), isTrue);
      expect(ChatFilterLogic.matches(ChatFilter.anon, unread: 0, otherRegistered: true), isFalse);
    });

    test('registered = lawan sudah terdaftar', () {
      expect(ChatFilterLogic.matches(ChatFilter.registered, unread: 0, otherRegistered: true), isTrue);
      expect(ChatFilterLogic.matches(ChatFilter.registered, unread: 0, otherRegistered: false), isFalse);
    });

    test('anon + registered saling eksklusif (semua chat masuk tepat satu)', () {
      for (final reg in [true, false]) {
        final inAnon = ChatFilterLogic.matches(ChatFilter.anon, unread: 0, otherRegistered: reg);
        final inReg = ChatFilterLogic.matches(ChatFilter.registered, unread: 0, otherRegistered: reg);
        expect(inAnon ^ inReg, isTrue, reason: 'registered=$reg');
      }
    });
  });

  group('ChatFilterLogic.counts', () {
    test('menghitung tiap kategori dari data nyata', () {
      final items = <({int unread, bool registered})>[
        (unread: 2, registered: true),   // unread + registered
        (unread: 0, registered: true),   // registered
        (unread: 3, registered: false),  // unread + anon
        (unread: 0, registered: false),  // anon
        (unread: 1, registered: false),  // unread + anon
      ];
      final c = ChatFilterLogic.counts(items);
      expect(c.all, 5);
      expect(c.unread, 3);
      expect(c.anon, 3);
      expect(c.registered, 2);
      // Invariant: anon + registered = all.
      expect(c.anon + c.registered, c.all);
    });

    test('daftar kosong → semua nol', () {
      final c = ChatFilterLogic.counts(const []);
      expect(c.all, 0);
      expect(c.unread, 0);
      expect(c.anon, 0);
      expect(c.registered, 0);
    });

    test('unread tidak melebihi all', () {
      final items = <({int unread, bool registered})>[
        (unread: 9, registered: true),
        (unread: 4, registered: false),
      ];
      final c = ChatFilterLogic.counts(items);
      expect(c.unread, lessThanOrEqualTo(c.all));
    });
  });
}
