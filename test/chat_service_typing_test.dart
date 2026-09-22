import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/services/chat_service.dart';

/// Fase 3 — ChatService typing mixin (logic-only).
/// `sendTyping` tanpa user login harus no-op total: tidak buat realtime
/// channel, tidak ping RPC. Ini mencegah channel "buta" tanpa handler.
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  test('sendTyping tanpa user login → no-op (tanpa channel/rpc)', () {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(null);

    final svc = ChatService(client);
    expect(() => svc.sendTyping('c1'), returnsNormally);
    verifyNever(() => client.rpc(any(), params: any(named: 'params')));
    verifyNever(() => client.channel(any()));
  });

  test('sendTyping uid kosong / berbeda tetap tidak menyentuh channel', () {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(null);

    final svc = ChatService(client);
    expect(() => svc.sendTyping('', kind: 'recording'), returnsNormally);
    verifyNever(() => client.channel(any()));
  });
}
