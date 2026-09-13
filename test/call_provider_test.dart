import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/providers/call_provider.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });

  tearDown(() {
    // Singleton dipakai lintas test dalam satu run — kembalikan bersih.
    final p = CallProvider.instance;
    if (p.activeCallId != null) p.unregisterCall(p.activeCallId!);
  });

  group('state call aktif (murni, tanpa realtime)', () {
    test('register → inCall true; unregister id cocok → false', () {
      final p = CallProvider.instance;
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
      final p = CallProvider.instance;
      var notified = 0;
      void listener() => notified++;
      p.addListener(listener);
      p.setMode(CallMode.fullscreen);
      expect(notified, 1);
      p.setMode(CallMode.fullscreen);
      expect(notified, 1);
      p.removeListener(listener);
    });
  });
}
