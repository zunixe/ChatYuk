import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chatyuk/providers/riverpod/call_provider.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });



  group('state call aktif (murni, tanpa realtime)', () {
    test('register → inCall true; unregister id cocok → false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final p = container.read(callProvider.notifier);
      expect(p.inCall, isFalse);
      p.registerCall('c1');
      expect(p.inCall, isTrue);
      expect(p.activeCallId, 'c1');
      // Unregister id lain tidak boleh menutup call aktif.
      p.unregisterCall('c2');
      expect(p.inCall, isTrue);
      p.unregisterCall('c1');
      expect(p.inCall, isFalse);
    });

    test('setMode notify sekali, sama = no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final p = container.read(callProvider.notifier);
      var notified = 0;
      final sub = container.listen(callProvider, (prev, next) => notified++);
      p.setMode(CallMode.fullscreen);
      expect(notified, 1);
      p.setMode(CallMode.fullscreen);
      expect(notified, 1);
      sub.close();
    });
  });
}
