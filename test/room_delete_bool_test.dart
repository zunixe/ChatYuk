import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/chat_provider.dart';
import 'package:chatyuk/services/chat_service.dart';

class MockChatService extends Mock implements ChatService {}

/// Kontrak hapus pesan room & private: `bool` merambat dari service.
/// Regresi: `.select('id')` + 0-rows (blokir RLS) → false, bukan sukses palsu.
void main() {
  late MockChatService service;
  late ChatProvider provider;

  setUp(() {
    service = MockChatService();
    provider = ChatProvider(service: service);
  });

  tearDown(() => provider.dispose());

  group('deleteRoomMessage bool', () {
    test('sukses → true', () async {
      when(() => service.deleteRoomMessage(any())).thenAnswer((_) async => true);
      expect(await provider.deleteRoomMessage('m1'), isTrue);
      verify(() => service.deleteRoomMessage('m1')).called(1);
    });

    test('0-rows / error → false', () async {
      when(() => service.deleteRoomMessage(any())).thenAnswer((_) async => false);
      expect(await provider.deleteRoomMessage('m2'), isFalse);
    });
  });

  group('deletePrivateMessage bool', () {
    test('sukses → true', () async {
      when(() => service.deletePrivateMessage(any()))
          .thenAnswer((_) async => true);
      expect(await provider.deletePrivateMessage('m1'), isTrue);
    });

    test('gagal → false', () async {
      when(() => service.deletePrivateMessage(any()))
          .thenAnswer((_) async => false);
      expect(await provider.deletePrivateMessage('m2'), isFalse);
    });
  });
}
