import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/services/call_service.dart';
import 'package:chatyuk/widgets/chat_call_overlay.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  testWidgets('tombol expand & end bisa di-tap di dalam Stack', (tester) async {
    var expanded = 0;
    var ended = 0;
    final session = CallSession(
      callId: 'c1',
      remoteUid: 'u1',
      remoteName: 'Budi',
      callType: 'video',
      isCaller: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>.value(
          value: LocaleProvider(),
          child: Scaffold(
            body: Stack(
              children: [
                // Simulasi konten chat di bawah overlay (real screen).
                Positioned.fill(
                  child: ListView(
                    children: List.generate(
                      40,
                      (i) => ListTile(title: Text('pesan $i')),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ChatCallOverlay(
                    session: session,
                    onExpand: () => expanded++,
                    onEnd: () => ended++,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }

    final expandBtn = find.byIcon(Icons.aspect_ratio_rounded);
    final endBtn = find.byIcon(Icons.call_end_rounded);
    await tester.tap(expandBtn, warnIfMissed: true);
    await tester.pump();
    await tester.tap(endBtn, warnIfMissed: true);
    await tester.pump();

    expect(expanded, 1, reason: 'tombol expand harus terpanggil');
    expect(ended, 1, reason: 'tombol end harus terpanggil');
  });
}
