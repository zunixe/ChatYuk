import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

/// ChatService typing mixin (logic-only).
/// `sendTyping` tanpa user login harus no-op total: tidak buat realtime
/// channel, tidak ping RPC. Ini mencegah channel "buta" tanpa handler.
/// Pola baru: `SupabaseClient` asli + HTTP palsu (tanpa mocktail) —
/// tanpa sesi, `currentUser` null → early-return sebelum channel/RPC.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  test('sendTyping tanpa user login → no-op (tanpa channel/rpc)', () {
    final handler = FakeSupabaseHandler();
    final svc = ChatService(fakeSupabaseClient(handler: handler));
    expect(() => svc.sendTyping('c1'), returnsNormally);
    expect(handler.captured, isEmpty,
        reason: 'tanpa login tidak boleh ada RPC/HTTP');
  });

  test('sendTyping uid kosong / berbeda tetap tidak menyentuh channel', () {
    final handler = FakeSupabaseHandler();
    final svc = ChatService(fakeSupabaseClient(handler: handler));
    expect(() => svc.sendTyping('', kind: 'recording'), returnsNormally);
    expect(handler.captured, isEmpty);
  });
}
