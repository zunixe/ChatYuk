import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/core/chat/chat_location.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/widgets/chat_composer_input.dart';

/// Regresi: tombol mic/send berada di dalam ValueListenableBuilder yang
/// hanya mendengar TEKS. Memilih video/foto tidak mengubah teks → tanpa
/// pemicu tambahan tombol tetap MIC → tap merekam suara, media tak terkirim.
void main() {
  Widget host({
    String? pendingVideoPath,
    String? pendingVideoPoster,
    VoidCallback? onSend,
    ChatLocation? pendingLocation,
  }) => ChangeNotifierProvider(
    create: (_) => LocaleProvider(),
    child: MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: ChatComposerInput(
        controller: TextEditingController(),
        onSend: onSend ?? () {},
        showAttachRow: false,
        onToggleAttach: () {},
        onTakePhoto: () {},
        onSendPhoto: () {},
        onSendViewOnce: () {},
        pendingVideoPath: pendingVideoPath,
        pendingVideoPoster: pendingVideoPoster,
        pendingVideoMs: 7000,
        onCancelVideo: () {},
        onSendVideo: () {},
        pendingLocation: pendingLocation,
        onCancelLocation: () {},
      ),
    ),
    ),
  );

  testWidgets('tanpa teks & tanpa media → tombol MIC (bukan send)', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(find.byKey(const ValueKey('send')), findsNothing);
  });

  testWidgets('video pending → tombol SEND muncul (regresi)', (tester) async {
    await tester.pumpWidget(
      host(pendingVideoPath: '/tmp/v.mp4', pendingVideoPoster: 'AA=='),
    );
    expect(find.byKey(const ValueKey('send')), findsOneWidget);
  });

  testWidgets('tap tombol send dengan video pending memanggil onSend', (
    tester,
  ) async {
    var sent = 0;
    await tester.pumpWidget(
      host(
        pendingVideoPath: '/tmp/v.mp4',
        pendingVideoPoster: 'AA==',
        onSend: () => sent++,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pump();
    expect(sent, 1);
  });

  testWidgets('transisi mic→send saat video muncul (tanpa ubah teks)', (
    tester,
  ) async {
    // Awal: tidak ada video → mic.
    await tester.pumpWidget(host());
    expect(find.byKey(const ValueKey('send')), findsNothing);
    // Video muncul (parent setState) → HARUS jadi tombol send walau teks
    // tidak berubah sama sekali.
    await tester.pumpWidget(
      host(pendingVideoPath: '/tmp/v.mp4', pendingVideoPoster: 'AA=='),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send')), findsOneWidget);
  });

  testWidgets('lokasi pending → tombol SEND muncul + onSend dipanggil', (
    tester,
  ) async {
    var sent = 0;
    await tester.pumpWidget(
      host(
        pendingLocation: const ChatLocation(lat: -6.2, lng: 106.8),
        onSend: () => sent++,
      ),
    );
    // Peta mini butuh frame async (tile) — pump beberapa kali, jangan
    // pumpAndSettle (tile network tidak pernah "settle" di test).
    await tester.pump();
    expect(find.byKey(const ValueKey('send')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pump();
    expect(sent, 1);
  });
}
