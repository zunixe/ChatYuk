import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_service.dart';

import 'supabase_test_client.dart';

/// Bukti DI `ChatBase`: `ChatService` menerima client Supabase dari luar,
/// sehingga bisa dibangun tanpa `Supabase.instance` dan dipakai dengan
/// client palsu.
void main() {
  group('ChatBase DI', () {
    test('ChatService(client palsu) bisa dibangun tanpa Supabase.instance',
        () {
      final svc = ChatService(fakeSupabaseClient());
      expect(svc, isNotNull);
    });

    test('ChatService() tanpa argumen tetap bisa dibangun (lazy client)', () {
      // Tidak menyentuh Supabase.instance sampai benar-benar dipakai.
      expect(ChatService(), isNotNull);
    });

    test('privateChatId deterministik (murni, tanpa I/O)', () {
      final svc = ChatService(fakeSupabaseClient());
      final a = svc.privateChatId('uid-b', 'uid-a');
      final b = svc.privateChatId('uid-a', 'uid-b');
      expect(a, b);
      expect(a, 'uid-a_uid-b');
    });

    test('privateChatId urutan sama walau uid dibalik', () {
      final svc = ChatService(fakeSupabaseClient());
      expect(svc.privateChatId('zzz', 'aaa'), svc.privateChatId('aaa', 'zzz'));
    });
  });
}
