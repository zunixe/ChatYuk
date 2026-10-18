import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ekspektasi navigasi pintasan Global Room dari halaman Online.
///
/// Alur yang diinginkan: Online → (ikon Global Room) → **halaman Global Room**
/// → Chat Room, dan BACK dari Chat Room kembali ke halaman Global Room itu
/// (bukan langsung ke Online).
///
/// CATATAN PENTING (2026-10-18): "halaman Global Room" itu SEKARANG = tab Chat
/// section **Rooms** di dalam `ChatsScreen` (punya lonceng + cari) — BUKAN
/// halaman `LobbyScreen` terpisah. Pintasan Online mengalihkan tab + section
/// lewat `requestedChatSection` (diuji di `chat_section_request_test.dart`).
///
/// Test DI SINI memakai harness sendiri untuk mengunci URUTAN back
/// (room → halaman room list → Online); ia tidak menjalankan layar asli
/// (butuh Supabase). Jadi ia dokumentasi perilaku, bukan uji integrasi.
void main() {
  testWidgets('back dari chat room kembali ke menu Global Room', (t) async {
    await t.pumpWidget(const MaterialApp(home: _OnlinePage()));

    // Online → Menu Global Room (push biasa).
    await t.tap(find.text('GLOBAL ROOM'));
    await t.pumpAndSettle();
    expect(find.text('MENU GLOBAL ROOM'), findsOneWidget);

    // Menu Global Room → Chat Room (push biasa, menu tetap di tumpukan).
    await t.tap(find.text('MASUK ROOM'));
    await t.pumpAndSettle();
    expect(find.text('ROOM'), findsOneWidget);

    // BACK → kembali ke MENU GLOBAL ROOM (bukan Online).
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('MENU GLOBAL ROOM'), findsOneWidget);
    expect(find.text('ONLINE'), findsNothing);
  });

  testWidgets('back kedua dari menu Global Room → kembali ke Online', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: _OnlinePage()));

    await t.tap(find.text('GLOBAL ROOM'));
    await t.pumpAndSettle();
    await t.tap(find.text('MASUK ROOM'));
    await t.pumpAndSettle();

    await t.pageBack(); // room → menu global room
    await t.pumpAndSettle();
    expect(find.text('MENU GLOBAL ROOM'), findsOneWidget);

    await t.pageBack(); // menu global room → online
    await t.pumpAndSettle();
    expect(find.text('ONLINE'), findsOneWidget);
  });
}

class _OnlinePage extends StatelessWidget {
  const _OnlinePage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ONLINE')),
    body: Center(
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const _LobbyPage()),
        ),
        child: const Text('GLOBAL ROOM'),
      ),
    ),
  );
}

class _LobbyPage extends StatelessWidget {
  const _LobbyPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MENU GLOBAL ROOM')),
    body: Center(
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const _RoomPage()),
        ),
        child: const Text('MASUK ROOM'),
      ),
    ),
  );
}

class _RoomPage extends StatelessWidget {
  const _RoomPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ROOM')),
    body: const Center(child: Text('isi room')),
  );
}
