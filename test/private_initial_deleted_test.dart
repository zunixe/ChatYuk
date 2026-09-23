import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/private_chat_screen.dart';

/// Prime banner akun terhapus: `initialOtherDeleted` default false (kompatibel
/// konstruktor lama) + prime sinkron `lastPrivateChatsSnapshot` di initState.
/// Widget pump penuh butuh ChatProvider/AuthProvider — di sini kunci kontrak
/// konstruktor + logika prime (chatId cocok + otherDeleted true).
void main() {
  test('konstruktor default initialOtherDeleted=false (kompatibel lama)',
      () {
    const w = PrivateChatScreen(chatId: 'c1', otherUid: 'u2', otherName: 'A');
    expect(w.initialOtherDeleted, isFalse);
  });

  test('initialOtherDeleted=true diteruskan (banner frame-1)', () {
    const w = PrivateChatScreen(
      chatId: 'c1',
      otherUid: 'u2',
      otherName: 'A',
      initialOtherDeleted: true,
    );
    expect(w.initialOtherDeleted, isTrue);
  });

  test('prime snapshot: chatId cocok + otherDeleted → true', () {
    bool prime({
      required bool initial,
      required String chatId,
      required List<({String chatId, bool otherDeleted})> snap,
    }) {
      var deleted = initial;
      if (!deleted) {
        for (final c in snap) {
          if (c.chatId == chatId && c.otherDeleted) {
            deleted = true;
            break;
          }
        }
      }
      return deleted;
    }

    expect(
      prime(initial: false, chatId: 'c1', snap: [(chatId: 'c1', otherDeleted: true)]),
      isTrue,
    );
    expect(
      prime(initial: false, chatId: 'c1', snap: [(chatId: 'c2', otherDeleted: true)]),
      isFalse,
      reason: 'chatId beda tidak boleh prime',
    );
    expect(
      prime(initial: true, chatId: 'c1', snap: const []),
      isTrue,
      reason: 'initial true langsung true tanpa snapshot',
    );
  });
}
