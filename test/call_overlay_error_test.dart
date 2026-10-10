import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/call/call_session.dart';
import 'package:chatyuk/core/call/call_permissions.dart';
import 'package:chatyuk/widgets/chat_call_overlay.dart';

import 'test_helper.dart';

/// Regresi: dulu `chat_call_overlay._statusText` TIDAK punya case
/// `CallPhase.error` → overlay menampilkan status KOSONG saat video call
/// gagal, jadi user melihat "gagal" tanpa penjelasan & tanpa jalan pulih.
void main() {
  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  Future<void> pumpOverlay(WidgetTester tester, CallSession session) async {
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        home:  Scaffold(
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
      )),
    );
    await tester.pumpAndSettle();
  }

  /// Drain animasi `AnimatedPositioned` (220ms) yang menyisakan timer —
  /// pola sama dengan `call_overlay_test.dart`.
  Future<void> drainAnimations(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  testWidgets('overlay tampilkan pesan error saat CallPhase.error',
      (tester) async {
    final session = CallSession(
      callId: 'c1',
      remoteUid: 'u1',
      remoteName: 'Budi',
      callType: 'video',
      isCaller: true,
    );
    await pumpOverlay(tester, session);
    session.debugSetPhase(CallPhase.error, mediaError: CallMediaError.permission);
    await tester.pumpAndSettle();
    await drainAnimations(tester);

    // Pesan izin (bukan status kosong) harus tampil.
    expect(find.text('Izin kamera & mikrofon diperlukan untuk panggilan'),
        findsOneWidget);
    // Tombol sambung ulang muncul sebagai jalan pulih.
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await drainAnimations(tester);
  });

  testWidgets('overlay tampilkan pesan kamera terpakai app lain',
      (tester) async {
    final session = CallSession(
      callId: 'c2',
      remoteUid: 'u2',
      remoteName: 'Ani',
      callType: 'video',
      isCaller: true,
    );
    await pumpOverlay(tester, session);
    session.debugSetPhase(CallPhase.error, mediaError: CallMediaError.inUse);
    await tester.pumpAndSettle();
    await drainAnimations(tester);

    expect(find.text('Kamera/mikrofon sedang dipakai aplikasi lain'),
        findsOneWidget);
    await drainAnimations(tester);
  });
}

void _noop() {}
