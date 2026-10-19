import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/chat_filter.dart';

void main() {
  group('ChatFilter.fromKey', () {
    test('key valid dipetakan', () {
      expect(ChatFilter.fromKey('all'), ChatFilter.all);
      expect(ChatFilter.fromKey('unread'), ChatFilter.unread);
      expect(ChatFilter.fromKey('friends'), ChatFilter.friends);
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
      expect(
        ChatFilterLogic.matches(
          ChatFilter.all,
          unread: 0,
          otherRegistered: false,
        ),
        isTrue,
      );
      expect(
        ChatFilterLogic.matches(
          ChatFilter.all,
          unread: 5,
          otherRegistered: true,
        ),
        isTrue,
      );
    });

    test('unread hanya bila ada pesan belum dibaca', () {
      expect(
        ChatFilterLogic.matches(
          ChatFilter.unread,
          unread: 1,
          otherRegistered: true,
        ),
        isTrue,
      );
      expect(
        ChatFilterLogic.matches(
          ChatFilter.unread,
          unread: 0,
          otherRegistered: true,
        ),
        isFalse,
      );
    });

    test('friends hanya bila lawan sudah menjadi teman', () {
      expect(
        ChatFilterLogic.matches(
          ChatFilter.friends,
          unread: 0,
          otherRegistered: true,
          otherFriend: true,
        ),
        isTrue,
      );
      expect(
        ChatFilterLogic.matches(
          ChatFilter.friends,
          unread: 0,
          otherRegistered: true,
          otherFriend: false,
        ),
        isFalse,
      );
    });

    test('anon = lawan belum terdaftar', () {
      expect(
        ChatFilterLogic.matches(
          ChatFilter.anon,
          unread: 0,
          otherRegistered: false,
        ),
        isTrue,
      );
      expect(
        ChatFilterLogic.matches(
          ChatFilter.anon,
          unread: 0,
          otherRegistered: true,
        ),
        isFalse,
      );
    });

    test('registered = lawan sudah terdaftar', () {
      expect(
        ChatFilterLogic.matches(
          ChatFilter.registered,
          unread: 0,
          otherRegistered: true,
        ),
        isTrue,
      );
      expect(
        ChatFilterLogic.matches(
          ChatFilter.registered,
          unread: 0,
          otherRegistered: false,
        ),
        isFalse,
      );
    });

    test(
      'anon + registered saling eksklusif (semua chat masuk tepat satu)',
      () {
        for (final reg in [true, false]) {
          final inAnon = ChatFilterLogic.matches(
            ChatFilter.anon,
            unread: 0,
            otherRegistered: reg,
          );
          final inReg = ChatFilterLogic.matches(
            ChatFilter.registered,
            unread: 0,
            otherRegistered: reg,
          );
          expect(inAnon ^ inReg, isTrue, reason: 'registered=$reg');
        }
      },
    );
  });

  group('ChatFilterLogic.counts', () {
    test('countsWithFriends menghitung teman terpisah', () {
      final c = ChatFilterLogic.countsWithFriends([
        (unread: 1, registered: true, friend: true),
        (unread: 0, registered: true, friend: false),
        (unread: 0, registered: false, friend: false),
      ]);
      expect(c.all, 3);
      expect(c.friends, 1);
      expect(c.anon, 1);
      expect(c.registered, 2);
    });

    test('menghitung tiap kategori dari data nyata', () {
      final items = <({int unread, bool registered})>[
        (unread: 2, registered: true), // unread + registered
        (unread: 0, registered: true), // registered
        (unread: 3, registered: false), // unread + anon
        (unread: 0, registered: false), // anon
        (unread: 1, registered: false), // unread + anon
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

  // ── REGRESI: chip vs list harus konsisten ──────────────────────────────
  // Bug 2026-10-19 (Xiaomi): chip "Teman (1)" tampil tapi list kosong /
  // polos. Penyebab: angka chip dihitung ulang di post-frame memakai
  // `friends` yang SUDAH berubah, sedangkan list memakai snapshot lama.
  // Kontrak yang harus dijaga: untuk SATU snapshot data, angka chip tiap
  // filter HARUS sama dengan jumlah item yang lolos `matches()`.
  group('ChatFilterLogic konsistensi chip vs list', () {
    // Data uji: (uid, unread, registered, friend)
    const rows = <({String uid, int unread, bool registered, bool friend})>[
      (uid: 'a', unread: 0, registered: true, friend: true),
      (uid: 'b', unread: 2, registered: true, friend: false),
      (uid: 'c', unread: 0, registered: false, friend: false),
      (uid: 'd', unread: 1, registered: false, friend: true),
      (uid: 'e', unread: 0, registered: true, friend: true),
    ];

    int matchesCount(ChatFilter f) => rows
        .where(
          (r) => ChatFilterLogic.matches(
            f,
            unread: r.unread,
            otherRegistered: r.registered,
            otherFriend: r.friend,
          ),
        )
        .length;

    test('jumlah chip = jumlah item matches() untuk tiap filter', () {
      final c = ChatFilterLogic.countsWithFriends(
        rows.map(
          (r) => (unread: r.unread, registered: r.registered, friend: r.friend),
        ),
      );
      expect(matchesCount(ChatFilter.all), c.all);
      expect(matchesCount(ChatFilter.unread), c.unread);
      expect(matchesCount(ChatFilter.friends), c.friends);
      expect(matchesCount(ChatFilter.anon), c.anon);
      expect(matchesCount(ChatFilter.registered), c.registered);
      // Jumlah semua filter eksklusif anon+registered = all.
      expect(c.anon + c.registered, c.all);
    });

    test('chip friends > 0 TIDAK PERNAH menghasilkan list kosong', () {
      final c = ChatFilterLogic.countsWithFriends(
        rows.map(
          (r) => (unread: r.unread, registered: r.registered, friend: r.friend),
        ),
      );
      expect(c.friends, greaterThan(0));
      expect(
        matchesCount(ChatFilter.friends),
        c.friends,
        reason: 'chip "Teman (n)" wajib menampilkan tepat n item',
      );
    });

    test('snapshot friends konsisten: set sama → hasil sama', () {
      // Mensimulasikan dua pemanggilan dengan set teman BERBEDA (yang dulu
      // menyebabkan chip/list desync). Dengan satu snapshot dipakai untuk
      // keduanya, hasilnya harus identik.
      const snapshot = {'a', 'd', 'e'};
      final friendFlags = rows.map((r) => snapshot.contains(r.uid)).toList();
      final countFromSameSnapshot = ChatFilterLogic.countsWithFriends([
        for (var i = 0; i < rows.length; i++)
          (
            unread: rows[i].unread,
            registered: rows[i].registered,
            friend: friendFlags[i],
          ),
      ]);
      final listFromSameSnapshot = rows
          .asMap()
          .entries
          .where(
            (e) => ChatFilterLogic.matches(
              ChatFilter.friends,
              unread: e.value.unread,
              otherRegistered: e.value.registered,
              otherFriend: friendFlags[e.key],
            ),
          )
          .length;
      expect(listFromSameSnapshot, countFromSameSnapshot.friends);
      expect(listFromSameSnapshot, 3);
    });
  });
}
