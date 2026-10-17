import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresi navigasi pintasan Global Room dari halaman Online.
///
/// Alur: Online → (kapsul Global Room) → Lobby (daftar room) → Chat Room.
/// Back dari Chat Room harus kembali ke **Online**, bukan ke daftar room.
///
/// Caranya: saat Lobby dibuka sebagai perpanjangan Online, memilih room
/// memakai `pushReplacement` sehingga Lobby keluar dari tumpukan.
void main() {
  testWidgets('replaceOnOpenRoom: back dari room kembali ke Online', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(home: _OnlinePage()),
    );

    // Online → Lobby (push biasa, Online tetap di tumpukan).
    await t.tap(find.text('GLOBAL ROOM'));
    await t.pumpAndSettle();
    expect(find.text('LOBBY'), findsOneWidget);

    // Lobby → Room dengan REPLACE (Lobby dibuang dari tumpukan).
    await t.tap(find.text('MASUK ROOM'));
    await t.pumpAndSettle();
    expect(find.text('ROOM'), findsOneWidget);

    // BACK → harus ke Online, bukan ke Lobby.
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('LOBBY'), findsNothing);
  });

  testWidgets('tanpa replace: back dari room kembali ke Lobby (perilaku lama)', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: _OnlinePage()));

    await t.tap(find.text('GLOBAL ROOM'));
    await t.pumpAndSettle();

    await t.tap(find.text('MASUK ROOM (TANPA REPLACE)'));
    await t.pumpAndSettle();
    expect(find.text('ROOM'), findsOneWidget);

    await t.pageBack();
    await t.pumpAndSettle();
    // Tumpukan masih menyimpan Lobby → kembali ke Lobby (bug yang dilaporkan).
    expect(find.text('LOBBY'), findsOneWidget);
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
          MaterialPageRoute<void>(
            builder: (_) => const _LobbyPage(replaceOnOpenRoom: true),
          ),
        ),
        child: const Text('GLOBAL ROOM'),
      ),
    ),
  );
}

class _LobbyPage extends StatelessWidget {
  final bool replaceOnOpenRoom;
  const _LobbyPage({required this.replaceOnOpenRoom});

  void _openRoom(BuildContext context) {
    final route = MaterialPageRoute<void>(builder: (_) => const _RoomPage());
    final nav = Navigator.of(context);
    if (replaceOnOpenRoom) {
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LOBBY')),
    body: Column(
      children: [
        ElevatedButton(
          onPressed: () => _openRoom(context),
          child: const Text('MASUK ROOM'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _RoomPage()),
          ),
          child: const Text('MASUK ROOM (TANPA REPLACE)'),
        ),
      ],
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
