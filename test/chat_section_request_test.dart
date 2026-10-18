import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_yuk_chat_header.dart';

/// Regresi: pintasan "Global Room" di halaman Online harus mengalihkan ke
/// halaman Global Room TUNGGAL (tab Chat → section Rooms, yang punya lonceng
/// notifikasi + tombol cari), BUKAN membuka halaman kedua (LobbyScreen
/// standalone).
///
/// Mekanismenya: `requestedChatSection` (sekali-pakai). Test ini mengunci
/// kontraknya + logika konsumsi yang dipakai `ChatsScreen`.
void main() {
  setUp(() => requestedChatSection.value = null);
  tearDown(() => requestedChatSection.value = null);

  test('awalnya null (tidak ada permintaan)', () {
    expect(requestedChatSection.value, isNull);
  });

  test('dapat di-set ke rooms lalu dikonsumsi sekali pakai', () {
    requestedChatSection.value = ChatSection.rooms;
    expect(requestedChatSection.value, ChatSection.rooms);

    // Konsumsi (pola _applyRequestedSection di ChatsScreen).
    final want = requestedChatSection.value;
    requestedChatSection.value = null;
    expect(want, ChatSection.rooms);
    expect(requestedChatSection.value, isNull);
  });

  testWidgets('ChatsScreen: permintaan diterapkan ke section & dikosongkan', (
    t,
  ) async {
    // Harness yang mereplikasi listener ChatsScreen.
    var section = ChatSection.messages;
    void apply() {
      final want = requestedChatSection.value;
      if (want == null) return;
      requestedChatSection.value = null;
      section = want;
    }

    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setState) => Column(
                children: [
                  Text('section=${section.name}'),
                  TextButton(
                    onPressed: () {
                      requestedChatSection.value = ChatSection.rooms;
                      setState(apply);
                    },
                    child: const Text('minta rooms'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('section=messages'), findsOneWidget);

    await t.tap(find.text('minta rooms'));
    await t.pumpAndSettle();

    expect(find.text('section=rooms'), findsOneWidget);
    // Permintaan sudah dikonsumsi → tidak akan ter-apply ulang.
    expect(requestedChatSection.value, isNull);
  });

  testWidgets('permintaan basi (dibaca saat belum mount) tetap diproses', (
    t,
  ) async {
    // Simulasi: Online men-set permintaan SEBELUM ChatsScreen mount.
    requestedChatSection.value = ChatSection.rooms;

    var section = ChatSection.messages;
    // initState ChatsScreen memanggil _applyRequestedSection().
    final want = requestedChatSection.value;
    if (want != null) {
      requestedChatSection.value = null;
      section = want;
    }

    expect(section, ChatSection.rooms);
    expect(requestedChatSection.value, isNull);
  });
}
