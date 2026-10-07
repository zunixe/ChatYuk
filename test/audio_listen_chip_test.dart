import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/strings_admin.dart';
import 'package:chatyuk/models/active_call_model.dart';
import 'package:chatyuk/screens/admin_chat/widgets/audio_listen_chip.dart';
import 'package:chatyuk/services/admin_call_watch_service.dart';

import 'test_helper.dart';

/// Mengunci chip monitor admin [AudioListenChip]:
/// - ringing → header "Memanggil…" + per peserta bedakan arah
///   (caller "Menelepon", callee "Berdering").
/// - answered + tersambung → header "Mendengarkan…".
/// - answered tapi belum tersambung → header "Menyambungkan…" (bukan
///   "Mendengarkan…" palsu).
///
/// Fokus `build`/`_participantStatus` saja (tanpa `start()` WebRTC).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  final s = S(isId: true);

  ActiveCallInfo call({String status = 'ringing'}) => ActiveCallInfo(
        id: 'call-1',
        chatId: 'chat-1',
        callerId: 'u-caller',
        calleeId: 'u-callee',
        callerName: 'Penelepon',
        calleeName: 'Penerima',
        callType: 'audio',
        status: status,
        createdAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );

  Future<void> pumpChip(WidgetTester tester, WatchSession session) async {
    await tester.pumpWidget(
       ProviderScope(child: MaterialApp(
          home: Scaffold(body: AudioListenChip(session: session)),
        )),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('ringing → header Memanggil + arah per peserta', (tester) async {
    final session = WatchSession(call(status: 'ringing'));
    await pumpChip(tester, session);

    expect(find.text(s.adminCallRinging), findsOneWidget);
    // Caller menelepon, callee berdering.
    expect(find.textContaining(s.adminCallerCalling), findsOneWidget);
    expect(find.textContaining(s.adminCalleeRinging), findsOneWidget);
    expect(find.text(s.adminListening), findsNothing);

    session.dispose();
    await tester.pump();
  });

  testWidgets('answered tapi belum tersambung → header Menyambungkan',
      (tester) async {
    final session = WatchSession(call(status: 'answered'));
    await pumpChip(tester, session);

    expect(find.text(s.adminWatchConnecting), findsWidgets);
    expect(find.text(s.adminListening), findsNothing);

    session.dispose();
    await tester.pump();
  });

  testWidgets('answered + tersambung → header Mendengarkan', (tester) async {
    final session = WatchSession(call(status: 'answered'));
    for (final p in session.participants) {
      p.connected = true;
      p.micOn = true;
    }
    await pumpChip(tester, session);

    expect(find.text(s.adminListening), findsWidgets);

    session.dispose();
    await tester.pump();
  });
}
