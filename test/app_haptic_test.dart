import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/app_gesture.dart';

/// Getar (haptic) ala WhatsApp pada tap/long-press — kunci kontrak:
///   * tap  → AppHaptic.tap() = HapticFeedback.lightImpact
///   * tahan → AppHaptic.medium() = HapticFeedback.mediumImpact
///   * haptic:false → TIDAK ada getar (kontrol internal)
///
/// Verifikasi via MethodChannel `flutter/platform` (HapticFeedback meneruskan
/// `HapticFeedback.vibrate` ke channel itu).
void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add('${call.arguments}');
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('tap → getar lightImpact', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        AppGestureDetector(
          onTap: () => tapped = true,
          child: const SizedBox(width: 100, height: 100, child: Text('x')),
        ),
      ),
    );
    await tester.tap(find.byType(AppGestureDetector));
    await tester.pump();
    expect(tapped, isTrue);
    expect(calls.any((c) => c.contains('lightImpact')), isTrue,
        reason: 'tap harus memicu getar ringan');
  });

  testWidgets('haptic:false → TIDAK getar', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        AppGestureDetector(
          haptic: false,
          onTap: () => tapped = true,
          child: const SizedBox(width: 100, height: 100, child: Text('x')),
        ),
      ),
    );
    await tester.tap(find.byType(AppGestureDetector));
    await tester.pump();
    expect(tapped, isTrue);
    expect(calls, isEmpty, reason: 'haptic:false tidak boleh getar');
  });

  testWidgets('tahan lama → getar mediumImpact', (tester) async {
    var held = false;
    await tester.pumpWidget(
      wrap(
        AppGestureDetector(
          onLongPress: () => held = true,
          longPressDuration: const Duration(milliseconds: 100),
          child: const SizedBox(width: 100, height: 100, child: Text('x')),
        ),
      ),
    );
    await tester.longPress(find.byType(AppGestureDetector));
    await tester.pump();
    expect(held, isTrue);
    expect(calls.any((c) => c.contains('mediumImpact')), isTrue,
        reason: 'tahan lama harus getar lebih tegas');
  });
}
