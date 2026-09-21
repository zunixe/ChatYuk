import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/privacy_settings.dart';
import 'package:chatyuk/providers/privacy_provider.dart';
import 'package:chatyuk/services/privacy_service.dart';

class MockPrivacyService extends Mock implements PrivacyService {}

void main() {
  late MockPrivacyService service;
  late PrivacyProvider provider;

  setUp(() {
    service = MockPrivacyService();
    provider = PrivacyProvider(service: service);
  });

  test('load mengisi settings dari server', () async {
    when(() => service.fetch()).thenAnswer(
      (_) async => const PrivacySettings(
        presence: PrivacyVisibility.friends,
        readReceipts: false,
      ),
    );

    await provider.load();

    expect(provider.settings.presence, PrivacyVisibility.friends);
    expect(provider.settings.readReceipts, isFalse);
    expect(provider.loading, isFalse);
  });

  test('update menerapkan hasil server dan memanggil service', () async {
    when(
      () => service.update(
        presence: PrivacyVisibility.nobody,
        lastSeen: null,
        profilePhoto: null,
        about: null,
        story: null,
        readReceipts: null,
      ),
    ).thenAnswer(
      (_) async => const PrivacySettings(presence: PrivacyVisibility.nobody),
    );

    await provider.update(presence: PrivacyVisibility.nobody);

    expect(provider.settings.presence, PrivacyVisibility.nobody);
    verify(
      () => service.update(
        presence: PrivacyVisibility.nobody,
        lastSeen: null,
        profilePhoto: null,
        about: null,
        story: null,
        readReceipts: null,
      ),
    ).called(1);
  });

  test('update gagal → fallback load ulang (tanpa crash)', () async {
    when(
      () => service.update(
        presence: any(named: 'presence'),
        lastSeen: any(named: 'lastSeen'),
        profilePhoto: any(named: 'profilePhoto'),
        about: any(named: 'about'),
        story: any(named: 'story'),
        readReceipts: any(named: 'readReceipts'),
      ),
    ).thenThrow(Exception('offline'));
    when(() => service.fetch()).thenAnswer(
      (_) async => const PrivacySettings(presence: PrivacyVisibility.everyone),
    );

    await provider.update(presence: PrivacyVisibility.nobody);

    expect(provider.settings.presence, PrivacyVisibility.everyone);
  });

  test('ensureExcludable memuat teman sekali saja (cached)', () async {
    when(() => service.excludableUsers()).thenAnswer(
      (_) async => [
        {'uid': 'u1', 'nickname': 'Budi'},
      ],
    );

    await provider.ensureExcludable();
    await provider.ensureExcludable();

    expect(provider.excludable.length, 1);
    expect(provider.excludable.first['nickname'], 'Budi');
    expect(provider.excludableLoaded, isTrue);
    verify(() => service.excludableUsers()).called(1);
  });

  test('ensureExcludable gagal → daftar tetap kosong tanpa crash', () async {
    when(() => service.excludableUsers()).thenThrow(Exception('offline'));

    await provider.ensureExcludable();

    expect(provider.excludable, isEmpty);
    expect(provider.excludableLoading, isFalse);
  });

  test('updateExclusions menyimpan daftar pengecualian', () async {
    when(() => service.replaceExclusions('last_seen', {'u1'})).thenAnswer(
      (_) async => const PrivacySettings(
        lastSeen: PrivacyVisibility.friendsExcept,
        exclusions: {
          'last_seen': {'u1'},
        },
      ),
    );

    await provider.updateExclusions('last_seen', {'u1'});

    expect(provider.settings.exclusions['last_seen'], {'u1'});
    expect(provider.settings.lastSeen, PrivacyVisibility.friendsExcept);
  });
}
