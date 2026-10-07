import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/privacy_settings.dart';
import 'package:chatyuk/providers/riverpod/privacy_provider.dart';
import 'package:chatyuk/services/privacy_service.dart';

class MockPrivacyService extends Mock implements PrivacyService {}

class _TestPrivacy extends PrivacyNotifier {
  _TestPrivacy(PrivacyService svc) : super(svc);
}

void main() {
  late MockPrivacyService service;
  late ProviderContainer container;

  setUp(() {
    service = MockPrivacyService();
    container = ProviderContainer(
      overrides: [privacyProvider.overrideWith(() => _TestPrivacy(service))],
    );
    addTearDown(container.dispose);
  });

  PrivacyState state() => container.read(privacyProvider);
  PrivacyNotifier notifier() => container.read(privacyProvider.notifier);

  test('load mengisi settings dari server', () async {
    when(() => service.fetch()).thenAnswer(
      (_) async => const PrivacySettings(
        presence: PrivacyVisibility.friends,
        readReceipts: false,
      ),
    );

    await notifier().load();

    expect(state().settings.presence, PrivacyVisibility.friends);
    expect(state().settings.readReceipts, isFalse);
    expect(state().loading, isFalse);
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

    await notifier().update(presence: PrivacyVisibility.nobody);

    expect(state().settings.presence, PrivacyVisibility.nobody);
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

    await notifier().update(presence: PrivacyVisibility.nobody);

    expect(state().settings.presence, PrivacyVisibility.everyone);
  });

  test('ensureExcludable memuat teman sekali saja (cached)', () async {
    when(() => service.excludableUsers()).thenAnswer(
      (_) async => [
        {'uid': 'u1', 'nickname': 'Budi'},
      ],
    );

    await notifier().ensureExcludable();
    await notifier().ensureExcludable();

    expect(state().excludable.length, 1);
    expect(state().excludable.first['nickname'], 'Budi');
    expect(state().excludableLoaded, isTrue);
    verify(() => service.excludableUsers()).called(1);
  });

  test('ensureExcludable gagal → daftar tetap kosong tanpa crash', () async {
    when(() => service.excludableUsers()).thenThrow(Exception('offline'));

    await notifier().ensureExcludable();

    expect(state().excludable, isEmpty);
    expect(state().excludableLoading, isFalse);
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

    await notifier().updateExclusions('last_seen', {'u1'});

    expect(state().settings.exclusions['last_seen'], {'u1'});
    expect(state().settings.lastSeen, PrivacyVisibility.friendsExcept);
  });
}
