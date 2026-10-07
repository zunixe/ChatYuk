import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/riverpod/social_provider.dart';
import 'package:chatyuk/providers/riverpod/timeline_provider.dart';
import 'package:chatyuk/services/social_service.dart';
import 'package:chatyuk/services/timeline_service.dart';

import 'supabase_test_client.dart';

/// Bukti DI provider Grup C: `SocialNotifier` & `TimelineNotifier` menerima
/// service/client dari luar. Dengan `autoInit: false`, konstruksi tidak
/// menyentuh network sama sekali (aman tanpa Supabase.initialize).
class MockSocialService extends Mock implements SocialService {}

class MockTimelineService extends Mock implements TimelineService {}

class _TestSocial extends SocialNotifier {
  _TestSocial(SocialService svc)
      : super(service: svc, sb: fakeSupabaseClient());
  @override
  SocialState build() => const SocialState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SocialNotifier DI', () {
    test('menerima service suntikan + tidak menyentuh network', () {
      final container = ProviderContainer(
        overrides: [
          socialProvider.overrideWith(() => _TestSocial(MockSocialService())),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(socialProvider.notifier), isNotNull);
    });
  });

  group('TimelineNotifier DI', () {
    test('menerima service suntikan + autoInit:false tidak menyentuh network',
        () {
      final service = MockTimelineService();
      final container = ProviderContainer(
        overrides: [
          timelineProvider.overrideWith(
            () => TimelineNotifier(
              service: service,
              sb: fakeSupabaseClient(),
              autoInit: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(timelineProvider.notifier), isNotNull);
    });

    test('delegasi ke service yang disuntik (createPost)', () async {
      final service = MockTimelineService();
      when(() => service.createPost(
            text: any(named: 'text'),
            imagePaths: any(named: 'imagePaths'),
            visibility: any(named: 'visibility'),
          )).thenAnswer((_) async => {'ok': true});

      final container = ProviderContainer(
        overrides: [
          timelineProvider.overrideWith(
            () => TimelineNotifier(
              service: service,
              sb: fakeSupabaseClient(),
              autoInit: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final res = await container
          .read(timelineProvider.notifier)
          .createPost(text: 'halo');
      expect(res['ok'], isTrue);
      verify(() => service.createPost(
            text: 'halo',
            imagePaths: const [],
            visibility: 'public',
          )).called(1);
    });
  });
}
