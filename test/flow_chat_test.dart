import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/chat_provider.dart';
import 'package:chatyuk/services/chat_service.dart' show ChatService;

// Alur kritis 1: daftar chat → aksi pin → service terpanggil 1×.
// Hermetic: ChatService di-mock, tanpa network. Jalan di CI via
// `flutter test` biasa. (Lihat integration_test/README.md untuk
// alasan penempatan di test/ vs integration_test/.)

class MockChatService extends Mock implements ChatService {}

void main() {
  final s = S(isId: true);

  testWidgets('pin chat dari daftar memanggil service sekali', (tester) async {
    final service = MockChatService();
    when(
      () => service.pinPrivateChat(any(), any(), myUidParam: any(named: 'myUidParam')),
    ).thenAnswer((_) async {});
    final provider = ChatProvider(service: service);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ChatProvider>.value(
          value: provider,
          child: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => context.read<ChatProvider>().pinChat(
                  'c1',
                  true,
                  myUid: 'u1',
                ),
                child: Text(s.btnSave),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    verify(
      () => service.pinPrivateChat('c1', true, myUidParam: 'u1'),
    ).called(1);
    provider.dispose();
  });
}
