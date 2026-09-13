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

  testWidgets('ChatCallOverlay mounts (connecting)', (tester) async {
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
                Positioned.fill(
                  child: ChatCallOverlay(
                    session: session,
                    onExpand: _noop,
                    onEnd: _noop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  });
}

void _noop() {}
