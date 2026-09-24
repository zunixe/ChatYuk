import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/services/admin_service.dart';

/// Bukti refactor DI: `AdminProvider` menerima `AdminService` dari luar
/// sehingga logika provider bisa diuji tanpa Supabase/jaringan.
class MockAdminService extends Mock implements AdminService {}

void main() {
  late MockAdminService service;
  late AdminProvider provider;

  setUp(() {
    service = MockAdminService();
    provider = AdminProvider(service: service);
  });

  tearDown(() => provider.dispose());

  group('DI AdminProvider', () {
    test('pakai service yang disuntik (bukan Supabase.instance)', () {
      // Konstruksi tidak menyentuh Supabase.instance — kalau provider masih
      // hardcode `AdminService(Supabase.instance.client)`, test ini gagal
      // (Supabase belum di-init di test).
      expect(provider, isNotNull);
    });

    test('getPointSettings delegasi ke service yang disuntik', () async {
      when(() => service.getPointSettings())
          .thenAnswer((_) async => {'enabled': true});

      final res = await provider.getPointSettings();

      expect(res['enabled'], isTrue);
      verify(() => service.getPointSettings()).called(1);
    });

    test('isNicknameAvailable delegasi + teruskan excludeUid', () async {
      when(() => service.isNicknameAvailable(any(), excludeUid: any(named: 'excludeUid')))
          .thenAnswer((_) async => true);

      final ok = await provider.isNicknameAvailable('Budi', excludeUid: 'u1');

      expect(ok, isTrue);
      verify(() => service.isNicknameAvailable('Budi', excludeUid: 'u1'))
          .called(1);
    });

    test('listDummiesPage delegasi limit/offset', () async {
      when(() => service.listDummiesPage(limit: any(named: 'limit'), offset: any(named: 'offset')))
          .thenAnswer((_) async => {'rows': [], 'total': 0});

      final res = await provider.listDummiesPage(limit: 10, offset: 20);

      expect(res['total'], 0);
      verify(() => service.listDummiesPage(limit: 10, offset: 20)).called(1);
    });

    test('deleteDummy delegasi uid', () async {
      when(() => service.deleteDummy(any()))
          .thenAnswer((_) async => {'ok': true});

      final res = await provider.deleteDummy('d1');

      expect(res['ok'], isTrue);
      verify(() => service.deleteDummy('d1')).called(1);
    });

    test('error dari service diteruskan (tidak ditelan diam)', () async {
      when(() => service.getPointSettings())
          .thenAnswer((_) async => throw Exception('boom'));

      await expectLater(
        provider.getPointSettings(),
        throwsA(isA<Exception>()),
      );
    });
  });
  group('Tab Terhapus: arsip + anon pending', () {
    test('listDeleted meneruskan includePending=true', () async {
      when(() => service.listDeleted(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            includePending: any(named: 'includePending'),
          )).thenAnswer((_) async => {
            'items': [
              {'user_id': 'd1', 'nickname': 'lama', 'pending': false},
              {'user_id': 'p1', 'nickname': 'anon1', 'pending': true},
            ],
            'total': 2,
          });

      await provider.fetchDeleted();

      // Item pending ikut terisi (ditandai `pending: true`).
      expect(provider.deleted.length, 2);
      expect(provider.deleted.where((r) => r['pending'] == true).length, 1);
      verify(() => service.listDeleted(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            includePending: true,
          )).called(1);
    });

    test('deleteAnonUser sukses → refresh daftar', () async {
      when(() => service.deleteAnonUser('a1'))
          .thenAnswer((_) async => {'ok': true, 'nickname': 'anon1'});
      when(() => service.listDeleted(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            includePending: any(named: 'includePending'),
          )).thenAnswer((_) async => {'items': const [], 'total': 0});

      final res = await provider.deleteAnonUser('a1');

      expect(res['ok'], isTrue);
      verify(() => service.deleteAnonUser('a1')).called(1);
      // Refresh dipicu setelah sukses.
      verify(() => service.listDeleted(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            includePending: any(named: 'includePending'),
          )).called(1);
    });

    test('deleteAnonUser ditolak (REGISTERED) → TIDAK refresh', () async {
      when(() => service.deleteAnonUser('r1'))
          .thenAnswer((_) async => {'ok': false, 'error': 'REGISTERED'});

      final res = await provider.deleteAnonUser('r1');

      expect(res['ok'], isFalse);
      expect(res['error'], 'REGISTERED');
      verifyNever(() => service.listDeleted(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            includePending: any(named: 'includePending'),
          ));
    });

    test('deleteAnonUser dummy ditolak dengan error DUMMY', () async {
      when(() => service.deleteAnonUser('d1'))
          .thenAnswer((_) async => {'ok': false, 'error': 'DUMMY'});

      final res = await provider.deleteAnonUser('d1');

      expect(res['error'], 'DUMMY');
    });

    test('deleteBatchUsers menghapus arsip dan anon serta refresh daftar', () async {
      when(() => service.deleteArchivedUsers(['u1', 'u2']))
          .thenAnswer((_) async {});
      when(() => service.deleteAnonUser('a1'))
          .thenAnswer((_) async => {'ok': true});
      when(() => service.listDeleted(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            includePending: any(named: 'includePending'),
          )).thenAnswer((_) async => {'items': [], 'total': 0});

      final items = [
        {'user_id': 'u1', 'pending': false},
        {'user_id': 'a1', 'pending': true},
        {'user_id': 'u2', 'pending': false},
      ];

      final count = await provider.deleteBatchUsers(items);

      expect(count, 3);
      verify(() => service.deleteArchivedUsers(['u1', 'u2'])).called(1);
      verify(() => service.deleteAnonUser('a1')).called(1);
      verify(() => service.listDeleted(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            includePending: any(named: 'includePending'),
          )).called(1);
    });
  });

  group('refreshChats — anti "kadang muncul kadang ilang"', () {
    Map<String, dynamic> chat(String id, {int count = 1}) => {
          'chat_id': id,
          'message_count': count,
          'participants': ['u1', 'u2'],
        };

    test('server return SUBSET → item lama tetap ada (tidak terpangkas)',
        () async {
      // fetch awal: 3 chat.
      when(() => service.listChats(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => {
            'items': [chat('a'), chat('b'), chat('c')],
            'total': 3,
          });
      await provider.fetchChats();
      expect(provider.chats.length, 3);

      // poll berikutnya server cuma balikin 1 (race/filter) — dulu list
      // terpangkas jadi 1 → "ilang", lalu muncul lagi saat scroll.
      when(() => service.listChats(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => {
            'items': [chat('a')],
            'total': 3,
          });
      await provider.refreshChats();

      expect(provider.chats.length, 3);
      expect(provider.chats.map((c) => c['chat_id']), containsAll(['a', 'b', 'c']));
    });

    test('chat baru dari server ditambahkan di depan tanpa duplikat', () async {
      when(() => service.listChats(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => {
            'items': [chat('a'), chat('b')],
            'total': 3,
          });
      await provider.fetchChats();

      when(() => service.listChats(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => {
            'items': [chat('new'), chat('a'), chat('b')],
            'total': 3,
          });
      await provider.refreshChats();

      expect(provider.chats.length, 3);
      expect(provider.chats.first['chat_id'], 'new');
      // tidak ada id ganda.
      final ids = provider.chats.map((c) => c['chat_id']).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('konten item yang berubah di-update in-place (posisi tetap)', () async {
      when(() => service.listChats(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => {
            'items': [chat('a', count: 1), chat('b', count: 5)],
            'total': 2,
          });
      await provider.fetchChats();

      when(() => service.listChats(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => {
            'items': [chat('a', count: 9), chat('b', count: 5)],
            'total': 2,
          });
      await provider.refreshChats();

      expect(provider.chats.length, 2);
      expect(provider.chats.first['chat_id'], 'a');
      expect(provider.chats.first['message_count'], 9);
    });

    test('limit refresh = kedalaman yang sudah dimuat (> chatPageSize)',
        () async {
      final many = List.generate(60, (i) => chat('c$i'));
      when(() => service.listChats(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => {'items': many, 'total': 60});
      await provider.fetchChats();
      expect(provider.chats.length, 60);

      await provider.refreshChats();

      // Kedalaman 60 dipertahankan (bukan dipangkas ke 50).
      verify(() => service.listChats(limit: 60, offset: 0)).called(1);
    });
  });

  group('fetchStats', () {
    test('sukses → stats terisi, loading mati, pointsEnabled dari server',
        () async {
      when(() => service.getStats()).thenAnswer(
        (_) async => {'points_enabled': true, 'users': 5},
      );
      await provider.fetchStats();
      expect(provider.stats?['users'], 5);
      expect(provider.loading, isFalse);
      expect(provider.pointsEnabled, isTrue);
      expect(provider.error, isNull);
    });

    test('force=true → panggil getStatsForce (bukan getStats)', () async {
      when(() => service.getStatsForce())
          .thenAnswer((_) async => {'points_enabled': false});
      await provider.fetchStats(force: true);
      verify(() => service.getStatsForce()).called(1);
      verifyNever(() => service.getStats());
      expect(provider.pointsEnabled, isFalse);
    });

    test('error → error terisi, loading tetap mati', () async {
      when(() => service.getStats()).thenThrow(Exception('boom'));
      await provider.fetchStats();
      expect(provider.error, isNotNull);
      expect(provider.loading, isFalse);
    });
  });

  group('fetchStatsDetail (cache 60 detik)', () {
    test('panggilan kedua dalam TTL → tidak fetch ulang', () async {
      when(() => service.getStatsDetail())
          .thenAnswer((_) async => {'x': 1});
      await provider.fetchStatsDetail();
      await provider.fetchStatsDetail();
      verify(() => service.getStatsDetail()).called(1);
    });

    test('force=true → fetch ulang meski cache hangat', () async {
      when(() => service.getStatsDetail())
          .thenAnswer((_) async => {'x': 1});
      await provider.fetchStatsDetail();
      await provider.fetchStatsDetail(force: true);
      verify(() => service.getStatsDetail()).called(2);
    });

    test('invalidateStatsDetail → panggilan berikutnya fetch lagi', () async {
      when(() => service.getStatsDetail())
          .thenAnswer((_) async => {'x': 1});
      await provider.fetchStatsDetail();
      provider.invalidateStatsDetail();
      await provider.fetchStatsDetail();
      verify(() => service.getStatsDetail()).called(2);
    });

    test('error → {} (bukan throw)', () async {
      when(() => service.getStatsDetail()).thenThrow(Exception('x'));
      expect(await provider.fetchStatsDetail(), isEmpty);
    });
  });

  group('hidden uids', () {
    test('fetchHiddenUids mengisi set + isHiddenUid benar', () async {
      when(() => service.fetchHiddenUids())
          .thenAnswer((_) async => {'a', 'b'});
      await provider.fetchHiddenUids();
      expect(provider.isHiddenUid('a'), isTrue);
      expect(provider.isHiddenUid('z'), isFalse);
    });

    test('isHiddenUid id kosong → selalu false', () {
      expect(provider.isHiddenUid(''), isFalse);
    });

    test('error → set dibiarkan (tidak crash)', () async {
      when(() => service.fetchHiddenUids()).thenThrow(Exception('x'));
      await provider.fetchHiddenUids();
      expect(provider.hiddenUids, isEmpty);
    });
  });

  group('fetchRegistrationsDaily', () {
    test('sukses → regDaily terisi, regLoading mati', () async {
      when(() => service.fetchRegistrationsDaily(any(), any()))
          .thenAnswer((_) async => {1: 3, 2: 5});
      await provider.fetchRegistrationsDaily(2020, 1);
      expect(provider.regDaily, {1: 3, 2: 5});
      expect(provider.regLoading, isFalse);
    });

    test('bulan lampau → cache permanen (fetch sekali)', () async {
      when(() => service.fetchRegistrationsDaily(any(), any()))
          .thenAnswer((_) async => {1: 1});
      await provider.fetchRegistrationsDaily(2020, 1);
      await provider.fetchRegistrationsDaily(2020, 1);
      verify(() => service.fetchRegistrationsDaily(2020, 1)).called(1);
    });

    test('error → regDaily dikosongkan', () async {
      when(() => service.fetchRegistrationsDaily(any(), any()))
          .thenThrow(Exception('x'));
      await provider.fetchRegistrationsDaily(2020, 1);
      expect(provider.regDaily, isEmpty);
      expect(provider.regLoading, isFalse);
    });
  });

  group('aksi poin', () {
    test('massBonus sukses → refresh stats & kembalikan hasil', () async {
      when(() => service.massBonus(any()))
          .thenAnswer((_) async => {'ok': true});
      when(() => service.getStats()).thenAnswer((_) async => {});
      final out = await provider.massBonus(50);
      expect(out?['ok'], true);
      verify(() => service.getStats()).called(1);
    });

    test('massBonus error → null', () async {
      when(() => service.massBonus(any())).thenThrow(Exception('x'));
      expect(await provider.massBonus(50), isNull);
    });

    test('resetAllPoints sukses → refresh stats + kembalikan count', () async {
      when(() => service.resetAllPoints()).thenAnswer((_) async => 42);
      when(() => service.getStats()).thenAnswer((_) async => {});
      expect(await provider.resetAllPoints(), 42);
    });

    test('togglePointsSystem mengubah _pointsEnabled', () async {
      when(() => service.togglePointsSystem(any()))
          .thenAnswer((_) async => true);
      expect(await provider.togglePointsSystem(true), isTrue);
      expect(provider.pointsEnabled, isTrue);
    });

    test('togglePointsSystem error → false', () async {
      when(() => service.togglePointsSystem(any())).thenThrow(Exception('x'));
      expect(await provider.togglePointsSystem(true), isFalse);
    });

    test('forceLogout sukses → delegasi; error → rethrow', () async {
      when(() => service.forceLogout(any())).thenAnswer((_) async {});
      await provider.forceLogout('u1');
      verify(() => service.forceLogout('u1')).called(1);

      when(() => service.forceLogout('u2')).thenThrow(Exception('x'));
      expect(() => provider.forceLogout('u2'), throwsA(isA<Exception>()));
    });
  });

  group('breakdown tabel', () {
    test('fetchTableSizes mengisi tableSizes + loading mati', () async {
      when(() => service.getTableSizes()).thenAnswer(
        (_) async => {
          'tables': [
            {'table': 'ai_reply_log', 'total_bytes': 1},
          ],
        },
      );
      await provider.fetchTableSizes();
      expect(provider.tableSizes.length, 1);
      expect(provider.tableSizesLoading, isFalse);
    });

    test('fetchTableSizes error → list tetap + loading mati', () async {
      when(() => service.getTableSizes()).thenThrow(Exception('x'));
      await provider.fetchTableSizes();
      expect(provider.tableSizes, isEmpty);
      expect(provider.tableSizesLoading, isFalse);
    });
  });
}
