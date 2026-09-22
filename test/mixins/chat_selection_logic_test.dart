import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/mixins/chat_selection_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/chat_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/services/message_reaction_service.dart';

/// Harness minimal untuk `ChatSelectionMixin` — kontraknya mandiri (tidak
/// bergantung mixin lain), jadi cukup host kecil.
class SelHost extends StatefulWidget {
  final AuthProvider auth;
  final ChatProvider chat;
  const SelHost({super.key, required this.auth, required this.chat});
  @override
  State<SelHost> createState() => SelHostState();
}

class SelHostState extends State<SelHost> with ChatSelectionMixin<SelHost> {
  @override
  String get chatKind => 'private';
  @override
  String get chatId => 'chat_1';
  @override
  AuthProvider get chatAuth => widget.auth;
  @override
  ChatProvider get chatProvider => widget.chat;
  final TextEditingController msgCtrl = TextEditingController();
  @override
  TextEditingController get chatMsgCtrl => msgCtrl;
  int focusCount = 0;
  int scrollCount = 0;
  final List<String> deleted = [];
  @override
  void chatFocusComposer() => focusCount++;
  @override
  void chatScrollToBottom() => scrollCount++;
  @override
  Future<bool> chatDeleteMessage(String id) async {
    deleted.add(id);
    return true;
  }

  @override
  String chatDeletedLabel(dynamic s) => 'x';
  @override
  Map<String, String> get chatReactionKnownNames => const {};

  @override
  void dispose() {
    msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

MessageModel msg({
  String id = 'm1',
  String senderId = 'u-me',
  String text = 'halo',
  bool isDeleted = false,
  String type = 'text',
}) =>
    MessageModel(
      id: id,
      senderId: senderId,
      senderName: 'Me',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: type,
      imageData: '',
      isDeleted: isDeleted,
      timestamp: DateTime.now(),
    );

Future<SelHostState> pumpSel(WidgetTester tester) async {
  final auth = AuthProvider(autoInit: false);
  final chat = ChatProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(home: SelHost(auth: auth, chat: chat)),
    ),
  );
  return tester.state<SelHostState>(find.byType(SelHost));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => MessageReactionService.restoreInstance());

  group('ChatSelectionMixin — seleksi dasar', () {
    testWidgets('toggleSelect menambah & mengeluarkan pesan', (tester) async {
      final s = await pumpSel(tester);
      expect(s.inSelection, isFalse);

      s.toggleSelect(msg(id: 'a'));
      await tester.pump();
      expect(s.selectedIds, {'a'});
      expect(s.selectedMsgs.containsKey('a'), isTrue);
      expect(s.inSelection, isTrue);

      s.toggleSelect(msg(id: 'a'));
      await tester.pump();
      expect(s.selectedIds, isEmpty);
      expect(s.selectedMsgs, isEmpty);
    });

    testWidgets('toggleSelect menolak pesan terhapus & pending', (tester) async {
      final s = await pumpSel(tester);

      s.toggleSelect(msg(id: 'x', isDeleted: true));
      await tester.pump();
      expect(s.selectedIds, isEmpty, reason: 'pesan terhapus tidak boleh dipilih');

      s.toggleSelect(msg(id: 'pending-123'));
      await tester.pump();
      expect(s.selectedIds, isEmpty, reason: 'pesan pending tidak boleh dipilih');
    });

    testWidgets('onMessageLongPress menambah; id sama = tidak dobel',
        (tester) async {
      final s = await pumpSel(tester);
      final m = msg(id: 'b');

      s.onMessageLongPress(LongPressStartDetails(), m, LayerLink());
      await tester.pump();
      expect(s.selectedIds, {'b'});

      // Tekan lama lagi pada pesan yang sudah terpilih → tidak menambah.
      s.onMessageLongPress(LongPressStartDetails(), m, LayerLink());
      await tester.pump();
      expect(s.selectedIds.length, 1);
    });

    testWidgets('onMessageLongPress menolak pesan terhapus', (tester) async {
      final s = await pumpSel(tester);
      s.onMessageLongPress(
        LongPressStartDetails(),
        msg(id: 'del', isDeleted: true),
        LayerLink(),
      );
      await tester.pump();
      expect(s.selectedIds, isEmpty);
    });

    testWidgets('clearSelection mengosongkan dua koleksi', (tester) async {
      final s = await pumpSel(tester);
      s.toggleSelect(msg(id: 'a'));
      s.toggleSelect(msg(id: 'b'));
      await tester.pump();
      expect(s.selectedIds.length, 2);

      s.clearSelection();
      await tester.pump();
      expect(s.selectedIds, isEmpty);
      expect(s.selectedMsgs, isEmpty);
    });

    testWidgets('singleSelected hanya saat tepat 1 terpilih', (tester) async {
      final s = await pumpSel(tester);
      expect(s.singleSelected, isNull);

      s.toggleSelect(msg(id: 'a'));
      await tester.pump();
      expect(s.singleSelected?.id, 'a');

      s.toggleSelect(msg(id: 'b'));
      await tester.pump();
      expect(s.singleSelected, isNull, reason: '2 terpilih → bukan single');
    });

    testWidgets('linkFor stabil per id (LayerLink sama)', (tester) async {
      final s = await pumpSel(tester);
      final l1 = s.linkFor('m1');
      final l2 = s.linkFor('m1');
      expect(identical(l1, l2), isTrue);
      expect(identical(s.linkFor('m2'), l1), isFalse);
    });

    testWidgets('linkFor membatasi peta agar tidak tumbuh tanpa batas',
        (tester) async {
      final s = await pumpSel(tester);
      // Isi melewati cap 500 → entri lama harus mulai dibuang.
      for (var i = 0; i < 520; i++) {
        s.linkFor('id_$i');
      }
      expect(s.msgLinks.length, lessThanOrEqualTo(501));
    });
  });

  group('ChatSelectionMixin — edit & balas', () {
    testWidgets('editMessage mengisi composer + fokus + fokus count naik',
        (tester) async {
      final s = await pumpSel(tester);
      s.editMessage(msg(id: 'e', text: 'teks lama'));
      await tester.pump();

      expect(s.editingMessage?.id, 'e');
      expect(s.chatMsgCtrl.text, 'teks lama');
      expect(s.chatMsgCtrl.selection.baseOffset, 'teks lama'.length);
      expect(s.focusCount, 1);
    });

    testWidgets('editMessage membatalkan mode balas (saling eksklusif)',
        (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump();
      expect(s.replyingTo, isNotNull);

      s.editMessage(msg(id: 'e'));
      await tester.pump();
      expect(s.replyingTo, isNull, reason: 'edit membatalkan balas');
      expect(s.editingMessage, isNotNull);
    });

    testWidgets('replyMessage memicu fokus + scroll composer', (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump();

      expect(s.replyingTo?.id, 'r');
      expect(s.focusCount, 1);
      expect(s.scrollCount, 1);
    });

    testWidgets('replyMessage membatalkan mode edit', (tester) async {
      final s = await pumpSel(tester);
      s.editMessage(msg(id: 'e'));
      await tester.pump();
      expect(s.editingMessage, isNotNull);

      s.replyMessage(msg(id: 'r'));
      await tester.pump();
      expect(s.editingMessage, isNull);
    });

    testWidgets('cancelEdit reset state + kosongkan composer', (tester) async {
      final s = await pumpSel(tester);
      s.editMessage(msg(id: 'e', text: 'abc'));
      await tester.pump();

      s.cancelEdit();
      await tester.pump();
      expect(s.editingMessage, isNull);
      expect(s.chatMsgCtrl.text, isEmpty);
    });

    testWidgets('cancelReply reset replyingTo', (tester) async {
      final s = await pumpSel(tester);
      s.replyMessage(msg(id: 'r'));
      await tester.pump();

      s.cancelReply();
      await tester.pump();
      expect(s.replyingTo, isNull);
    });
  });
}
