import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresi: tombol BACK saat panel lampiran (menu "+") terbuka di chat harus
/// MENUTUP PANEL saja, bukan keluar dari layar chat.
///
/// Widget di bawah mereplikasi pola `PopScope` yang dipakai
/// `private_chat_core.dart` & `room_chat_live.dart`: `canPop` false selama
/// panel terbuka, lalu `onPopInvokedWithResult` menutup panel.
void main() {
  testWidgets('back menutup panel lampiran, layar chat TETAP terbuka', (
    t,
  ) async {
    var panelOpen = false;
    var popped = false;

    Future<void> pumpHarness() => t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _FakeChatScreen(
                      onState: (open) => panelOpen = open,
                      onPopped: () => popped = true,
                    ),
                  ),
                ),
                child: const Text('buka chat'),
              ),
            ),
          ),
        ),
      ),
    );

    await pumpHarness();
    await t.tap(find.text('buka chat'));
    await t.pumpAndSettle();
    expect(find.text('CHAT'), findsOneWidget);

    // Buka panel "+".
    await t.tap(find.text('+'));
    await t.pumpAndSettle();
    expect(find.text('PANEL'), findsOneWidget);

    // Tekan BACK.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    // Panel tertutup, chat masih ada, route chat TIDAK ter-pop.
    expect(panelOpen, isFalse);
    expect(find.text('PANEL'), findsNothing);
    expect(find.text('CHAT'), findsOneWidget);
    expect(popped, isFalse);

    // BACK kedua (panel sudah tertutup) → baru keluar dari chat.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.text('CHAT'), findsNothing);
    expect(find.text('buka chat'), findsOneWidget);
  });
}

class _FakeChatScreen extends StatefulWidget {
  final ValueChanged<bool> onState;
  final VoidCallback onPopped;
  const _FakeChatScreen({required this.onState, required this.onPopped});

  @override
  State<_FakeChatScreen> createState() => _FakeChatScreenState();
}

class _FakeChatScreenState extends State<_FakeChatScreen> {
  bool _panel = false;

  void _setPanel(bool v) {
    setState(() => _panel = v);
    widget.onState(v);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_panel,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          widget.onPopped();
          return;
        }
        if (_panel) _setPanel(false);
      },
      child: Scaffold(
        body: Column(
          children: [
            const Text('CHAT'),
            ElevatedButton(onPressed: () => _setPanel(true), child: const Text('+')),
            if (_panel) const Text('PANEL'),
          ],
        ),
      ),
    );
  }
}
