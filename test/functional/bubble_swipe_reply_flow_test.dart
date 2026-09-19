import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/widgets/private_chat_message.dart';

/// Functional: bubble chat nyata — swipe kanan ≥48px memicu balas,
/// <48px batal, dan pesan sendiri tidak bisa di-swipe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MessageModel msg({String id = 'm1'}) => MessageModel(
        id: id,
        senderId: 'u-other',
        senderName: 'Budi',
        senderGender: 'male',
        isRegistered: true,
        text: 'halo dunia',
        type: 'text',
        imageData: '',
        timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
      );

  Widget wrap(Widget child) => MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
          child: Scaffold(
            body: SizedBox(width: 360, height: 200, child: child),
          ),
        ),
      );

  Widget bubble({
    required MessageModel m,
    required bool isMe,
    VoidCallback? onSwipeReply,
    bool enabled = true,
  }) =>
      MessageBubble(
        msg: m,
        chatKey: 'chat_1',
        isMe: isMe,
        isRead: false,
        link: LayerLink(),
        onSwipeReply: enabled ? (onSwipeReply ?? () {}) : null,
      );

  testWidgets('drag kanan cukup jauh → onSwipeReply terpanggil',
      (tester) async {
    var replied = 0;
    await tester.pumpWidget(wrap(
      bubble(m: msg(), isMe: false, onSwipeReply: () => replied++),
    ));

    await tester.drag(find.byType(MessageBubble), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(replied, 1);
  });

  testWidgets('drag kanan sedikit (<48px) → tidak memicu balas',
      (tester) async {
    var replied = 0;
    await tester.pumpWidget(wrap(
      bubble(m: msg(), isMe: false, onSwipeReply: () => replied++),
    ));

    await tester.drag(find.byType(MessageBubble), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(replied, 0);
  });

  testWidgets('onSwipeReply null (pesan sendiri) → tidak ada aksi',
      (tester) async {
    await tester.pumpWidget(wrap(
      bubble(m: msg(), isMe: true, enabled: false),
    ));

    // Tidak ada GestureDetector swipe; drag tidak melempar.
    await tester.drag(find.byType(MessageBubble), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pesan tampil teksnya', (tester) async {
    await tester.pumpWidget(wrap(bubble(m: msg(), isMe: false)));
    // Bubble teks dirender RichText (MessageTextWithTime), bukan Text.
    expect(
      find.textContaining('halo dunia', findRichText: true),
      findsOneWidget,
    );
  });
}
