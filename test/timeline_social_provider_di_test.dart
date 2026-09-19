import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/social_provider.dart';
import 'package:chatyuk/providers/timeline_provider.dart';
import 'package:chatyuk/services/social_service.dart';
import 'package:chatyuk/services/timeline_service.dart';

import 'supabase_test_client.dart';

/// Bukti DI provider Grup C: `SocialProvider` & `TimelineProvider` menerima
/// service/client dari luar. Dengan `autoInit: false`, konstruksi tidak
/// menyentuh network sama sekali (aman tanpa Supabase.initialize).
class MockSocialService extends Mock implements SocialService {}

class MockTimelineService extends Mock implements TimelineService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SocialProvider DI', () {
    test('menerima service suntikan + autoInit:false tidak menyentuh network',
        () {
      final service = MockSocialService();
      final provider = SocialProvider(
        service: service,
        sb: fakeSupabaseClient(),
        autoInit: false,
      );
      expect(provider, isNotNull);
      provider.dispose();
    });
  });

  group('TimelineProvider DI', () {
    test('menerima service suntikan + autoInit:false tidak menyentuh network',
        () {
      final service = MockTimelineService();
      final provider = TimelineProvider(
        service: service,
        sb: fakeSupabaseClient(),
        autoInit: false,
      );
      expect(provider, isNotNull);
      provider.dispose();
    });

    test('delegasi ke service yang disuntik (createPost)', () async {
      final service = MockTimelineService();
      when(() => service.createPost(
            text: any(named: 'text'),
            imagePaths: any(named: 'imagePaths'),
            visibility: any(named: 'visibility'),
          )).thenAnswer((_) async => {'ok': true});

      final provider = TimelineProvider(
        service: service,
        sb: fakeSupabaseClient(),
        autoInit: false,
      );

      final res = await provider.createPost(text: 'halo');
      expect(res['ok'], isTrue);
      verify(() => service.createPost(
            text: 'halo',
            imagePaths: const [],
            visibility: 'public',
          )).called(1);
      provider.dispose();
    });
  });
}
