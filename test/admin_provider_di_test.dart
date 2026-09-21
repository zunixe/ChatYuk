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
}
