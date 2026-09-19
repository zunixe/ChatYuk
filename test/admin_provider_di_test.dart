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
}
